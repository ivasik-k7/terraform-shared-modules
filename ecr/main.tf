
# ECR Repository
resource "aws_ecr_repository" "this" {
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
}

resource "aws_ecr_lifecycle_policy" "this" {
  count      = var.enable_lifecycle_policy ? 1 : 0
  repository = aws_ecr_repository.this.name

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
          length(rule.tag_prefix_list) > 0 ? { tagPrefixList = rule.tag_prefix_list } : {}
        )
        action = {
          type = rule.action_type
        }
      }
    ]
  })
}

resource "aws_ecr_repository_policy" "this" {
  count      = var.create_repository_policy && length(local.all_policy_statements) > 0 ? 1 : 0
  repository = aws_ecr_repository.this.name

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
        stmt.Resource != null ? { Resource = stmt.Resource } : {},
        stmt.Condition != null && length(stmt.Condition) > 0 ? { Condition = stmt.Condition } : {}
      ) if stmt.Principal != null
    ]
  })
}

resource "aws_ecr_replication_configuration" "this" {
  count = var.enable_replication ? 1 : 0

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
}

resource "aws_cloudwatch_log_group" "ecr" {
  count             = var.enable_logging ? 1 : 0
  name              = local.log_group_name
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.cloudwatch_kms_key_id

  tags = local.merged_tags
}

resource "aws_ecr_registry_scanning_configuration" "this" {
  count     = var.enable_registry_scanning ? 1 : 0
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
  for_each = var.pull_through_cache_rules

  ecr_repository_prefix = each.value.ecr_repository_prefix
  upstream_registry_url = each.value.upstream_registry_url
  credential_arn        = lookup(each.value, "credential_arn", null)
}

resource "aws_ecr_registry_policy" "this" {
  count  = var.enable_registry_policy ? 1 : 0
  policy = var.registry_policy_json
}

