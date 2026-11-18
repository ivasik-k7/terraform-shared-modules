locals {
  create = var.create

  # Module keys last, so a caller's tags cannot override them.
  module_tags = {
    "ManagedBy" = "Terraform"
    "Module"    = "ecr"
  }
  common_tags = merge(var.tags, local.module_tags)

  # Placeholders so ARN strings still build when create = false.
  partition  = coalesce(one(data.aws_partition.current[*].partition), "aws")
  region     = coalesce(one(data.aws_region.current[*].region), "us-east-1")
  account_id = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")

  acknowledged = toset(var.acknowledged_checks)

  registry_arn = "arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository"
  registry_url = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"

  # ---------------------------------------------------------------------------
  # Repositories
  # ---------------------------------------------------------------------------

  repositories = local.create ? var.repositories : {}

  mutability = { for k, r in local.repositories : k => r.image_tag_mutability != "" ? r.image_tag_mutability : var.image_tag_mutability }
  # A repository with exclusions is sent as the matching *_WITH_EXCLUSION mode.
  mutability_sent = { for k, r in local.repositories : k => length(r.tag_mutability_exclusions) > 0 ? "${local.mutability[k]}_WITH_EXCLUSION" : local.mutability[k] }
  repository_key  = { for k, r in local.repositories : k => r.kms_key_arn != "" ? r.kms_key_arn : var.kms_key_arn }
  scan_on_push    = { for k, r in local.repositories : k => r.scan_on_push != null ? r.scan_on_push : var.scan_on_push }
  repository_tags = { for k, r in local.repositories : k => merge(var.tags, r.tags, local.module_tags) }

  # ---------------------------------------------------------------------------
  # Lifecycle policies, for repositories and creation templates alike
  # ---------------------------------------------------------------------------

  templates   = local.registry_on ? var.registry.creation_templates : {}
  registry_on = local.create ? var.registry.enabled : false

  lifecycle_owners = merge(
    { for k, r in local.repositories : "repository ${k}" => r.lifecycle_policy != null ? r.lifecycle_policy : var.lifecycle_policy },
    { for p, t in local.templates : "template ${p}" => t.lifecycle_policy },
  )

  # Each rule is rendered on its own, so rules of different shapes can share
  # a policy; the policy is joined from them.
  # https://docs.aws.amazon.com/AmazonECR/latest/userguide/lifecycle_policy_parameters.html
  lifecycle_rules = { for o, p in local.lifecycle_owners : o => !p.enabled ? [] : (length(p.rules) > 0 ? [
    for r in p.rules : jsonencode(merge(
      { rulePriority = r.priority },
      r.description != "" ? { description = r.description } : {},
      {
        selection = merge(
          { tagStatus = r.tag_status, countType = r.count_type, countNumber = r.count },
          r.count_type != "imageCountMoreThan" ? { countUnit = "days" } : {},
          length(r.tag_patterns) > 0 ? { tagPatternList = r.tag_patterns } : {},
          length(r.tag_prefixes) > 0 ? { tagPrefixList = r.tag_prefixes } : {},
          r.storage_class != "standard" ? { storageClass = r.storage_class } : {},
        )
        action = merge({ type = r.action }, r.action == "transition" ? { targetStorageClass = "archive" } : {})
      },
    ))
    ] : concat(
    p.untagged_expire_days > 0 ? [jsonencode({
      rulePriority = 1
      description  = "Expire untagged images ${p.untagged_expire_days} days after push"
      selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = p.untagged_expire_days }
      action       = { type = "expire" }
    })] : [],
    p.archive_unpulled_days > 0 ? [jsonencode({
      rulePriority = 2
      description  = "Archive images not pulled for ${p.archive_unpulled_days} days"
      selection    = { tagStatus = "any", countType = "sinceImagePulled", countUnit = "days", countNumber = p.archive_unpulled_days }
      action       = { type = "transition", targetStorageClass = "archive" }
    })] : [],
    p.keep_last > 0 ? [jsonencode({
      rulePriority = 3
      description  = "Keep the newest ${p.keep_last} images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = p.keep_last }
      action       = { type = "expire" }
    })] : [],
    p.archive_expire_days > 0 ? [jsonencode({
      rulePriority = 4
      description  = "Expire images ${p.archive_expire_days} days after archiving"
      selection    = { tagStatus = "any", storageClass = "archive", countType = "sinceImageTransitioned", countUnit = "days", countNumber = p.archive_expire_days }
      action       = { type = "expire" }
    })] : [],
  )) }

  lifecycle_json = { for o, rules in local.lifecycle_rules : o => length(rules) == 0 ? "" : "{\"rules\":[${join(",", rules)}]}" }

  # What ECR would refuse, or the module's preset cannot mean, per owner.
  # https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html
  lifecycle_problems = { for o, p in local.lifecycle_owners : o => compact(concat(
    [
      min(p.untagged_expire_days, p.keep_last, p.archive_unpulled_days, p.archive_expire_days) < 0 ? "the preset's numbers are 0 or more" : "",
      (p.keep_last > 0 ? p.archive_unpulled_days > 0 : false) ? "keep_last and archive_unpulled_days are alternatives: both select every image in standard storage. Set keep_last = 0 to archive, or write rules" : "",
      p.archive_expire_days == 0 ? "" : (p.archive_expire_days < 90 ? "archive_expire_days is at least 90: archived images cannot be deleted by a lifecycle rule before 90 days" : ""),
      length(distinct([for r in p.rules : r.priority])) == length(p.rules) ? "" : "rule priorities must be unique",
    ],
    [for r in p.rules : (r.priority >= 1 ? r.count >= 1 : false) ? "" : "rule ${r.priority}: priority and count are 1 or more"],
    [for r in p.rules : contains(["any", "tagged", "untagged"], r.tag_status) ? "" : "rule ${r.priority}: tag_status is any, tagged or untagged"],
    [for r in p.rules : r.tag_status == "tagged" ? ((length(r.tag_patterns) > 0) != (length(r.tag_prefixes) > 0) ? "" : "rule ${r.priority}: a tagged rule takes tag_patterns or tag_prefixes, exactly one of them") : (length(r.tag_patterns) + length(r.tag_prefixes) == 0 ? "" : "rule ${r.priority}: tag_patterns and tag_prefixes need tag_status = tagged")],
    [for r in p.rules : alltrue([for t in concat(r.tag_patterns, r.tag_prefixes) : length(regexall("\\*", t)) <= 4]) ? "" : "rule ${r.priority}: at most four * in a pattern"],
    [for r in p.rules : contains(["imageCountMoreThan", "sinceImagePushed", "sinceImagePulled", "sinceImageTransitioned"], r.count_type) ? "" : "rule ${r.priority}: count_type is imageCountMoreThan, sinceImagePushed, sinceImagePulled or sinceImageTransitioned"],
    [for r in p.rules : contains(["expire", "transition"], r.action) ? (contains(["standard", "archive"], r.storage_class) ? "" : "rule ${r.priority}: storage_class is standard or archive") : "rule ${r.priority}: action is expire or transition"],
    [for r in p.rules : r.count_type == "sinceImageTransitioned" ? (r.storage_class == "archive" ? (r.action == "expire" ? (r.count >= 90 ? "" : "rule ${r.priority}: archived images can only be deleted 90 days or more after archiving") : "rule ${r.priority}: a sinceImageTransitioned rule expires") : "rule ${r.priority}: a sinceImageTransitioned rule selects storage_class = archive") : (r.storage_class == "archive" ? "rule ${r.priority}: only a sinceImageTransitioned rule selects archived images" : "")],
    [for r in p.rules : r.tag_status != "any" ? "" : (alltrue([for q in p.rules : q.priority < r.priority if(q.storage_class == r.storage_class ? q.tag_status != "any" : false)]) ? "" : "rule ${r.priority}: a tag_status = any rule has the highest priority number of its storage class")],
  )) }

  # ---------------------------------------------------------------------------
  # Repository policies
  # ---------------------------------------------------------------------------

  pull_actions = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
  push_actions = concat(local.pull_actions, ["ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"])

  repository_statements = { for k, r in local.repositories : k => concat(
    length(r.access.pull_principals) == 0 ? [] : [jsonencode({
      Sid       = "Pull"
      Effect    = "Allow"
      Principal = { AWS = sort(distinct(r.access.pull_principals)) }
      Action    = local.pull_actions
    })],
    length(r.access.push_principals) == 0 ? [] : [jsonencode({
      Sid       = "PullAndPush"
      Effect    = "Allow"
      Principal = { AWS = sort(distinct(r.access.push_principals)) }
      Action    = local.push_actions
    })],
    length(r.access.pull_organization_ids) == 0 ? [] : [jsonencode({
      Sid       = "PullFromOrganizations"
      Effect    = "Allow"
      Principal = "*"
      Action    = local.pull_actions
      Condition = { StringEquals = { "aws:PrincipalOrgID" = sort(distinct(r.access.pull_organization_ids)) } }
    })],
    # Lambda adds this statement itself when it is missing, and the next
    # apply would remove it again; declared here, the policy stays stable.
    # https://docs.aws.amazon.com/lambda/latest/dg/images-create.html
    length(r.access.lambda_accounts) == 0 ? [] : [
      jsonencode({
        Sid       = "LambdaAccountsPull"
        Effect    = "Allow"
        Principal = { AWS = [for a in sort(distinct(r.access.lambda_accounts)) : "arn:${local.partition}:iam::${a}:root"] }
        Action    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
      }),
      jsonencode({
        Sid       = "LambdaImageRetrieval"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
        Condition = { ArnLike = { "aws:sourceARN" = [for a in sort(distinct(r.access.lambda_accounts)) : "arn:${local.partition}:lambda:${local.region}:${a}:function:*"] } }
      }),
    ],
    [for s in r.access.statements : jsonencode(jsondecode(s))],
  ) }

  # Decided from configuration only, never from values unknown at plan.
  repositories_with_policy = { for k, r in local.repositories : k => r if length(r.access.pull_principals) + length(r.access.push_principals) + length(r.access.pull_organization_ids) + length(r.access.lambda_accounts) + length(r.access.statements) > 0 }

  # ---------------------------------------------------------------------------
  # Registry
  # ---------------------------------------------------------------------------

  pull_through_cache = local.registry_on ? var.registry.pull_through_cache : {}
  upstream_url = {
    "docker-hub"                = "registry-1.docker.io"
    "ecr-public"                = "public.ecr.aws"
    "quay"                      = "quay.io"
    "k8s"                       = "registry.k8s.io"
    "github-container-registry" = "ghcr.io"
    "gitlab-container-registry" = "registry.gitlab.com"
    "chainguard"                = "cgr.dev"
  }

  replication_rules = local.registry_on ? var.registry.replication : []
  replication_destination_accounts = sort(distinct(flatten([
    for r in local.replication_rules : [for d in r.destinations : d.account_id if d.account_id != "" ? d.account_id != local.account_id : false]
  ])))

  registry_statements = local.registry_on ? concat(
    length(var.registry.replication_source_accounts) == 0 ? [] : [jsonencode({
      Sid       = "ReplicationFromAccounts"
      Effect    = "Allow"
      Principal = { AWS = [for a in sort(distinct(var.registry.replication_source_accounts)) : "arn:${local.partition}:iam::${a}:root"] }
      Action    = ["ecr:CreateRepository", "ecr:ReplicateImage"]
      Resource  = "${local.registry_arn}/*"
    })],
    (length(var.registry.pull_through_cache_principals) == 0 ? true : length(local.pull_through_cache) == 0) ? [] : [jsonencode({
      Sid       = "PullThroughCache"
      Effect    = "Allow"
      Principal = { AWS = sort(distinct(var.registry.pull_through_cache_principals)) }
      Action    = ["ecr:BatchImportUpstreamImage", "ecr:CreateRepository"]
      Resource  = [for prefix in sort(keys(local.pull_through_cache)) : "${local.registry_arn}/${prefix}/*"]
    })],
    [for s in var.registry.policy_statements : jsonencode(jsondecode(s))],
  ) : []

  # A template that applies tags or a key needs a role, and every template the
  # module creates carries the module's tags.
  # https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-creation-templates.html
  template_tags            = { for p, t in local.templates : p => merge(var.tags, t.tags, local.module_tags) }
  create_template_role     = length(local.templates) > 0
  template_role_name       = "${var.name}-ecr-templates"
  template_role_arn        = "arn:${local.partition}:iam::${local.account_id}:role/${local.template_role_name}"
  template_keys            = sort(distinct([for p, t in local.templates : t.kms_key_arn if t.kms_key_arn != ""]))
  template_repository_arns = sort([for p, t in local.templates : p == "ROOT" ? "${local.registry_arn}/*" : "${local.registry_arn}/${p}/*"])

  # The template a cache repository gets: the longest template prefix the
  # cache prefix falls under, else ROOT, else none. With none, ECR creates
  # it with mutable tags, AES-256 and no lifecycle policy.
  template_matches = { for prefix, c in local.pull_through_cache : prefix => reverse(sort([
    for p, t in local.templates : format("%04d %s", length(p), p) if p == "ROOT" ? false : (prefix == p ? true : startswith(prefix, "${p}/"))
  ])) }
  template_for = { for prefix, m in local.template_matches : prefix => (
    length(m) > 0 ? split(" ", m[0])[1] : (contains(keys(local.templates), "ROOT") ? "ROOT" : "")
  ) }
  untemplated_caches        = sort([for prefix, t in local.template_for : prefix if t == "" ? true : !contains(local.templates[t].applied_for, "PULL_THROUGH_CACHE")])
  immutable_cache_templates = sort([for prefix, t in local.template_for : prefix if t == "" ? false : local.templates[t].image_tag_mutability == "IMMUTABLE"])
  # Replicas arrive in this registry from replication_source_accounts.
  untemplated_replication = local.registry_on ? (length(var.registry.replication_source_accounts) == 0 ? false : !anytrue([for p, t in local.templates : contains(t.applied_for, "REPLICATION")])) : false

  # ---------------------------------------------------------------------------
  # Signals
  # ---------------------------------------------------------------------------

  event_rules = local.create && var.sns_topic_arn != "" ? merge(
    length(local.repositories) == 0 ? {} : {
      critical-findings = {
        description = "Images in ${var.name}'s repositories whose basic scan found CRITICAL vulnerabilities."
        pattern = jsonencode({
          source        = ["aws.ecr"]
          "detail-type" = ["ECR Image Scan"]
          detail = {
            "repository-name"         = sort(keys(local.repositories))
            "finding-severity-counts" = { CRITICAL = [{ numeric = [">", 0] }] }
          }
        })
      }
    },
    !local.registry_on || length(local.replication_rules) == 0 ? {} : {
      replication-failed = {
        description = "Image replications from this registry that did not succeed."
        pattern = jsonencode({
          source        = ["aws.ecr"]
          "detail-type" = ["ECR Replication Action"]
          detail        = { result = [{ "anything-but" = "SUCCESS" }] }
        })
      }
    },
    length(local.pull_through_cache) == 0 ? {} : {
      pull-through-cache-failed = {
        description = "Pull through cache syncs from an upstream registry that did not succeed."
        pattern = jsonencode({
          source        = ["aws.ecr"]
          "detail-type" = ["ECR Pull Through Cache Action"]
          detail        = { "sync-status" = [{ "anything-but" = "SUCCESS" }] }
        })
      }
    },
  ) : {}

  # ---------------------------------------------------------------------------
  # What the deployer needs, one rendered statement each
  # ---------------------------------------------------------------------------

  repository_keys = sort(distinct([for k, key in local.repository_key : key if key != ""]))
  deployer_statements = concat(
    # https://docs.aws.amazon.com/AmazonECR/latest/userguide/encryption-at-rest.html
    length(local.repository_keys) == 0 ? [] : [jsonencode({
      Sid      = "RetireRepositoryKeyGrants"
      Effect   = "Allow"
      Action   = ["kms:RetireGrant"]
      Resource = local.repository_keys
    })],
    !local.create_template_role ? [] : [jsonencode({
      Sid       = "PassTemplateRole"
      Effect    = "Allow"
      Action    = "iam:PassRole"
      Resource  = local.template_role_arn
      Condition = { StringEquals = { "iam:PassedToService" = "ecr.amazonaws.com" } }
    })],
    [for s in [
      { on = length(local.pull_through_cache) > 0, service = "pullthroughcache.ecr.amazonaws.com", role = "AWSServiceRoleForECRPullThroughCache" },
      { on = length(local.templates) > 0, service = "ecr.amazonaws.com", role = "AWSServiceRoleForECRTemplate" },
      { on = length(local.replication_rules) > 0, service = "replication.ecr.amazonaws.com", role = "AWSServiceRoleForECRReplication" },
      ] : jsonencode({
        Sid       = "ServiceLinkedRole${replace(s.role, "AWSServiceRoleFor", "")}"
        Effect    = "Allow"
        Action    = "iam:CreateServiceLinkedRole"
        Resource  = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/${s.service}/${s.role}"
        Condition = { StringEquals = { "iam:AWSServiceName" = s.service } }
    }) if s.on],
    # https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning-enhanced-iam.html
    (local.registry_on ? (var.registry.scanning == null ? false : var.registry.scanning.type == "ENHANCED") : false) ? [
      jsonencode({
        Sid      = "EnhancedScanning"
        Effect   = "Allow"
        Action   = ["inspector2:Disable", "inspector2:Enable", "inspector2:ListAccountPermissions", "inspector2:ListCoverage", "inspector2:ListFindings"]
        Resource = "*" # these Inspector actions have no resource-level permissions
      }),
      jsonencode({
        Sid       = "InspectorServiceLinkedRole"
        Effect    = "Allow"
        Action    = "iam:CreateServiceLinkedRole"
        Resource  = "*"
        Condition = { StringEquals = { "iam:AWSServiceName" = "inspector2.amazonaws.com" } }
      }),
    ] : [],
  )

  # ---------------------------------------------------------------------------
  # Posture
  # ---------------------------------------------------------------------------

  missing_required_tag_keys = [for t in var.required_tag_keys : t if trimspace(lookup(var.tags, t, "")) == ""]
  mutable_repositories      = sort([for k, m in local.mutability : k if m == "MUTABLE"])
  repositories_without_key  = sort([for k, key in local.repository_key : k if key == ""])
  unbounded_repositories    = sort([for k, r in local.repositories : k if !strcontains(local.lifecycle_json["repository ${k}"], "\"expire\"")])
  unscanned_repositories    = local.registry_on ? (var.registry.scanning != null ? [] : sort([for k, on in local.scan_on_push : k if !on])) : sort([for k, on in local.scan_on_push : k if !on])
  open_repositories         = sort([for k, r in local.repositories : k if anytrue([for s in r.access.statements : strcontains(replace(s, " ", ""), "\"Principal\":\"*\"") ? !strcontains(s, "Condition") : false])])
  cross_account_principals = sort(distinct(flatten([for k, r in local.repositories : [
    for p in concat(r.access.pull_principals, r.access.push_principals) : "${k}: ${p}" if split(":", p)[4] != local.account_id
  ]])))
}
