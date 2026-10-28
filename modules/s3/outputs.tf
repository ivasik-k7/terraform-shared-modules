output "bucket" {
  description = "Bucket name (with the account and region suffix, if used)."
  value       = one(aws_s3_bucket.this[*].bucket)
}

output "arn" {
  description = "Bucket ARN."
  value       = one(aws_s3_bucket.this[*].arn)
}

output "regional_domain_name" {
  description = "Regional domain name: the origin for CloudFront and the endpoint for VPC-local clients."
  value       = one(aws_s3_bucket.this[*].bucket_regional_domain_name)
}

output "region" {
  description = "The bucket's region."
  value       = local.create ? local.region : null
}

output "replication_role_arn" {
  description = "The replication role in use, or null."
  value       = local.create && local.replication_on ? local.replication_role_arn : null
}

output "read_policy_json" {
  description = "An IAM policy for principals in this account that read the bucket: list, get objects and versions, and decrypt with the bucket's key through S3. Attach it; the module attaches it to nobody."
  value = !local.create ? null : jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        { Sid = "ListBucket", Effect = "Allow", Action = ["s3:ListBucket", "s3:ListBucketVersions", "s3:GetBucketLocation"], Resource = [local.bucket_arn] },
        { Sid = "ReadObjects", Effect = "Allow", Action = local.read_actions, Resource = [local.objects_arn] },
      ],
      local.kms_for_readers,
    )
  })
}

output "write_policy_json" {
  description = "An IAM policy for principals in this account that read and write the bucket: everything in read_policy_json, plus put, tag, delete and abort uploads, and encrypt with the bucket's key through S3."
  value = !local.create ? null : jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        { Sid = "ListBucket", Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"], Resource = [local.bucket_arn] },
        { Sid = "ReadWriteObjects", Effect = "Allow", Action = concat(local.read_actions, local.write_actions, ["s3:ListMultipartUploadParts"]), Resource = [local.objects_arn] },
      ],
      local.kms_for_writers,
    )
  })
}

output "kms_key_policy_requirements" {
  description = "What each customer managed key's policy has to allow for this bucket, in contract version 2 (modules/kms compiles it): key, sid, principals = { services, arns, roles }, actions, conditions = [{ test, variable, values }], purpose. Symbolic roles: deployer runs Terraform, bucket_readers and bucket_writers hold read_policy_json and write_policy_json."
  value = !local.create ? null : concat(
    !local.uses_kms ? [] : concat(
      [
        {
          key        = var.kms_key_arn
          sid        = "BucketWriters"
          principals = { services = [], arns = [], roles = ["bucket_writers"] }
          actions    = ["kms:GenerateDataKey", "kms:Decrypt"]
          conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["s3.${local.region}.amazonaws.com"] }]
          purpose    = "Writers encrypt new objects through S3 with the bucket's key."
        },
        {
          key        = var.kms_key_arn
          sid        = "BucketReaders"
          principals = { services = [], arns = [], roles = ["bucket_readers"] }
          actions    = ["kms:Decrypt"]
          conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["s3.${local.region}.amazonaws.com"] }]
          purpose    = "Readers decrypt objects through S3."
        },
      ],
      [for k, g in var.grants : {
        key        = var.kms_key_arn
        sid        = "Grant${k}"
        principals = { services = [], arns = g.principals, roles = [] }
        actions    = g.access == "read" ? ["kms:Decrypt"] : ["kms:GenerateDataKey", "kms:Decrypt"]
        conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["s3.${local.region}.amazonaws.com"] }]
        purpose    = "The bucket policy grant ${k} reads${g.access == "read" ? "" : " and writes"} objects encrypted with this key."
      }],
      length(var.cloudfront_distribution_arns) == 0 ? [] : [{
        key        = var.kms_key_arn
        sid        = "CloudFrontOriginAccessControl"
        principals = { services = ["cloudfront.amazonaws.com"], arns = [], roles = [] }
        actions    = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*"]
        conditions = [{ test = "StringEquals", variable = "AWS:SourceArn", values = var.cloudfront_distribution_arns }]
        purpose    = "CloudFront reads encrypted objects through Origin Access Control."
      }],
      local.replication_on ? [{
        key        = var.kms_key_arn
        sid        = "ReplicationSource"
        principals = { services = [], arns = [local.replication_role_arn], roles = [] }
        actions    = ["kms:Decrypt"]
        conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["s3.${local.region}.amazonaws.com"] }]
        purpose    = "Replication decrypts source objects."
      }] : [],
    ),
    [for k in local.replica_keys : {
      key        = k
      sid        = "ReplicationDestination${substr(sha1(k), 0, 8)}"
      principals = { services = [], arns = [local.replication_role_arn], roles = [] }
      actions    = ["kms:Encrypt", "kms:GenerateDataKey", "kms:Decrypt"]
      conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["s3.${local.key_region[k]}.amazonaws.com"] }]
      purpose    = "Replication encrypts replicas at the destination."
    }],
  )
}

output "replication_destination_requirements" {
  description = "For each replication destination bucket: the bucket policy statement its owner adds when it is in another account (the role may replicate into it and read its versioning), and what it must have on (versioning). Null without replication."
  value = !local.create || !local.replication_on ? null : {
    for b in local.replication_buckets : b => {
      versioning       = "Enabled"
      object_ownership = "BucketOwnerEnforced - the destination account then owns the replicas"
      bucket_policy_statements = jsonencode([
        {
          Sid       = "ReplicationObjects"
          Effect    = "Allow"
          Principal = { AWS = local.replication_role_arn }
          Action    = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
          Resource  = "${b}/*"
        },
        {
          Sid       = "ReplicationBucket"
          Effect    = "Allow"
          Principal = { AWS = local.replication_role_arn }
          Action    = ["s3:List*", "s3:GetBucketVersioning", "s3:PutBucketVersioning"]
          Resource  = b
        },
      ])
    }
  }
}

output "notification_destination_requirements" {
  description = "The resource policy statement each notification destination needs before the apply - S3 tests delivery when the configuration is written and refuses it otherwise. For KMS-encrypted queues and topics, the key also needs s3.amazonaws.com with kms:GenerateDataKey and kms:Decrypt. Lambda functions: an aws_lambda_permission with these values."
  value = !local.create || !local.notifications_on ? null : {
    topics = { for k, t in var.notifications.topics : k => jsonencode({
      Sid       = "S3Notifications"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = t.arn
      Condition = { ArnEquals = { "aws:SourceArn" = local.bucket_arn }, StringEquals = { "aws:SourceAccount" = local.account_id } }
    }) }
    queues = { for k, q in var.notifications.queues : k => jsonencode({
      Sid       = "S3Notifications"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "SQS:SendMessage"
      Resource  = q.arn
      Condition = { ArnEquals = { "aws:SourceArn" = local.bucket_arn }, StringEquals = { "aws:SourceAccount" = local.account_id } }
    }) }
    lambda_functions = { for k, l in var.notifications.lambda_functions : k => {
      function_name  = l.arn
      action         = "lambda:InvokeFunction"
      principal      = "s3.amazonaws.com"
      source_arn     = local.bucket_arn
      source_account = local.account_id
    } }
  }
}

output "inventory_destination_requirements" {
  description = "The bucket policy statement each inventory destination bucket needs, as the S3 documentation gives it, and the key policy statement for a destination_kms_key. Null without inventory."
  value = !local.create || length(var.inventory) == 0 ? null : {
    for k, i in var.inventory : k => {
      bucket_policy_statement = jsonencode({
        Sid       = "S3Inventory"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${i.destination_bucket_arn}/*"
        Condition = {
          ArnLike      = { "aws:SourceArn" = local.bucket_arn }
          StringEquals = { "aws:SourceAccount" = local.account_id, "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      })
      key_policy_statement = i.destination_kms_key == "" ? null : jsonencode({
        Sid       = "S3InventoryEncryption"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "kms:GenerateDataKey"
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id }, ArnLike = { "aws:SourceArn" = local.bucket_arn } }
      })
    }
  }
}

output "governance" {
  description = "The posture of the bucket as data: assert on it in tests, diff it in a change review."
  value = !local.create ? null : {
    name_suffix            = var.name_suffix
    versioning             = var.versioning
    encryption             = local.sse_algorithm
    customer_key           = local.uses_kms
    bucket_key             = local.bucket_key
    object_lock            = var.object_lock.enabled ? "${var.object_lock.mode}${var.object_lock.days > 0 ? " ${var.object_lock.days} days" : ""}${var.object_lock.years > 0 ? " ${var.object_lock.years} years" : ""}" : null
    object_ownership       = var.object_ownership
    public_access_blocked  = !local.public_access_relaxed
    minimum_tls_version    = var.minimum_tls_version
    vpc_endpoint_only      = length(var.vpc_endpoint_ids) > 0
    organization_only      = var.organization_id != ""
    cross_account_grants   = { for k, g in var.grants : k => g.access }
    cloudfront             = length(var.cloudfront_distribution_arns)
    access_logged          = var.access_logging.enabled
    log_bucket_for         = var.access_log_sources
    noncurrent_expiry_days = var.versioning ? var.default_lifecycle.noncurrent_version_expiration_days : null
    replication            = { for k, r in var.replication.rules : k => r.destination_bucket_arn }
    force_destroy          = var.force_destroy
    acknowledged_checks    = sort(var.acknowledged_checks)
  }
}

output "verify_commands" {
  description = "AWS CLI commands to run from CloudShell after an apply. plain_http_is_denied passes when it returns 403; a 404 means plain HTTP reached the bucket."
  value = !local.create ? null : {
    encryption           = "aws s3api get-bucket-encryption --bucket ${local.bucket_name}"
    public_access        = "aws s3api get-public-access-block --bucket ${local.bucket_name}"
    policy_status        = "aws s3api get-bucket-policy-status --bucket ${local.bucket_name} --query PolicyStatus.IsPublic"
    versioning           = "aws s3api get-bucket-versioning --bucket ${local.bucket_name}"
    lifecycle            = "aws s3api get-bucket-lifecycle-configuration --bucket ${local.bucket_name}"
    replication          = local.replication_on ? "aws s3api get-bucket-replication --bucket ${local.bucket_name}" : "no replication"
    plain_http_is_denied = "aws s3api head-object --bucket ${local.bucket_name} --key verify-no-such-key --endpoint-url http://s3.${local.region}.amazonaws.com"
  }
}
