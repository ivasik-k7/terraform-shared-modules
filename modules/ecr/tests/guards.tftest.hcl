# Every validation, precondition and check, with the input that trips it.
# expect_failures names the exact address: var.x for a validation, the
# resource for a precondition, check.x for a check. The baseline is fully
# configured, so each run changes only what it needs to trip one guard.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
}

variables {
  name              = "platform"
  kms_key_arn       = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
  tags              = { CostCenter = "cc-1" }
  required_tag_keys = ["CostCenter"]
  repositories      = { "orders/api" = {} }
}

run "the_baseline_plans_without_a_warning" {
  command = plan
}

# ---------------------------------------------------------------------------
# Validations
# ---------------------------------------------------------------------------

run "a_name_with_capitals_is_rejected" {
  command = plan
  variables {
    name = "Platform"
  }
  expect_failures = [var.name]
}

run "an_unknown_acknowledged_check_is_rejected" {
  command = plan
  variables {
    acknowledged_checks = ["no_such_check"]
  }
  expect_failures = [var.acknowledged_checks]
}

run "an_unknown_tag_mutability_is_rejected" {
  command = plan
  variables {
    image_tag_mutability = "LOCKED"
  }
  expect_failures = [var.image_tag_mutability]
}

run "a_key_alias_is_rejected" {
  command = plan
  variables {
    kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:alias/ecr"
  }
  expect_failures = [var.kms_key_arn]
}

run "a_repository_name_ecr_refuses_is_rejected" {
  command = plan
  variables {
    repositories = { "Orders/API" = {}, "orders//api" = {} }
  }
  expect_failures = [var.repositories]
}

run "more_than_five_exclusions_or_three_wildcards_are_rejected" {
  command = plan
  variables {
    repositories = {
      "orders/a" = { tag_mutability_exclusions = ["a", "b", "c", "d", "e", "f"] }
      "orders/b" = { tag_mutability_exclusions = ["*a*b*"] }
    }
  }
  expect_failures = [var.repositories]
}

run "a_repository_key_alias_is_rejected" {
  command = plan
  variables {
    repositories = { "orders/api" = { kms_key_arn = "alias/aws/ecr" } }
  }
  expect_failures = [var.repositories]
}

# A wildcard principal makes the repository usable by every AWS account.
run "a_wildcard_principal_is_rejected" {
  command = plan
  variables {
    repositories = { "orders/api" = { access = { pull_principals = ["*"] } } }
  }
  expect_failures = [var.repositories]
}

run "malformed_access_entries_are_rejected" {
  command = plan
  variables {
    repositories = { "orders/api" = { access = { pull_organization_ids = ["org-1"], lambda_accounts = ["1234"], statements = ["Allow everything"] } } }
  }
  expect_failures = [var.repositories]
}

run "basic_scanning_cannot_scan_continuously" {
  command = plan
  variables {
    registry = { enabled = true, scanning = { type = "BASIC" } }
  }
  expect_failures = [var.registry]
}

run "a_replication_destination_without_a_valid_region_or_account_is_rejected" {
  command = plan
  variables {
    registry = { enabled = true, replication = [{ destinations = [{ region = "london", account_id = "12" }] }] }
  }
  expect_failures = [var.registry]
}

run "an_authenticated_upstream_without_its_secret_is_rejected" {
  command = plan
  variables {
    registry = { enabled = true, pull_through_cache = { "docker-hub" = { upstream = "docker-hub" } } }
  }
  expect_failures = [var.registry]
}

# ECR reads only secrets named ecr-pullthroughcache/...
run "a_cache_secret_outside_the_required_prefix_is_rejected" {
  command = plan
  variables {
    registry = { enabled = true, pull_through_cache = { "ghcr" = { upstream = "github-container-registry", credential_secret_arn = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:github-token-AbCdEf" } } }
  }
  expect_failures = [var.registry]
}

run "an_ecr_upstream_without_its_url_is_rejected" {
  command = plan
  variables {
    registry = { enabled = true, pull_through_cache = { "shared" = { upstream = "ecr" } } }
  }
  expect_failures = [var.registry]
}

run "a_role_on_a_non_ecr_upstream_is_rejected" {
  command = plan
  variables {
    registry = { enabled = true, pull_through_cache = { "quay" = { upstream = "quay", role_arn = "arn:aws:iam::111122223333:role/x" } } }
  }
  expect_failures = [var.registry]
}

run "a_cache_prefix_over_thirty_characters_is_rejected" {
  command = plan
  variables {
    registry = { enabled = true, pull_through_cache = { "a-very-long-pull-through-cache-prefix" = { upstream = "quay" } } }
  }
  expect_failures = [var.registry]
}

run "a_template_for_an_unknown_workflow_is_rejected" {
  command = plan
  variables {
    registry = { enabled = true, creation_templates = { ROOT = { applied_for = ["IMPORT"] } } }
  }
  expect_failures = [var.registry]
}

run "malformed_registry_settings_are_rejected" {
  command = plan
  variables {
    registry = { enabled = true, pull_time_update_exclusions = ["arn:aws:iam::111122223333:group/scanners"], account_settings = { registry_policy_scope = "V1" } }
  }
  expect_failures = [var.registry]
}

run "a_topic_that_is_not_an_sns_arn_is_rejected" {
  command = plan
  variables {
    sns_topic_arn = "alerts"
  }
  expect_failures = [var.sns_topic_arn]
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

run "a_missing_required_tag_fails_the_plan" {
  command = plan
  variables {
    tags = { Environment = "test" }
  }
  expect_failures = [aws_ecr_repository.this["orders/api"]]
}

run "a_key_in_another_region_fails_the_plan" {
  command = plan
  variables {
    kms_key_arn = "arn:aws:kms:eu-west-1:111122223333:key/11111111-2222-3333-4444-555555555555"
  }
  expect_failures = [aws_ecr_repository.this["orders/api"]]
}

run "keep_last_and_archiving_together_fail_the_plan" {
  command = plan
  variables {
    lifecycle_policy = { archive_unpulled_days = 60 }
  }
  expect_failures = [aws_ecr_repository.this["orders/api"]]
}

# ECR cannot delete an archived image before 90 days.
run "deleting_archives_before_ninety_days_fails_the_plan" {
  command = plan
  variables {
    lifecycle_policy = { keep_last = 0, archive_unpulled_days = 60, archive_expire_days = 30 }
  }
  expect_failures = [aws_ecr_repository.this["orders/api"]]
}

run "a_tagged_rule_without_patterns_fails_the_plan" {
  command = plan
  variables {
    lifecycle_policy = { rules = [{ priority = 1, tag_status = "tagged", count_type = "imageCountMoreThan", count = 5 }] }
  }
  expect_failures = [aws_ecr_repository.this["orders/api"]]
}

run "an_any_rule_that_is_not_last_fails_the_plan" {
  command = plan
  variables {
    lifecycle_policy = { rules = [
      { priority = 1, tag_status = "any", count_type = "imageCountMoreThan", count = 50 },
      { priority = 2, tag_status = "untagged", count_type = "sinceImagePushed", count = 7 },
    ] }
  }
  expect_failures = [aws_ecr_repository.this["orders/api"]]
}

run "an_archive_rule_on_standard_storage_fails_the_plan" {
  command = plan
  variables {
    lifecycle_policy = { rules = [{ priority = 1, tag_status = "any", count_type = "sinceImageTransitioned", count = 365 }] }
  }
  expect_failures = [aws_ecr_repository.this["orders/api"]]
}

run "duplicate_rule_priorities_fail_the_plan" {
  command = plan
  variables {
    lifecycle_policy = { rules = [
      { priority = 1, tag_status = "untagged", count_type = "sinceImagePushed", count = 7 },
      { priority = 1, tag_status = "tagged", tag_prefixes = ["v"], count_type = "imageCountMoreThan", count = 5 },
    ] }
  }
  expect_failures = [aws_ecr_repository.this["orders/api"]]
}

run "a_cross_account_ecr_upstream_without_a_role_fails_the_plan" {
  command = plan
  variables {
    registry = {
      enabled            = true
      pull_through_cache = { "shared" = { upstream = "ecr", url = "444455556666.dkr.ecr.eu-west-2.amazonaws.com" } }
      creation_templates = { ROOT = { applied_for = ["PULL_THROUGH_CACHE"], image_tag_mutability = "MUTABLE" } }
    }
  }
  expect_failures = [aws_ecr_pull_through_cache_rule.this["shared"]]
}

run "a_template_lifecycle_policy_ecr_would_refuse_fails_the_plan" {
  command = plan
  variables {
    registry = { enabled = true, creation_templates = { ROOT = { applied_for = ["CREATE_ON_PUSH"], lifecycle_policy = { keep_last = 0, archive_expire_days = 10 } } } }
  }
  expect_failures = [aws_ecr_repository_creation_template.this["ROOT"]]
}

# ---------------------------------------------------------------------------
# Checks: each warns, and is silent once acknowledged
# ---------------------------------------------------------------------------

run "a_mutable_repository_warns" {
  command = plan
  variables {
    repositories = { "orders/api" = { image_tag_mutability = "MUTABLE" } }
  }
  expect_failures = [check.tags_are_immutable]
}

run "a_mutable_repository_is_silent_once_acknowledged" {
  command = plan
  variables {
    repositories        = { "orders/api" = { image_tag_mutability = "MUTABLE" } }
    acknowledged_checks = ["tags_are_immutable"]
  }
}

run "a_repository_without_a_customer_key_warns" {
  command = plan
  variables {
    kms_key_arn = ""
  }
  expect_failures = [check.repositories_use_a_customer_key]
}

run "a_repository_without_a_customer_key_is_silent_once_acknowledged" {
  command = plan
  variables {
    kms_key_arn         = ""
    acknowledged_checks = ["repositories_use_a_customer_key"]
  }
}

run "a_policy_that_never_deletes_warns" {
  command = plan
  variables {
    lifecycle_policy = { untagged_expire_days = 0, keep_last = 0, archive_unpulled_days = 90 }
  }
  expect_failures = [check.storage_is_bounded]
}

run "a_policy_that_never_deletes_is_silent_once_acknowledged" {
  command = plan
  variables {
    lifecycle_policy    = { untagged_expire_days = 0, keep_last = 0, archive_unpulled_days = 90 }
    acknowledged_checks = ["storage_is_bounded"]
  }
}

run "a_repository_without_scanning_warns" {
  command = plan
  variables {
    scan_on_push = false
  }
  expect_failures = [check.images_are_scanned]
}

run "registry_scanning_here_covers_repositories_without_scan_on_push" {
  command = plan
  variables {
    scan_on_push = false
    registry     = { enabled = true, scanning = {} }
  }
}

run "a_cache_without_a_template_warns" {
  command = plan
  variables {
    registry = { enabled = true, pull_through_cache = { "ecr-public" = { upstream = "ecr-public" } } }
  }
  expect_failures = [check.ecr_created_repositories_follow_a_template]
}

run "replicas_arriving_without_a_template_warn" {
  command = plan
  variables {
    registry = { enabled = true, replication_source_accounts = ["444455556666"], creation_templates = { ROOT = { applied_for = ["CREATE_ON_PUSH"] } } }
  }
  expect_failures = [check.ecr_created_repositories_follow_a_template]
}

run "a_cache_without_a_template_is_silent_once_acknowledged" {
  command = plan
  variables {
    registry            = { enabled = true, pull_through_cache = { "ecr-public" = { upstream = "ecr-public" } } }
    acknowledged_checks = ["ecr_created_repositories_follow_a_template"]
  }
}

run "an_immutable_cache_template_warns" {
  command = plan
  variables {
    registry = {
      enabled            = true
      pull_through_cache = { "ecr-public" = { upstream = "ecr-public" } }
      creation_templates = { "ecr-public" = { applied_for = ["PULL_THROUGH_CACHE"] } }
    }
  }
  expect_failures = [check.cached_images_can_refresh]
}

run "an_immutable_cache_template_is_silent_once_acknowledged" {
  command = plan
  variables {
    registry = {
      enabled            = true
      pull_through_cache = { "ecr-public" = { upstream = "ecr-public" } }
      creation_templates = { "ecr-public" = { applied_for = ["PULL_THROUGH_CACHE"] } }
    }
    acknowledged_checks = ["cached_images_can_refresh"]
  }
}

run "an_unconditioned_wildcard_statement_warns" {
  command = plan
  variables {
    repositories = { "orders/api" = { access = { statements = [jsonencode({ Sid = "Open", Effect = "Allow", Principal = "*", Action = ["ecr:BatchGetImage"] })] } } }
  }
  expect_failures = [check.repositories_are_not_open_to_every_account]
}

run "an_unconditioned_wildcard_statement_is_silent_once_acknowledged" {
  command = plan
  variables {
    repositories        = { "orders/api" = { access = { statements = [jsonencode({ Sid = "Open", Effect = "Allow", Principal = "*", Action = ["ecr:BatchGetImage"] })] } } }
    acknowledged_checks = ["repositories_are_not_open_to_every_account"]
  }
}
