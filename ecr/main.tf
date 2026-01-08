resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = local.merged_tags

  depends_on = [data.aws_caller_identity.current]
}

resource "aws_ecr_lifecycle_policy" "this" {
  count      = var.enable_lifecycle_policy ? 1 : 0
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      for rule in local.lifecycle_rules_final : {
        rulePriority = rule.rule_priority
        description  = rule.description
        selection = merge(
          {
            tagStatus   = rule.tag_status
            countType   = rule.count_type
            countUnit   = rule.count_unit
            countNumber = rule.count_number
          },
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
  count      = var.create_repository_policy ? 1 : 0
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for stmt in local.all_policy_statements : {
        Sid       = stmt.Sid
        Effect    = stmt.Effect
        Principal = stmt.Principal
        Action    = stmt.Action
        Resource  = stmt.Resource
      } if stmt.Principal != null
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

  tags = local.merged_tags
}
