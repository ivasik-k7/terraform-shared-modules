# plan-level checks, no creds. `terraform test`
# mock_provider so the caller-identity / partition data sources resolve offline.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

# --- defaults: secure-by-default repo, no lifecycle policy (no rules) ---------
run "basic_defaults" {
  command = plan

  variables {
    repository_name = "platform/api"
  }

  assert {
    condition     = length(aws_ecr_repository.this) == 1
    error_message = "A repository should be planned"
  }

  assert {
    condition     = aws_ecr_repository.this[0].image_tag_mutability == "IMMUTABLE"
    error_message = "Tags should be immutable by default"
  }

  assert {
    condition     = aws_ecr_repository.this[0].image_scanning_configuration[0].scan_on_push == true
    error_message = "scan_on_push should default true"
  }

  assert {
    condition     = aws_ecr_repository.this[0].encryption_configuration[0].encryption_type == "AES256"
    error_message = "Encryption should default to AES256"
  }

  # the bug fix: enable_lifecycle_policy defaults true but with no rules we must
  # NOT emit an empty (invalid) lifecycle policy.
  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 0
    error_message = "No lifecycle policy should be created when there are no rules"
  }

  # the secure baseline repository policy is created by default...
  assert {
    condition     = length(aws_ecr_repository_policy.this) == 1
    error_message = "A repository policy should be created by default"
  }

  # ...and it must NOT contain destructive/admin actions (secure default).
  assert {
    condition     = !can(regex("ecr:DeleteRepository", aws_ecr_repository_policy.this[0].policy)) && !can(regex("ecr:SetRepositoryPolicy", aws_ecr_repository_policy.this[0].policy))
    error_message = "The default baseline must not grant destructive/admin actions"
  }

  assert {
    condition     = can(regex("ecr:PutImage", aws_ecr_repository_policy.this[0].policy))
    error_message = "The default baseline should still allow account pull/push"
  }
}

# --- custom statements layer ON TOP of the secure baseline -------------------
run "statements_layered_on_baseline" {
  command = plan

  variables {
    repository_name = "platform/api"
    repository_policy_statements = [
      {
        sid    = "AllowOrgRead"
        effect = "Allow"
        principals = {
          type        = "AWS"
          identifiers = ["arn:aws:iam::555555555555:root"]
        }
        actions = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
      },
    ]
  }

  # baseline (AllowAccountPullPush) + the custom statement both present
  assert {
    condition     = can(regex("AllowAccountPullPush", aws_ecr_repository_policy.this[0].policy)) && can(regex("AllowOrgRead", aws_ecr_repository_policy.this[0].policy))
    error_message = "Custom statements must layer on top of the secure baseline, not replace it"
  }
}

# --- single-knob: repository_access with curated principals ------------------
run "repository_access_principals" {
  command = plan

  variables {
    repository_name = "platform/api"
    repository_access = {
      push_principals = ["arn:aws:iam::222222222222:role/ci-push"]
      pull_principals = ["arn:aws:iam::333333333333:root"]
    }
  }

  assert {
    condition     = length(aws_ecr_repository_policy.this) == 1
    error_message = "repository_access principals should produce a policy"
  }

  assert {
    condition     = can(regex("222222222222", aws_ecr_repository_policy.this[0].policy)) && can(regex("333333333333", aws_ecr_repository_policy.this[0].policy)) && can(regex("AllowAccountPullPush", aws_ecr_repository_policy.this[0].policy))
    error_message = "Baseline + push + pull principals should all be present"
  }
}

# --- single-knob: baseline off + custom statement = full manual control ------
run "repository_access_manual" {
  command = plan

  variables {
    repository_name = "platform/api"
    repository_access = {
      account_access = false
      statements = [
        {
          sid    = "PullOnlyForBuildAccount"
          effect = "Allow"
          principals = {
            type        = "AWS"
            identifiers = ["arn:aws:iam::444444444444:role/deployer"]
          }
          actions = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability"]
        },
      ]
    }
  }

  assert {
    condition     = can(regex("PullOnlyForBuildAccount", aws_ecr_repository_policy.this[0].policy)) && !can(regex("AllowAccountPullPush", aws_ecr_repository_policy.this[0].policy))
    error_message = "account_access=false should leave only the user's statements"
  }
}

# --- single-knob: enabled=false -> no policy ---------------------------------
run "repository_access_disabled" {
  command = plan

  variables {
    repository_name   = "platform/api"
    repository_access = { enabled = false }
  }

  assert {
    condition     = length(aws_ecr_repository_policy.this) == 0
    error_message = "repository_access.enabled=false should create no policy"
  }
}

# --- F1: a "*" principal renders as {"AWS":["*"]}, not {"*":[...]} -----------
run "public_principal_renders_aws_star" {
  command = plan

  variables {
    repository_name = "platform/public"
    repository_access = {
      account_access = false # so the ONLY principal is the public one
      statements = [
        {
          sid        = "PublicPull"
          effect     = "Allow"
          principals = { type = "*", identifiers = ["*"] }
          actions    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
        },
      ]
    }
  }

  # with the baseline off, "AWS" appears in the policy only if the public
  # principal rendered correctly as {"AWS":["*"]} (the malformed {"*":[...]} omits it).
  assert {
    condition     = can(regex("AWS", aws_ecr_repository_policy.this[0].policy))
    error_message = "A '*' principal must render as {\"AWS\":[\"*\"]}"
  }
}

# --- backward compat: deprecated flat inputs still merge in ------------------
run "deprecated_inputs_still_honored" {
  command = plan

  variables {
    repository_name    = "platform/api"
    allowed_principals = ["arn:aws:iam::222222222222:role/legacy-ci"]
  }

  assert {
    condition     = can(regex("222222222222", aws_ecr_repository_policy.this[0].policy))
    error_message = "Deprecated allowed_principals must still be honored (merged into repository_access)"
  }
}

# --- tags unify: tags wins over common_tags on conflict ----------------------
run "tags_unified" {
  command = plan

  variables {
    repository_name = "platform/api"
    common_tags     = { Env = "old", Owner = "platform" }
    tags            = { Env = "prod" }
  }

  assert {
    condition     = aws_ecr_repository.this[0].tags["Env"] == "prod" && aws_ecr_repository.this[0].tags["Owner"] == "platform"
    error_message = "tags should override common_tags on conflict and union the rest"
  }
}

# --- lifecycle policy with rules ---------------------------------------------
run "lifecycle_with_rules" {
  command = plan

  variables {
    repository_name = "platform/api"
    lifecycle_rules = [
      {
        rule_priority = 1
        description   = "expire untagged after 14 days"
        tag_status    = "untagged"
        count_type    = "sinceImagePushed"
        count_unit    = "days"
        count_number  = 14
        action_type   = "expire"
      },
      {
        rule_priority = 2
        description   = "keep last 20"
        tag_status    = "any"
        count_type    = "imageCountMoreThan"
        count_number  = 20
        action_type   = "expire"
      },
    ]
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 1
    error_message = "A lifecycle policy should be created when rules are present"
  }

  assert {
    condition     = can(regex("sinceImagePushed", aws_ecr_lifecycle_policy.this[0].policy))
    error_message = "Lifecycle policy JSON should contain the rule selection"
  }
}

# --- tagPatternList support (previously declared but ignored) -----------------
run "lifecycle_tag_pattern" {
  command = plan

  variables {
    repository_name = "platform/api"
    lifecycle_rules = [
      {
        rule_priority    = 1
        description      = "keep last 5 release images"
        tag_status       = "tagged"
        tag_pattern_list = ["v*"]
        count_type       = "imageCountMoreThan"
        count_number     = 5
        action_type      = "expire"
      },
    ]
  }

  assert {
    condition     = can(regex("tagPatternList", aws_ecr_lifecycle_policy.this[0].policy))
    error_message = "tagPatternList should be rendered into the lifecycle policy"
  }
}

# --- KMS encryption -----------------------------------------------------------
run "kms_encryption" {
  command = plan

  variables {
    repository_name = "platform/api"
    encryption_type = "KMS"
    kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/abcd-ef01"
  }

  assert {
    condition     = aws_ecr_repository.this[0].encryption_configuration[0].encryption_type == "KMS"
    error_message = "Encryption type should be KMS"
  }
}

# --- mutable tags + scanning off ---------------------------------------------
run "mutable_tags" {
  command = plan

  variables {
    repository_name      = "platform/api"
    image_tag_mutability = "MUTABLE"
    scan_on_push         = false
  }

  assert {
    condition     = aws_ecr_repository.this[0].image_tag_mutability == "MUTABLE"
    error_message = "Tags should be mutable when requested"
  }
}

# --- cross-account access principals -> repository policy --------------------
run "allowed_principals" {
  command = plan

  variables {
    repository_name         = "platform/api"
    allowed_principals      = ["arn:aws:iam::222222222222:role/ci-push"]
    allowed_pull_principals = ["arn:aws:iam::333333333333:root"]
  }

  assert {
    condition     = length(aws_ecr_repository_policy.this) == 1
    error_message = "A repository policy should be planned for cross-account principals"
  }

  assert {
    condition     = can(regex("222222222222", aws_ecr_repository_policy.this[0].policy))
    error_message = "The push principal should appear in the policy"
  }
}

# --- repository policy can be disabled ---------------------------------------
run "no_repository_policy" {
  command = plan

  variables {
    repository_name          = "platform/api"
    create_repository_policy = false
  }

  assert {
    condition     = length(aws_ecr_repository_policy.this) == 0
    error_message = "No repository policy should be created when disabled"
  }
}

# --- least privilege: baseline off + nothing else -> no resource policy ------
run "least_privilege_no_resource_policy" {
  command = plan

  variables {
    repository_name = "platform/api"
    # no baseline, no principals, no statements -> no resource policy at all.
    # access is then governed purely by identity policies (pull/push_policy_json).
    repository_access = { account_access = false }
  }

  assert {
    condition     = length(aws_ecr_repository_policy.this) == 0
    error_message = "Baseline off with no principals/statements should produce no resource policy"
  }
}

# --- a tightly-scoped custom resource policy (least privilege, cross-account) -
run "custom_least_privilege_statement" {
  command = plan

  variables {
    repository_name = "platform/api"
    repository_policy_statements = [
      {
        sid    = "PullOnlyForBuildAccount"
        effect = "Allow"
        principals = {
          type        = "AWS"
          identifiers = ["arn:aws:iam::444444444444:role/deployer"]
        }
        actions = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
        ]
      },
    ]
  }

  assert {
    condition     = length(aws_ecr_repository_policy.this) == 1
    error_message = "A custom least-privilege resource policy should be planned"
  }

  assert {
    condition     = can(regex("PullOnlyForBuildAccount", aws_ecr_repository_policy.this[0].policy)) && !can(regex("ecr:DeleteRepository", aws_ecr_repository_policy.this[0].policy))
    error_message = "Only the scoped pull statement should be present (no broad delete grant)"
  }
}

# --- replication --------------------------------------------------------------
run "replication" {
  command = plan

  variables {
    repository_name    = "platform/api"
    enable_replication = true
    replication_rules = [
      {
        destinations = [{ region = "eu-west-1", registry_id = "123456789012" }]
      },
    ]
  }

  assert {
    condition     = length(aws_ecr_replication_configuration.this) == 1
    error_message = "A replication configuration should be planned"
  }
}

# --- pull-through cache -------------------------------------------------------
run "pull_through_cache" {
  command = plan

  variables {
    repository_name = "platform/api"
    pull_through_cache_rules = {
      dockerhub = {
        ecr_repository_prefix = "docker-hub"
        upstream_registry_url = "registry-1.docker.io"
      }
    }
  }

  assert {
    condition     = length(aws_ecr_pull_through_cache_rule.this) == 1
    error_message = "A pull-through cache rule should be planned"
  }
}

# --- create = false builds nothing -------------------------------------------
run "create_false" {
  command = plan

  variables {
    create          = false
    repository_name = "platform/api"
  }

  assert {
    condition     = length(aws_ecr_repository.this) == 0 && length(aws_ecr_repository_policy.this) == 0
    error_message = "create=false should build nothing"
  }
}

# ============================================================================
# VALIDATION / PRECONDITION FAILURES
# ============================================================================

run "invalid_name_uppercase_fails" {
  command = plan
  variables {
    repository_name = "Platform/API"
  }
  expect_failures = [var.repository_name]
}

run "short_name_fails" {
  command = plan
  variables {
    repository_name = "a"
  }
  expect_failures = [var.repository_name]
}

run "kms_without_key_fails" {
  command = plan
  variables {
    repository_name = "platform/api"
    encryption_type = "KMS"
    # kms_key_arn omitted -> precondition fails
  }
  expect_failures = [aws_ecr_repository.this]
}

run "bad_lifecycle_action_fails" {
  command = plan
  variables {
    repository_name = "platform/api"
    lifecycle_rules = [
      { rule_priority = 1, description = "x", tag_status = "untagged", count_type = "sinceImagePushed", count_number = 14, action_type = "delete" },
    ]
  }
  expect_failures = [var.lifecycle_rules]
}

run "bad_lifecycle_tag_status_fails" {
  command = plan
  variables {
    repository_name = "platform/api"
    lifecycle_rules = [
      { rule_priority = 1, description = "x", tag_status = "weird", count_type = "imageCountMoreThan", count_number = 5, action_type = "expire" },
    ]
  }
  expect_failures = [var.lifecycle_rules]
}

run "duplicate_priority_fails" {
  command = plan
  variables {
    repository_name = "platform/api"
    lifecycle_rules = [
      { rule_priority = 1, description = "a", tag_status = "untagged", count_type = "imageCountMoreThan", count_number = 5, action_type = "expire" },
      { rule_priority = 1, description = "b", tag_status = "any", count_type = "imageCountMoreThan", count_number = 9, action_type = "expire" },
    ]
  }
  expect_failures = [var.lifecycle_rules]
}

run "tagged_without_filter_fails" {
  command = plan
  variables {
    repository_name = "platform/api"
    lifecycle_rules = [
      { rule_priority = 1, description = "x", tag_status = "tagged", count_type = "imageCountMoreThan", count_number = 5, action_type = "expire" },
    ]
  }
  expect_failures = [var.lifecycle_rules]
}

run "replication_without_rules_fails" {
  command = plan
  variables {
    repository_name    = "platform/api"
    enable_replication = true
    replication_rules  = []
  }
  expect_failures = [aws_ecr_replication_configuration.this]
}

run "registry_policy_without_json_fails" {
  command = plan
  variables {
    repository_name        = "platform/api"
    enable_registry_policy = true
    # registry_policy_json omitted
  }
  expect_failures = [aws_ecr_registry_policy.this]
}

run "bad_statement_effect_fails" {
  command = plan
  variables {
    repository_name = "platform/api"
    repository_policy_statements = [
      { sid = "x", effect = "Permit", actions = ["ecr:BatchGetImage"] },
    ]
  }
  expect_failures = [var.repository_policy_statements]
}

run "empty_actions_fails" {
  command = plan
  variables {
    repository_name   = "platform/api"
    repository_access = { statements = [{ sid = "x", actions = [] }] }
  }
  expect_failures = [var.repository_access]
}

run "non_ecr_action_fails" {
  command = plan
  variables {
    repository_name   = "platform/api"
    repository_access = { statements = [{ sid = "x", actions = ["s3:GetObject"] }] }
  }
  expect_failures = [var.repository_access]
}
