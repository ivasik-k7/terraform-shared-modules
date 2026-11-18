# The encryption configuration is fixed at creation: a change replaces the
# repository, and force_delete decides whether its images go with it.
# https://docs.aws.amazon.com/AmazonECR/latest/userguide/encryption-at-rest.html
resource "aws_ecr_repository" "this" {
  for_each = local.repositories

  name                 = each.key
  image_tag_mutability = local.mutability_sent[each.key]
  force_delete         = each.value.force_delete

  dynamic "image_tag_mutability_exclusion_filter" {
    for_each = each.value.tag_mutability_exclusions
    content {
      filter      = image_tag_mutability_exclusion_filter.value
      filter_type = "WILDCARD"
    }
  }

  image_scanning_configuration {
    scan_on_push = local.scan_on_push[each.key]
  }

  encryption_configuration {
    encryption_type = local.repository_key[each.key] != "" ? "KMS" : "AES256"
    kms_key         = local.repository_key[each.key] != "" ? local.repository_key[each.key] : null
  }

  tags = local.repository_tags[each.key]

  lifecycle {
    precondition {
      condition     = length(local.missing_required_tag_keys) == 0
      error_message = "tags is missing ${join(", ", local.missing_required_tag_keys)}, which required_tag_keys makes mandatory. Without them the repository's storage is unattributable in Cost Explorer."
    }

    precondition {
      condition     = length(local.lifecycle_problems["repository ${each.key}"]) == 0
      error_message = "The lifecycle policy of ${each.key} would be refused or would not mean what it says: ${join("; ", local.lifecycle_problems["repository ${each.key}"])}."
    }

    # https://docs.aws.amazon.com/AmazonECR/latest/userguide/encryption-at-rest.html
    precondition {
      condition     = local.repository_key[each.key] == "" ? true : split(":", local.repository_key[each.key])[3] == local.region
      error_message = "The KMS key of ${each.key} is in another Region; ECR uses only a key in the repository's Region."
    }
  }
}

# policy is ForceNew: a change deletes and puts the policy again. With
# create_before_destroy the delete would remove the new one.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = { for k, r in local.repositories : k => r if local.lifecycle_json["repository ${k}"] != "" }

  repository = aws_ecr_repository.this[each.key].name
  policy     = local.lifecycle_json["repository ${each.key}"]
}

resource "aws_ecr_repository_policy" "this" {
  for_each = local.repositories_with_policy

  repository = aws_ecr_repository.this[each.key].name
  policy     = "{\"Version\":\"2012-10-17\",\"Statement\":[${join(",", local.repository_statements[each.key])}]}"
}
