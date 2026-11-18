# One per account and Region, so only with registry.enabled.

resource "aws_ecr_registry_scanning_configuration" "this" {
  count = local.registry_on ? (var.registry.scanning != null ? 1 : 0) : 0

  scan_type = var.registry.scanning.type

  dynamic "rule" {
    for_each = var.registry.scanning.rules
    content {
      scan_frequency = rule.value.frequency

      dynamic "repository_filter" {
        for_each = rule.value.filters
        content {
          filter      = repository_filter.value
          filter_type = "WILDCARD"
        }
      }
    }
  }
}

resource "aws_ecr_replication_configuration" "this" {
  count = length(local.replication_rules) > 0 ? 1 : 0

  replication_configuration {
    dynamic "rule" {
      for_each = local.replication_rules
      content {
        dynamic "destination" {
          for_each = rule.value.destinations
          content {
            region      = destination.value.region
            registry_id = destination.value.account_id != "" ? destination.value.account_id : local.account_id
          }
        }

        dynamic "repository_filter" {
          for_each = rule.value.repository_prefixes
          content {
            filter      = repository_filter.value
            filter_type = "PREFIX_MATCH"
          }
        }
      }
    }
  }
}

resource "aws_ecr_pull_through_cache_rule" "this" {
  for_each = local.pull_through_cache

  ecr_repository_prefix      = each.key
  upstream_registry_url      = contains(["azure-container-registry", "ecr"], each.value.upstream) ? each.value.url : local.upstream_url[each.value.upstream]
  credential_arn             = each.value.credential_secret_arn != "" ? each.value.credential_secret_arn : null
  custom_role_arn            = each.value.role_arn != "" ? each.value.role_arn : null
  upstream_repository_prefix = each.value.upstream_prefix != "" ? each.value.upstream_prefix : null

  lifecycle {
    # https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache-private.html
    precondition {
      condition     = each.value.upstream != "ecr" ? true : (split(".", each.value.url)[0] == local.account_id ? true : each.value.role_arn != "")
      error_message = "The ECR upstream of ${each.key} is in account ${split(".", each.value.url)[0]}: a cross-account ECR upstream needs role_arn, a role ECR assumes to pull from it."
    }
  }

  # Created before the first pull, so cache repositories get the template.
  depends_on = [aws_ecr_repository_creation_template.this]
}

resource "aws_ecr_repository_creation_template" "this" {
  for_each = local.templates

  prefix               = each.key
  description          = each.value.description != "" ? each.value.description : null
  applied_for          = each.value.applied_for
  custom_role_arn      = aws_iam_role.templates[0].arn
  image_tag_mutability = length(each.value.tag_mutability_exclusions) > 0 ? "${each.value.image_tag_mutability}_WITH_EXCLUSION" : each.value.image_tag_mutability
  repository_policy    = each.value.repository_policy != "" ? each.value.repository_policy : null
  lifecycle_policy     = local.lifecycle_json["template ${each.key}"] != "" ? local.lifecycle_json["template ${each.key}"] : null
  resource_tags        = local.template_tags[each.key]

  dynamic "image_tag_mutability_exclusion_filter" {
    for_each = each.value.tag_mutability_exclusions
    content {
      filter      = image_tag_mutability_exclusion_filter.value
      filter_type = "WILDCARD"
    }
  }

  encryption_configuration {
    encryption_type = each.value.kms_key_arn != "" ? "KMS" : "AES256"
    kms_key         = each.value.kms_key_arn != "" ? each.value.kms_key_arn : null
  }

  lifecycle {
    precondition {
      condition     = length(local.lifecycle_problems["template ${each.key}"]) == 0
      error_message = "The lifecycle policy of template ${each.key} would be refused or would not mean what it says: ${join("; ", local.lifecycle_problems["template ${each.key}"])}."
    }
  }

  depends_on = [aws_iam_role_policy.templates]
}

resource "aws_ecr_registry_policy" "this" {
  count = length(local.registry_statements) > 0 ? 1 : 0

  policy = "{\"Version\":\"2012-10-17\",\"Statement\":[${join(",", local.registry_statements)}]}"
}

resource "aws_ecr_pull_time_update_exclusion" "this" {
  for_each = toset(local.registry_on ? var.registry.pull_time_update_exclusions : [])

  principal_arn = each.value
}

# Removing one from the configuration leaves the setting as it is in AWS.
# https://github.com/hashicorp/terraform-provider-aws/blob/v6.57.1/internal/service/ecr/account_setting.go
resource "aws_ecr_account_setting" "this" {
  for_each = local.registry_on ? { for n, v in {
    BASIC_SCAN_TYPE_VERSION = var.registry.account_settings.basic_scan_type_version
    REGISTRY_POLICY_SCOPE   = var.registry.account_settings.registry_policy_scope
    BLOB_MOUNTING           = var.registry.account_settings.blob_mounting
  } : n => v if v != "" } : {}

  name  = each.key
  value = each.value
}
