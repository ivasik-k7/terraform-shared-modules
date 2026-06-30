# mocked-provider apply. proves the resources assemble end to end without creds.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

run "full_apply" {
  command = apply

  variables {
    repository_name = "platform/api"
    encryption_type = "KMS"
    kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/abcd-ef01"

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
    ]

    allowed_principals = ["arn:aws:iam::222222222222:role/ci-push"]

    tags        = { Project = "platform" }
    common_tags = { ManagedBy = "Terraform" }
  }

  assert {
    condition     = aws_ecr_repository.this[0].name == "platform/api"
    error_message = "Repository name should pass through"
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 1 && length(aws_ecr_repository_policy.this) == 1
    error_message = "Lifecycle + repository policies should be created"
  }

  assert {
    condition     = output.repository_url != null
    error_message = "repository_url output should be populated"
  }

  assert {
    condition     = output.lifecycle_policy_created == true
    error_message = "lifecycle_policy_created should be true when rules exist"
  }

  assert {
    condition     = output.kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/abcd-ef01"
    error_message = "kms_key_arn output should expose the key for downstream decrypt grants"
  }

  assert {
    condition     = can(regex("ecr:GetDownloadUrlForLayer", output.pull_policy_json)) && can(regex("ecr:GetAuthorizationToken", output.pull_policy_json))
    error_message = "pull_policy_json should grant pull actions + auth token"
  }

  assert {
    condition     = can(regex("ecr:PutImage", output.push_policy_json)) && !can(regex("ecr:PutImage", output.pull_policy_json))
    error_message = "push_policy_json includes push actions; pull_policy_json must not"
  }
}

run "minimal_apply" {
  command = apply

  variables {
    repository_name = "platform/worker"
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 0
    error_message = "Default (no rules) must not create an empty lifecycle policy"
  }

  assert {
    condition     = output.lifecycle_policy_created == false
    error_message = "lifecycle_policy_created should be false with no rules"
  }
}
