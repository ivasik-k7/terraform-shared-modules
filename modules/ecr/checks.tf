# Warnings, not refusals: postures a real configuration may want, but a
# reviewer should see in every plan and HCP Terraform health assessment.
# Each is silent under create = false and once named in acknowledged_checks.

locals {
  ack_hint = "Acknowledge it with acknowledged_checks if this is intended."
}

check "tags_are_immutable" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "tags_are_immutable") ? true : length(local.mutable_repositories) == 0)
    error_message = "Repositories with mutable tags: ${join(", ", local.mutable_repositories)}. A push can move a tag to another image, so two tasks started from one tag can run different code, and a deployment record no longer says what ran. Use IMMUTABLE, with tag_mutability_exclusions for the few tags that move (latest). ${local.ack_hint}"
  }
}

check "repositories_use_a_customer_key" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "repositories_use_a_customer_key") ? true : length(local.repositories_without_key) == 0)
    error_message = "Repositories encrypted with keys Amazon S3 manages: ${join(", ", local.repositories_without_key)}. Access cannot be revoked by key policy, and the encryption cannot be changed later without replacing the repository and its images. ${local.ack_hint}"
  }
}

check "storage_is_bounded" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "storage_is_bounded") ? true : length(local.unbounded_repositories) == 0)
    error_message = "Repositories whose lifecycle policy never deletes an image: ${join(", ", local.unbounded_repositories)}. Every push adds storage billed every month, forever. ${local.ack_hint}"
  }
}

check "images_are_scanned" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "images_are_scanned") ? true : length(local.unscanned_repositories) == 0)
    error_message = "Repositories with scan_on_push off and no registry scanning configuration managed here: ${join(", ", local.unscanned_repositories)}. Their images are not checked for known vulnerabilities unless another workspace configures registry scanning. ${local.ack_hint}"
  }
}

check "ecr_created_repositories_follow_a_template" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "ecr_created_repositories_follow_a_template") ? true : (length(local.untemplated_caches) == 0 ? !local.untemplated_replication : false))
    error_message = "Repositories ECR creates on its own have no creation template: pull through cache prefixes ${length(local.untemplated_caches) == 0 ? "(none)" : join(", ", local.untemplated_caches)}${local.untemplated_replication ? ", and replicas from replication_source_accounts" : ""}. ECR then creates them with mutable tags, AES-256 and no lifecycle policy: they are unencrypted by your key and grow forever. Add a creation_templates entry for the prefix (or ROOT) with the matching applied_for. ${local.ack_hint}"
  }
}

# ECR updates a cached tag from upstream at least once every 24 hours, which
# an immutable tag forbids.
# https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html
check "cached_images_can_refresh" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "cached_images_can_refresh") ? true : length(local.immutable_cache_templates) == 0)
    error_message = "Pull through cache prefixes whose creation template makes tags immutable: ${join(", ", local.immutable_cache_templates)}. When the upstream moves a tag, the cache cannot follow, and pulls keep the first image cached under it. AWS recommends MUTABLE for pull through cache templates. ${local.ack_hint}"
  }
}

check "repositories_are_not_open_to_every_account" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "repositories_are_not_open_to_every_account") ? true : length(local.open_repositories) == 0)
    error_message = "Repositories with a policy statement for Principal \"*\" and no Condition: ${join(", ", local.open_repositories)}. Any AWS account can use those actions on them. Scope it with pull_organization_ids or a Condition. ${local.ack_hint}"
  }
}
