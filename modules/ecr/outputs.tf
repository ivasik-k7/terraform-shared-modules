# ---------------------------------------------------------------------------
# Resources: what callers wire to their other resources.
# ---------------------------------------------------------------------------

output "repository_names" {
  description = "Repository name by key (the key itself)."
  value       = { for k, r in aws_ecr_repository.this : k => r.name }
}

output "repository_arns" {
  description = "Repository ARN by key."
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}

output "repository_urls" {
  description = "Repository URL by key: <account>.dkr.ecr.<region>.amazonaws.com/<name>, what docker push and an image reference use."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "registry_url" {
  description = "The registry host, <account>.dkr.ecr.<region>.amazonaws.com: what docker login takes, and the prefix of pull through cache images (<registry_url>/<prefix>/<upstream image>)."
  value       = local.create ? local.registry_url : null
}

output "registry_id" {
  description = "The registry ID, which is the account ID."
  value       = local.create ? local.account_id : null
}

output "creation_template_role_arn" {
  description = "The role ECR creates templated repositories with. Null without creation_templates."
  value       = one(aws_iam_role.templates[*].arn)
}

# ---------------------------------------------------------------------------
# Identity policies for the roles that use the images
# ---------------------------------------------------------------------------

output "pull_policy_json" {
  description = "IAM policy for a role that pulls from every repository of this module (an ECS execution role, a CI runner, a node role): the three pull actions on exactly these repositories, and ecr:GetAuthorizationToken, which has no resource-level permissions. Null without repositories."
  value = !local.create || length(local.repositories) == 0 ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "PullImages", Effect = "Allow", Action = local.pull_actions, Resource = sort([for k, r in local.repositories : "${local.registry_arn}/${k}"]) },
      { Sid = "GetAuthorizationToken", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    ]
  })
}

output "push_policy_json" {
  description = "IAM policy for a role that builds and pushes to every repository of this module: pull and push actions on exactly these repositories, and ecr:GetAuthorizationToken. Null without repositories."
  value = !local.create || length(local.repositories) == 0 ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "PushImages", Effect = "Allow", Action = local.push_actions, Resource = sort([for k, r in local.repositories : "${local.registry_arn}/${k}"]) },
      { Sid = "GetAuthorizationToken", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    ]
  })
}

output "pull_through_cache_policy_json" {
  description = "IAM policy for a role that pulls through the cache: the first pull of an upstream image creates the cache repository and imports the image, which needs ecr:CreateRepository and ecr:BatchImportUpstreamImage beside the pull actions. Null without pull_through_cache."
  value = length(local.pull_through_cache) == 0 ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "PullThroughCache", Effect = "Allow", Action = concat(local.pull_actions, ["ecr:BatchImportUpstreamImage", "ecr:CreateRepository"]), Resource = [for p in sort(keys(local.pull_through_cache)) : "${local.registry_arn}/${p}/*"] },
      { Sid = "GetAuthorizationToken", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    ]
  })
}

# ---------------------------------------------------------------------------
# Contracts: facts another team acts on, as data rather than prose.
# ---------------------------------------------------------------------------

output "governance" {
  description = "The posture of these repositories and of the registry as data: assert on it in tests, diff it in a change review."
  value = !local.create ? null : {
    tag_mutability              = { for k, m in local.mutability_sent : k => m }
    tag_mutability_exclusions   = { for k, r in local.repositories : k => r.tag_mutability_exclusions if length(r.tag_mutability_exclusions) > 0 }
    encryption                  = { for k, key in local.repository_key : k => key != "" ? key : "AES256" }
    scan_on_push                = local.scan_on_push
    lifecycle_rules             = { for k, r in local.repositories : k => length(local.lifecycle_rules["repository ${k}"]) }
    unbounded_storage           = local.unbounded_repositories
    cross_account_principals    = local.cross_account_principals
    organization_pull           = { for k, r in local.repositories : k => r.access.pull_organization_ids if length(r.access.pull_organization_ids) > 0 }
    lambda_accounts             = { for k, r in local.repositories : k => r.access.lambda_accounts if length(r.access.lambda_accounts) > 0 }
    force_delete                = sort([for k, r in local.repositories : k if r.force_delete])
    registry_managed_here       = local.registry_on
    registry_scanning           = local.registry_on ? (var.registry.scanning != null ? var.registry.scanning.type : "not managed") : "not managed"
    replication_destinations    = sort(distinct(flatten([for r in local.replication_rules : [for d in r.destinations : "${d.region}/${d.account_id != "" ? d.account_id : local.account_id}"]])))
    replication_source_accounts = local.registry_on ? sort(var.registry.replication_source_accounts) : []
    pull_through_cache          = { for p, c in local.pull_through_cache : p => c.upstream }
    cache_templates             = local.template_for
    creation_templates          = { for p, t in local.templates : p => sort(t.applied_for) }
    account_settings            = local.registry_on ? { for n, v in var.registry.account_settings : n => v if v != "" } : {}
    event_rules                 = sort(keys(local.event_rules))
    required_tag_keys           = sort(var.required_tag_keys)
    acknowledged_checks         = sort(var.acknowledged_checks)
  }
}

output "kms_key_policy_requirements" {
  description = "What each customer managed key's policy has to allow, in contract version 2: key, sid, principals = { services, arns, roles }, actions, conditions = [{ test, variable, values }], purpose. Known at plan. The symbolic role deployer is whoever runs Terraform, which must also hold kms:RetireGrant in its own IAM policy (output.deployer_requirements)."
  value = !local.create ? null : concat(
    [for i, key in local.repository_keys : {
      key        = key
      sid        = "RepositoryGrants${i}"
      principals = { services = [], arns = [], roles = ["deployer"] }
      actions    = ["kms:CreateGrant", "kms:DescribeKey"]
      conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["ecr.${local.region}.amazonaws.com"] }]
      purpose    = "Creating a repository with this key makes ECR describe it and create the grants it encrypts and decrypts images with, as the caller. Without it the repository create fails. Pullers need nothing on the key: ECR decrypts through its grant."
    }],
    [for i, key in local.template_keys : {
      key        = key
      sid        = "TemplateGrants${i}"
      principals = { services = [], arns = [local.template_role_arn], roles = [] }
      actions    = ["kms:CreateGrant", "kms:DescribeKey", "kms:RetireGrant"]
      conditions = []
      purpose    = "ECR creates the repositories of a creation template with this key as the template role. Without it, the first pull through the cache, or the first replica, fails to create its repository."
    }],
  )
}

output "deployer_requirements" {
  description = "IAM the principal running Terraform needs besides managing the module's resources: kms:RetireGrant on the repository keys (ECR requires it in the caller's own policy), iam:PassRole on the template role, the ECR and Inspector service-linked roles AWS creates on first use, and the Inspector actions enhanced scanning needs. Attach iam_policy to the HCP Terraform apply role."
  value = !local.create ? null : {
    iam_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[${join(",", local.deployer_statements)}]}"
  }
}

output "replication_destination_requirements" {
  description = "For each destination account of registry.replication that is not this one: the registry policy statement its owner must add (in each destination Region), or replication into it fails. Give the destination registry a REPLICATION creation template too, or replicas get mutable tags, AES-256 and no lifecycle policy. Pass this module's account as replication_source_accounts there, if it uses this module."
  value = { for a in local.replication_destination_accounts : a => {
    regions = sort(distinct(flatten([for r in local.replication_rules : [for d in r.destinations : d.region if d.account_id == a]])))
    registry_policy_statement = {
      Sid       = "ReplicationFrom${local.account_id}"
      Effect    = "Allow"
      Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
      Action    = ["ecr:CreateRepository", "ecr:ReplicateImage"]
      Resource  = "arn:${local.partition}:ecr:<region>:${a}:repository/*"
    }
  } }
}

output "notification_requirements" {
  description = "What sns_topic_arn's access policy must allow, as policy statements: EventBridge publishing from this module's rules. A topic that denies them drops every notification while the rules show as healthy. Null without a topic."
  value = !local.create || length(local.event_rules) == 0 ? null : {
    topic = var.sns_topic_arn
    topic_policy_statements = [{
      Sid       = "EcrEventRules"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = var.sns_topic_arn
      Condition = { ArnLike = { "aws:SourceArn" = "arn:${local.partition}:events:${local.region}:${local.account_id}:rule/${var.name}-ecr-*" } }
    }]
  }
}

output "network_contract" {
  description = <<-EOT
    What pushing and pulling need from YOUR network, as data. The module creates no network resources. In a
    subnet without a route to the internet, a missing endpoint shows as a pull that hangs or fails with
    CannotPullContainerError, not as an error at apply.
  EOT
  value = !local.create ? null : {
    required_interface_endpoints = ["com.amazonaws.${local.region}.ecr.api", "com.amazonaws.${local.region}.ecr.dkr"]
    gateway_endpoints            = ["com.amazonaws.${local.region}.s3"]
    notes = compact([
      "ecr.dkr needs private DNS enabled; ECR serves image layers from S3, so a pull fails after authentication without the S3 gateway endpoint or another S3 path (https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html).",
      length(local.pull_through_cache) == 0 ? "" : "The first pull of an upstream image through the cache needs the VPC to reach the internet through a NAT gateway, even with the endpoints; later pulls do not (same page).",
    ])
  }
}

output "verify_commands" {
  description = "Copy-paste checks for CloudShell after an apply. Maps are keyed by repository."
  value = !local.create ? null : {
    repositories       = length(local.repositories) == 0 ? "" : "aws ecr describe-repositories --repository-names ${join(" ", sort(keys(local.repositories)))} --query 'repositories[].[repositoryName,imageTagMutability,encryptionConfiguration.encryptionType]' --output table"
    images             = { for k, r in local.repositories : k => "aws ecr describe-images --repository-name ${k} --query 'sort_by(imageDetails,&imagePushedAt)[-10:].[imageTags[0],imagePushedAt,imageSizeInBytes,lastRecordedPullTime]' --output table" }
    lifecycle_preview  = { for k, r in local.repositories : k => "aws ecr start-lifecycle-policy-preview --repository-name ${k} && sleep 10 && aws ecr get-lifecycle-policy-preview --repository-name ${k} --query 'summary' --output json" if local.lifecycle_json["repository ${k}"] != "" }
    scan_findings      = { for k, r in local.repositories : k => "aws ecr describe-image-scan-findings --repository-name ${k} --image-id imageTag=<tag> --query 'imageScanFindings.findingSeverityCounts' --output json" }
    login              = "aws ecr get-login-password | docker login --username AWS --password-stdin ${local.registry_url}"
    registry           = local.registry_on ? "aws ecr describe-registry --query '[registryId,replicationConfiguration]' --output json && aws ecr get-registry-scanning-configuration --output json" : ""
    pull_through_cache = local.registry_on ? (length(local.pull_through_cache) == 0 ? "" : "aws ecr validate-pull-through-cache-rule --ecr-repository-prefix <prefix> (one of: ${join(", ", sort(keys(local.pull_through_cache)))})") : ""
  }
}
