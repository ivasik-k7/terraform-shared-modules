locals {
  create = var.create

  module_tags = {
    "ManagedBy" = "Terraform"
    "Module"    = "s3"
    "Bucket"    = var.name
  }
  common_tags = merge(var.tags, local.module_tags)

  partition = coalesce(one(data.aws_partition.current[*].partition), "aws")
  # Provider 6.x deprecates aws_region.name and 5.x has no aws_region.region; endpoint is in both.
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/version-6-upgrade
  region     = try(split(".", one(data.aws_region.current[*].endpoint))[1], "us-east-1")
  account_id = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")

  acknowledged = toset(var.acknowledged_checks)

  suffixed    = var.name_suffix == "account-region"
  bucket_name = local.suffixed ? "${var.name}-${local.account_id}-${local.region}" : var.name
  bucket_arn  = "arn:${local.partition}:s3:::${local.bucket_name}"
  objects_arn = "${local.bucket_arn}/*"

  uses_kms      = var.kms_key_arn != ""
  sse_algorithm = local.uses_kms ? (var.encryption.dsse ? "aws:kms:dsse" : "aws:kms") : "AES256"
  # S3 Bucket Keys aren't supported for DSSE-KMS.
  # https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingDSSEncryption.html
  bucket_key = local.uses_kms && !var.encryption.dsse ? var.encryption.bucket_key : false

  key_in_another_region = local.uses_kms ? !strcontains(var.kms_key_arn, ":${local.region}:") : false

  public_access_relaxed = !alltrue(values(var.public_access_block))

  read_actions  = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetObjectTagging", "s3:GetObjectAttributes"]
  write_actions = ["s3:PutObject", "s3:PutObjectTagging", "s3:AbortMultipartUpload", "s3:DeleteObject"]
  grant_object_resources = {
    for k, g in var.grants : k => [for p in g.prefixes : "${local.bucket_arn}/${p}*"]
  }
  grant_list_prefixes = {
    for k, g in var.grants : k => [for p in g.prefixes : "${p}*"]
  }

  default_rule_on = anytrue([
    var.versioning ? var.default_lifecycle.noncurrent_version_expiration_days > 0 : false,
    var.default_lifecycle.abort_incomplete_multipart_days > 0,
    var.versioning ? var.default_lifecycle.expired_object_delete_marker : false,
  ])
  lifecycle_on = local.default_rule_on || length(var.lifecycle_rules) > 0

  lifecycle_filter_count = {
    for k, r in var.lifecycle_rules : k => (
      (r.prefix != "" ? 1 : 0) + length(r.tags) + (r.object_size_greater_than > 0 ? 1 : 0) + (r.object_size_less_than > 0 ? 1 : 0)
    )
  }

  replication_on          = length(var.replication.rules) > 0
  create_replication_role = local.create && local.replication_on && var.replication.create_role
  replication_role_name   = "${var.name}-${local.region}-s3-replication"
  replication_role_arn    = var.replication.create_role ? "arn:${local.partition}:iam::${local.account_id}:role/${local.replication_role_name}" : var.replication.role_arn

  replica_keys        = distinct(compact([for r in values(var.replication.rules) : r.replica_kms_key_arn]))
  replication_buckets = distinct([for r in values(var.replication.rules) : r.destination_bucket_arn])
  key_region          = { for k in local.replica_keys : k => split(":", k)[3] }

  # With an S3 Bucket Key the replication encryption context is the bucket ARN, otherwise the object ARN.
  # https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-config-for-kms-objects.html#bk-replication
  replication_statements = concat(
    [
      {
        sid       = "ReadReplicationConfiguration"
        actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        resources = [local.bucket_arn]
        condition = []
      },
      {
        sid = "ReadSourceVersions"
        actions = concat(
          ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"],
          var.object_lock.enabled ? ["s3:GetObjectRetention", "s3:GetObjectLegalHold"] : [],
        )
        resources = [local.objects_arn]
        condition = []
      },
      {
        sid       = "ReplicateToDestinations"
        actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
        resources = [for b in local.replication_buckets : "${b}/*"]
        condition = []
      },
    ],
    !local.uses_kms ? [] : [{
      sid       = "DecryptSourceObjects"
      actions   = ["kms:Decrypt"]
      resources = [var.kms_key_arn]
      condition = [
        { test = "StringLike", variable = "kms:ViaService", values = ["s3.${local.region}.amazonaws.com"] },
        { test = "StringLike", variable = "kms:EncryptionContext:aws:s3:arn", values = [local.bucket_arn, "${local.objects_arn}"] },
      ]
    }],
    [for k in local.replica_keys : {
      sid       = "EncryptReplicas${substr(sha1(k), 0, 8)}"
      actions   = ["kms:Encrypt", "kms:GenerateDataKey", "kms:Decrypt"]
      resources = [k]
      condition = [
        { test = "StringLike", variable = "kms:ViaService", values = ["s3.${local.key_region[k]}.amazonaws.com"] },
        { test = "StringLike", variable = "kms:EncryptionContext:aws:s3:arn", values = flatten([
          for r in values(var.replication.rules) : [r.destination_bucket_arn, "${r.destination_bucket_arn}/*"] if r.replica_kms_key_arn == k
        ]) },
      ]
    }],
  )

  notifications_on = anytrue([
    var.notifications.eventbridge,
    length(var.notifications.topics) > 0,
    length(var.notifications.queues) > 0,
    length(var.notifications.lambda_functions) > 0,
  ])

  # Service-to-service calls carry no network context; a network Deny exempts them with aws:PrincipalIsAWSService.
  # https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html#condition-keys-sourcevpce
  not_a_service = { test = "BoolIfExists", variable = "aws:PrincipalIsAWSService", values = ["false"] }
  # Forward access sessions (Athena, Glue) carry no aws:SourceVpce, and aws:ViaAWSService is true for them.
  # https://docs.aws.amazon.com/IAM/latest/UserGuide/access_forward_access_sessions.html
  not_via_a_service = { test = "BoolIfExists", variable = "aws:ViaAWSService", values = ["false"] }

  object_data_actions = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject", "s3:DeleteObjectVersion"]

  module_policy_statements = concat(
    [
      {
        sid        = "DenyInsecureTransport"
        effect     = "Deny"
        principals = { AWS = ["*"] }
        actions    = ["s3:*"]
        resources  = [local.bucket_arn, local.objects_arn]
        conditions = [{ test = "Bool", variable = "aws:SecureTransport", values = ["false"] }, local.not_a_service]
      },
      {
        sid        = "DenyOldTls"
        effect     = "Deny"
        principals = { AWS = ["*"] }
        actions    = ["s3:*"]
        resources  = [local.bucket_arn, local.objects_arn]
        conditions = [{ test = "NumericLessThan", variable = "s3:TlsVersion", values = [var.minimum_tls_version] }, local.not_a_service]
      },
    ],
    local.uses_kms && var.encryption.enforce_kms_key ? [
      {
        sid        = "DenyOtherEncryption"
        effect     = "Deny"
        principals = { AWS = ["*"] }
        actions    = ["s3:PutObject"]
        resources  = [local.objects_arn]
        conditions = [
          { test = "Null", variable = "s3:x-amz-server-side-encryption", values = ["false"] },
          { test = "StringNotEquals", variable = "s3:x-amz-server-side-encryption", values = [local.sse_algorithm] },
        ]
      },
      {
        sid        = "DenyOtherKmsKeys"
        effect     = "Deny"
        principals = { AWS = ["*"] }
        actions    = ["s3:PutObject"]
        resources  = [local.objects_arn]
        conditions = [
          { test = "Null", variable = "s3:x-amz-server-side-encryption-aws-kms-key-id", values = ["false"] },
          { test = "StringNotEquals", variable = "s3:x-amz-server-side-encryption-aws-kms-key-id", values = [var.kms_key_arn] },
        ]
      },
      {
        # PutObject with aws:kms and no key id encrypts under the AWS managed key aws/s3.
        # https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObject.html
        sid        = "DenyAwsManagedKey"
        effect     = "Deny"
        principals = { AWS = ["*"] }
        actions    = ["s3:PutObject"]
        resources  = [local.objects_arn]
        conditions = [
          { test = "StringEquals", variable = "s3:x-amz-server-side-encryption", values = [local.sse_algorithm] },
          { test = "Null", variable = "s3:x-amz-server-side-encryption-aws-kms-key-id", values = ["true"] },
        ]
      },
    ] : [],
    length(var.vpc_endpoint_ids) == 0 ? [] : [{
      sid        = "DenyObjectAccessOutsideVpcEndpoints"
      effect     = "Deny"
      principals = { AWS = ["*"] }
      actions    = local.object_data_actions
      resources  = [local.objects_arn]
      conditions = [{ test = "StringNotEqualsIfExists", variable = "aws:SourceVpce", values = var.vpc_endpoint_ids }, local.not_a_service, local.not_via_a_service]
    }],
    var.organization_id == "" ? [] : [{
      sid        = "DenyObjectAccessOutsideOrganization"
      effect     = "Deny"
      principals = { AWS = ["*"] }
      actions    = local.object_data_actions
      resources  = [local.objects_arn]
      conditions = [
        { test = "StringNotEqualsIfExists", variable = "aws:PrincipalOrgID", values = [var.organization_id] },
        { test = "StringNotEquals", variable = "aws:PrincipalAccount", values = [local.account_id] },
        local.not_a_service,
      ]
    }],
    flatten([for k, g in var.grants : concat(
      [{
        sid        = "${k}List"
        effect     = "Allow"
        principals = { AWS = g.principals }
        actions    = ["s3:ListBucket"]
        resources  = [local.bucket_arn]
        conditions = contains(g.prefixes, "") ? [] : [{ test = "StringLike", variable = "s3:prefix", values = local.grant_list_prefixes[k] }]
      }],
      [{
        sid        = "${k}Objects"
        effect     = "Allow"
        principals = { AWS = g.principals }
        actions    = g.access == "read" ? local.read_actions : (g.access == "write" ? local.write_actions : concat(local.read_actions, local.write_actions))
        resources  = local.grant_object_resources[k]
        conditions = []
      }],
    )]),
    length(var.cloudfront_distribution_arns) == 0 ? [] : [{
      sid        = "CloudFrontOriginAccessControl"
      effect     = "Allow"
      principals = { Service = ["cloudfront.amazonaws.com"] }
      actions    = ["s3:GetObject"]
      resources  = [local.objects_arn]
      conditions = [{ test = "StringEquals", variable = "AWS:SourceArn", values = var.cloudfront_distribution_arns }]
    }],
    length(var.access_log_sources) == 0 ? [] : [{
      sid        = "ServerAccessLogDelivery"
      effect     = "Allow"
      principals = { Service = ["logging.s3.amazonaws.com"] }
      actions    = ["s3:PutObject"]
      resources  = [local.objects_arn]
      conditions = [
        { test = "ArnLike", variable = "aws:SourceArn", values = var.access_log_sources },
        { test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] },
      ]
    }],
  )

  caller_policy_statements = [for s in var.policy_statements : merge(s, {
    resources = [for r in s.resources : replace(replace(r, "OBJECTS_ARN", local.objects_arn), "BUCKET_ARN", local.bucket_arn)]
  })]

  policy_statements = concat(local.module_policy_statements, local.caller_policy_statements)

  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [for s in local.policy_statements : merge(
      { Sid = s.sid, Effect = s.effect, Action = s.actions, Resource = s.resources },
      # Both results of a conditional need one type, and "*" does not unify with an object.
      { Principal = jsondecode(jsonencode(s.principals) == jsonencode({ AWS = ["*"] }) ? jsonencode("*") : jsonencode(s.principals)) },
      length(s.conditions) == 0 ? {} : {
        Condition = { for test in distinct([for c in s.conditions : c.test]) : test => {
          for c in s.conditions : c.variable => c.values if c.test == test
        } }
      },
    )]
  })

  kms_for_readers = !local.uses_kms ? [] : [{
    Sid       = "DecryptObjects"
    Effect    = "Allow"
    Action    = ["kms:Decrypt"]
    Resource  = [var.kms_key_arn]
    Condition = { StringEquals = { "kms:ViaService" = "s3.${local.region}.amazonaws.com" } }
  }]
  kms_for_writers = !local.uses_kms ? [] : [{
    Sid       = "EncryptObjects"
    Effect    = "Allow"
    Action    = ["kms:GenerateDataKey", "kms:Decrypt"]
    Resource  = [var.kms_key_arn]
    Condition = { StringEquals = { "kms:ViaService" = "s3.${local.region}.amazonaws.com" } }
  }]
}
