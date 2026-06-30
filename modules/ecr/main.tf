locals {
  create = var.create
}

# ECR Repository
resource "aws_ecr_repository" "this" {
  count = local.create ? 1 : 0

  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = local.merged_tags

  lifecycle {
    # KMS encryption needs a key, or AWS rejects the repo at apply.
    precondition {
      condition     = var.encryption_type != "KMS" || var.kms_key_arn != null
      error_message = "kms_key_arn is required when encryption_type = \"KMS\"."
    }
  }
}

# Backward compatibility: the repository used to be countless. This rename keeps
# existing state attached instead of destroying + recreating the repository
# (which would delete its images) when upgrading to the create toggle.
moved {
  from = aws_ecr_repository.this
  to   = aws_ecr_repository.this[0]
}

resource "aws_ecr_lifecycle_policy" "this" {
  # FIX: only create when there are rules. enable_lifecycle_policy defaulted to
  # true with an empty rules list, which made ECR reject an empty policy at apply.
  count      = local.create && var.enable_lifecycle_policy && length(var.lifecycle_rules) > 0 ? 1 : 0
  repository = aws_ecr_repository.this[0].name

  policy = jsonencode({
    rules = [
      for rule in var.lifecycle_rules : {
        rulePriority = rule.rule_priority
        description  = rule.description
        selection = merge(
          {
            tagStatus   = rule.tag_status
            countType   = rule.count_type
            countNumber = rule.count_number
          },
          rule.count_type == "sinceImagePushed" ? { countUnit = rule.count_unit } : {},
          length(rule.tag_prefix_list) > 0 ? { tagPrefixList = rule.tag_prefix_list } : {},
          length(rule.tag_pattern_list) > 0 ? { tagPatternList = rule.tag_pattern_list } : {},
        )
        action = {
          type = rule.action_type
        }
      }
    ]
  })
}

resource "aws_ecr_repository_policy" "this" {
  count      = local.create && local.policy_enabled && length(local.all_policy_statements) > 0 ? 1 : 0
  repository = aws_ecr_repository.this[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for stmt in local.all_policy_statements :
      merge(
        {
          Sid       = stmt.Sid
          Effect    = stmt.Effect
          Principal = stmt.Principal
          Action    = stmt.Action
        },
        length(stmt.Resource) > 0 ? { Resource = stmt.Resource } : {},
        length(stmt.Condition) > 0 ? {
          Condition = {
            for c in stmt.Condition : c.variable => { (c.test) = c.values }
          }
        } : {}
      ) if stmt.Principal != null
    ]
  })
}

# NOTE: replication, registry scanning, and registry policy are REGISTRY-level
# (one per account per region) - not per repository. Enable them in exactly ONE
# instance of this module per account/region, or instances will fight over the
# shared config.
resource "aws_ecr_replication_configuration" "this" {
  count = local.create && var.enable_replication ? 1 : 0

  replication_configuration {
    dynamic "rule" {
      for_each = var.replication_rules
      content {
        dynamic "destination" {
          for_each = rule.value.destinations
          content {
            region      = destination.value.region
            registry_id = destination.value.registry_id
          }
        }

        dynamic "repository_filter" {
          for_each = length(rule.value.repository_filters) > 0 ? rule.value.repository_filters : []
          content {
            filter      = repository_filter.value.filter
            filter_type = repository_filter.value.filter_type
          }
        }
      }
    }
  }

  depends_on = [aws_ecr_repository.this]

  lifecycle {
    precondition {
      condition     = length(var.replication_rules) > 0
      error_message = "enable_replication = true requires at least one entry in replication_rules."
    }
  }
}

resource "aws_cloudwatch_log_group" "ecr" {
  count             = local.create && var.enable_logging ? 1 : 0
  name              = local.log_group_name
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.cloudwatch_kms_key_id

  tags = local.merged_tags
}

resource "aws_ecr_registry_scanning_configuration" "this" {
  count     = local.create && var.enable_registry_scanning ? 1 : 0
  scan_type = var.registry_scan_type

  dynamic "rule" {
    for_each = var.registry_scanning_rules
    content {
      scan_frequency = rule.value.scan_frequency

      repository_filter {
        filter      = rule.value.repository_filter
        filter_type = rule.value.filter_type
      }
    }
  }
}

resource "aws_ecr_pull_through_cache_rule" "this" {
  for_each = local.create ? var.pull_through_cache_rules : {}

  ecr_repository_prefix = each.value.ecr_repository_prefix
  upstream_registry_url = each.value.upstream_registry_url
  credential_arn        = lookup(each.value, "credential_arn", null)
}

resource "aws_ecr_registry_policy" "this" {
  count  = local.create && var.enable_registry_policy ? 1 : 0
  policy = var.registry_policy_json

  lifecycle {
    precondition {
      condition     = var.registry_policy_json != null
      error_message = "enable_registry_policy = true requires registry_policy_json."
    }
  }
}
