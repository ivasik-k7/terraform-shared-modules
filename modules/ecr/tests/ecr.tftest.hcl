# Properties of the repositories, one run per property. The baseline is fully
# configured, so the module's own advisory checks pass.
#
# What a mock cannot show: ECR accepting a lifecycle policy or a repository
# policy, or the replacement a change of encryption causes (mock_provider
# never reports RequiresReplace).

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
  tags              = { CostCenter = "cc-1", Environment = "test" }
  required_tag_keys = ["CostCenter"]

  repositories = {
    "orders/api" = {}
  }
}

# ---------------------------------------------------------------------------
# Repository settings
# ---------------------------------------------------------------------------

run "a_repository_is_immutable_scanned_and_encrypted_by_default" {
  command = plan

  assert {
    condition = alltrue([
      aws_ecr_repository.this["orders/api"].name == "orders/api",
      aws_ecr_repository.this["orders/api"].image_tag_mutability == "IMMUTABLE",
      aws_ecr_repository.this["orders/api"].image_scanning_configuration[0].scan_on_push,
      aws_ecr_repository.this["orders/api"].encryption_configuration[0].encryption_type == "KMS",
      aws_ecr_repository.this["orders/api"].encryption_configuration[0].kms_key == "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555",
      !aws_ecr_repository.this["orders/api"].force_delete,
    ])
    error_message = "the defaults are immutable tags, scan on push, the module's key, and no force_delete."
  }
}

run "exclusions_turn_either_mode_into_its_with_exclusion_form" {
  command = plan

  variables {
    repositories = {
      "orders/api"  = { tag_mutability_exclusions = ["latest", "dev-*"] }
      "orders/base" = { image_tag_mutability = "MUTABLE", tag_mutability_exclusions = ["v*"] }
    }
    acknowledged_checks = ["tags_are_immutable"]
  }

  assert {
    condition = alltrue([
      aws_ecr_repository.this["orders/api"].image_tag_mutability == "IMMUTABLE_WITH_EXCLUSION",
      [for f in aws_ecr_repository.this["orders/api"].image_tag_mutability_exclusion_filter : f.filter] == ["latest", "dev-*"],
      alltrue([for f in aws_ecr_repository.this["orders/api"].image_tag_mutability_exclusion_filter : f.filter_type == "WILDCARD"]),
      aws_ecr_repository.this["orders/base"].image_tag_mutability == "MUTABLE_WITH_EXCLUSION",
    ])
    error_message = "exclusions send IMMUTABLE_WITH_EXCLUSION or MUTABLE_WITH_EXCLUSION with WILDCARD filters, which is the only mode the provider accepts them in."
  }
}

run "a_repository_key_wins_and_no_key_means_aes256" {
  command = plan

  variables {
    repositories = {
      "orders/api"    = { kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/99999999-2222-3333-4444-555555555555" }
      "orders/public" = {}
    }
    kms_key_arn         = ""
    acknowledged_checks = ["repositories_use_a_customer_key"]
  }

  assert {
    condition = alltrue([
      aws_ecr_repository.this["orders/api"].encryption_configuration[0].kms_key == "arn:aws:kms:eu-west-2:111122223333:key/99999999-2222-3333-4444-555555555555",
      aws_ecr_repository.this["orders/public"].encryption_configuration[0].encryption_type == "AES256",
    ])
    error_message = "a repository's own key is used; without any key, AES-256."
  }

  assert {
    condition     = output.governance.encryption == { "orders/api" = "arn:aws:kms:eu-west-2:111122223333:key/99999999-2222-3333-4444-555555555555", "orders/public" = "AES256" }
    error_message = "governance names each repository's encryption."
  }
}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

run "the_default_lifecycle_expires_untagged_images_and_keeps_the_newest_hundred" {
  command = plan

  assert {
    condition = jsondecode(aws_ecr_lifecycle_policy.this["orders/api"].policy) == {
      rules = [
        {
          rulePriority = 1
          description  = "Expire untagged images 14 days after push"
          selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 14 }
          action       = { type = "expire" }
        },
        {
          rulePriority = 3
          description  = "Keep the newest 100 images"
          selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 100 }
          action       = { type = "expire" }
        },
      ]
    }
    error_message = "the preset bounds storage: untagged images go after 14 days, and only the newest 100 images stay; the any rule has the highest priority number."
  }
}

run "the_archive_preset_moves_unpulled_images_and_deletes_old_archives" {
  command = plan

  variables {
    lifecycle_policy = { keep_last = 0, archive_unpulled_days = 60, archive_expire_days = 365 }
  }

  assert {
    condition = [for r in jsondecode(aws_ecr_lifecycle_policy.this["orders/api"].policy).rules : [r.selection, r.action]] == [
      [{ tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 14 }, { type = "expire" }],
      [{ tagStatus = "any", countType = "sinceImagePulled", countUnit = "days", countNumber = 60 }, { type = "transition", targetStorageClass = "archive" }],
      [{ tagStatus = "any", storageClass = "archive", countType = "sinceImageTransitioned", countUnit = "days", countNumber = 365 }, { type = "expire" }],
    ]
    error_message = "archiving sends a transition on last pull and an expiry of archived images, in the shape of AWS's combined example."
  }
}

run "a_repository_policy_replaces_the_modules_and_rules_replace_the_preset" {
  command = plan

  variables {
    repositories = {
      "orders/api" = {
        lifecycle_policy = {
          rules = [
            { priority = 1, description = "Releases: keep 20", tag_status = "tagged", tag_patterns = ["v*"], count_type = "imageCountMoreThan", count = 20 },
            { priority = 9, tag_status = "any", count_type = "sinceImagePushed", count = 30 },
          ]
        }
      }
      "orders/worker" = {}
    }
  }

  assert {
    condition = jsondecode(aws_ecr_lifecycle_policy.this["orders/api"].policy).rules == [
      { rulePriority = 1, description = "Releases: keep 20", selection = { tagStatus = "tagged", countType = "imageCountMoreThan", countNumber = 20, tagPatternList = ["v*"] }, action = { type = "expire" } },
      { rulePriority = 9, selection = { tagStatus = "any", countType = "sinceImagePushed", countNumber = 30, countUnit = "days" }, action = { type = "expire" } },
    ]
    error_message = "rules are sent as written, with countUnit only on day counts and no empty description."
  }

  assert {
    condition     = length(jsondecode(aws_ecr_lifecycle_policy.this["orders/worker"].policy).rules) == 2
    error_message = "a repository without its own policy keeps the module's."
  }
}

run "a_disabled_lifecycle_sends_no_policy" {
  command = plan

  variables {
    repositories        = { "orders/api" = { lifecycle_policy = { enabled = false } } }
    acknowledged_checks = ["storage_is_bounded"]
  }

  assert {
    condition     = alltrue([length(aws_ecr_lifecycle_policy.this) == 0, jsonencode(output.governance.unbounded_storage) == jsonencode(["orders/api"])])
    error_message = "enabled = false sends no policy, and governance lists the repository as unbounded."
  }
}

# ---------------------------------------------------------------------------
# Access
# ---------------------------------------------------------------------------

run "no_repository_policy_without_access" {
  command = plan

  assert {
    condition     = length(aws_ecr_repository_policy.this) == 0
    error_message = "same-account access is IAM's; a repository with no access entries gets no policy."
  }
}

run "access_entries_render_exactly_their_statements" {
  command = plan

  variables {
    repositories = {
      "orders/api" = {
        access = {
          pull_principals       = ["arn:aws:iam::444455556666:root"]
          push_principals       = ["arn:aws:iam::111122223333:role/ci"]
          pull_organization_ids = ["o-abcdefghij"]
          lambda_accounts       = ["444455556666"]
          statements            = [jsonencode({ Sid = "Extra", Effect = "Deny", Principal = "*", Action = "ecr:DeleteRepository", Condition = { StringNotEquals = { "aws:PrincipalAccount" = "111122223333" } } })]
        }
      }
    }
  }

  assert {
    condition = jsondecode(aws_ecr_repository_policy.this["orders/api"].policy).Statement == [
      { Sid = "Pull", Effect = "Allow", Principal = { AWS = ["arn:aws:iam::444455556666:root"] }, Action = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"] },
      { Sid = "PullAndPush", Effect = "Allow", Principal = { AWS = ["arn:aws:iam::111122223333:role/ci"] }, Action = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"] },
      { Sid = "PullFromOrganizations", Effect = "Allow", Principal = "*", Action = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], Condition = { StringEquals = { "aws:PrincipalOrgID" = ["o-abcdefghij"] } } },
      { Sid = "LambdaAccountsPull", Effect = "Allow", Principal = { AWS = ["arn:aws:iam::444455556666:root"] }, Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"] },
      { Sid = "LambdaImageRetrieval", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], Condition = { ArnLike = { "aws:sourceARN" = ["arn:aws:lambda:eu-west-2:444455556666:function:*"] } } },
      { Sid = "Extra", Effect = "Deny", Principal = "*", Action = "ecr:DeleteRepository", Condition = { StringNotEquals = { "aws:PrincipalAccount" = "111122223333" } } },
    ]
    error_message = "each access entry renders one statement: pull and push to the named principals, organization pull scoped by aws:PrincipalOrgID, the two statements Lambda needs, and the caller's own."
  }

  assert {
    condition     = jsonencode(output.governance.cross_account_principals) == jsonencode(["orders/api: arn:aws:iam::444455556666:root"])
    error_message = "governance lists principals from other accounts."
  }
}

run "consumer_policies_name_exactly_these_repositories" {
  command = plan

  variables {
    repositories = { "orders/api" = {}, "orders/worker" = {} }
  }

  assert {
    condition = jsondecode(output.pull_policy_json).Statement == [
      { Sid = "PullImages", Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], Resource = ["arn:aws:ecr:eu-west-2:111122223333:repository/orders/api", "arn:aws:ecr:eu-west-2:111122223333:repository/orders/worker"] },
      { Sid = "GetAuthorizationToken", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    ]
    error_message = "the pull policy scopes the pull actions to the module's repositories; only the token is *."
  }

  assert {
    condition     = contains(jsondecode(output.push_policy_json).Statement[0].Action, "ecr:PutImage") && output.pull_through_cache_policy_json == null
    error_message = "the push policy adds the push actions; there is no cache policy without a cache."
  }
}

# ---------------------------------------------------------------------------
# Contracts and signals
# ---------------------------------------------------------------------------

run "every_kms_requirement_is_contract_v2" {
  command = plan

  assert {
    condition = output.kms_key_policy_requirements == [{
      key        = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
      sid        = "RepositoryGrants0"
      principals = { services = [], arns = [], roles = ["deployer"] }
      actions    = ["kms:CreateGrant", "kms:DescribeKey"]
      conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["ecr.eu-west-2.amazonaws.com"] }]
      purpose    = output.kms_key_policy_requirements[0].purpose
    }]
    error_message = "the repository key admits the deployer to create grants through ECR in this Region, and nothing else."
  }

  assert {
    condition     = jsondecode(output.deployer_requirements.iam_policy).Statement == [{ Sid = "RetireRepositoryKeyGrants", Effect = "Allow", Action = ["kms:RetireGrant"], Resource = ["arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"] }]
    error_message = "the deployer holds kms:RetireGrant in its own policy, which ECR requires, and needs nothing else for repositories alone."
  }
}

run "the_network_contract_names_the_ecr_endpoints_and_s3" {
  command = plan

  assert {
    condition = alltrue([
      output.network_contract.required_interface_endpoints == ["com.amazonaws.eu-west-2.ecr.api", "com.amazonaws.eu-west-2.ecr.dkr"],
      output.network_contract.gateway_endpoints == ["com.amazonaws.eu-west-2.s3"],
    ])
    error_message = "pulls need ecr.api, ecr.dkr and the S3 gateway endpoint."
  }
}

run "critical_findings_reach_the_topic" {
  command = plan

  variables {
    sns_topic_arn = "arn:aws:sns:eu-west-2:111122223333:alerts"
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_event_rule.this["critical-findings"].name == "platform-ecr-critical-findings",
      jsondecode(aws_cloudwatch_event_rule.this["critical-findings"].event_pattern).detail == { "repository-name" = ["orders/api"], "finding-severity-counts" = { CRITICAL = [{ numeric = [">", 0] }] } },
      aws_cloudwatch_event_target.this["critical-findings"].arn == "arn:aws:sns:eu-west-2:111122223333:alerts",
      length(aws_cloudwatch_event_rule.this) == 1,
    ])
    error_message = "a basic scan with critical findings in the module's repositories publishes to the topic; registry rules need the registry."
  }

  assert {
    condition     = output.notification_requirements.topic_policy_statements[0].Condition == { ArnLike = { "aws:SourceArn" = "arn:aws:events:eu-west-2:111122223333:rule/platform-ecr-*" } }
    error_message = "the topic policy admits only this module's rules."
  }
}

run "module_tags_cannot_be_overridden" {
  command = plan

  variables {
    tags         = { CostCenter = "cc-1", ManagedBy = "someone", Module = "other" }
    repositories = { "orders/api" = { tags = { Team = "orders", Module = "again" } } }
  }

  assert {
    condition     = aws_ecr_repository.this["orders/api"].tags == tomap({ CostCenter = "cc-1", Team = "orders", ManagedBy = "Terraform", Module = "ecr" })
    error_message = "repository tags merge the module's, the repository's and the module keys last."
  }
}

run "create_false_plans_nothing_and_outputs_nothing" {
  command = plan

  variables {
    create        = false
    sns_topic_arn = "arn:aws:sns:eu-west-2:111122223333:alerts"
    registry      = { enabled = true, scanning = {}, replication = [{ destinations = [{ region = "eu-west-1" }] }] }
  }

  assert {
    condition = alltrue([
      length(aws_ecr_repository.this) == 0, length(aws_ecr_lifecycle_policy.this) == 0, length(aws_ecr_repository_policy.this) == 0,
      length(aws_ecr_registry_scanning_configuration.this) == 0, length(aws_ecr_replication_configuration.this) == 0,
      length(aws_cloudwatch_event_rule.this) == 0, length(aws_iam_role.templates) == 0,
    ])
    error_message = "create = false creates nothing."
  }

  assert {
    condition = alltrue([
      output.repository_arns == {}, output.repository_urls == {}, output.registry_url == null, output.registry_id == null,
      output.pull_policy_json == null, output.push_policy_json == null, output.governance == null,
      output.kms_key_policy_requirements == null, output.deployer_requirements == null, output.network_contract == null,
      output.notification_requirements == null, output.verify_commands == null, output.replication_destination_requirements == {},
      output.creation_template_role_arn == null,
    ])
    error_message = "create = false leaves every output null or empty."
  }
}
