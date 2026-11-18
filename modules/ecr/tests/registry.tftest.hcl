# Properties of the registry settings: scanning, replication, pull through
# cache, creation templates, the registry policy and account settings.
#
# What a mock cannot show: ECR accepting the registry policy, a pull through
# cache rule reaching its upstream, or a template applying to a repository ECR
# creates.

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
  # Applied runs need ARNs the provider's own validation accepts.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/platform-ecr-templates" }
  }
}

variables {
  name              = "platform"
  kms_key_arn       = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
  tags              = { CostCenter = "cc-1" }
  required_tag_keys = ["CostCenter"]
  repositories      = {}

  registry = {
    enabled  = true
    scanning = {}
    replication = [{
      destinations        = [{ region = "eu-west-1" }, { region = "eu-west-2", account_id = "444455556666" }]
      repository_prefixes = ["orders"]
    }]
    replication_source_accounts = ["777788889999"]
    pull_through_cache = {
      "docker-hub" = { upstream = "docker-hub", credential_secret_arn = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:ecr-pullthroughcache/docker-hub-AbCdEf" }
      "ecr-public" = { upstream = "ecr-public" }
      "shared"     = { upstream = "ecr", url = "444455556666.dkr.ecr.eu-west-2.amazonaws.com", role_arn = "arn:aws:iam::111122223333:role/ptc-shared", upstream_prefix = "base" }
    }
    pull_through_cache_principals = ["arn:aws:iam::111122223333:role/nodes"]
    creation_templates = {
      ROOT = {
        applied_for          = ["PULL_THROUGH_CACHE", "REPLICATION"]
        image_tag_mutability = "MUTABLE"
        kms_key_arn          = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
        lifecycle_policy     = { keep_last = 50 }
      }
    }
    pull_time_update_exclusions = ["arn:aws:iam::111122223333:role/scanner"]
    account_settings            = { registry_policy_scope = "V2", blob_mounting = "ENABLED" }
  }
}

run "nothing_registry_wide_without_registry_enabled" {
  command = plan

  variables {
    registry = {}
  }

  assert {
    condition = alltrue([
      length(aws_ecr_registry_scanning_configuration.this) == 0, length(aws_ecr_replication_configuration.this) == 0,
      length(aws_ecr_pull_through_cache_rule.this) == 0, length(aws_ecr_repository_creation_template.this) == 0,
      length(aws_ecr_registry_policy.this) == 0, length(aws_ecr_account_setting.this) == 0,
      length(aws_ecr_pull_time_update_exclusion.this) == 0, length(aws_iam_role.templates) == 0,
      !output.governance.registry_managed_here,
    ])
    error_message = "a workspace that does not own the registry touches none of its singletons."
  }
}

run "scanning_defaults_to_enhanced_continuous_on_everything" {
  command = plan

  assert {
    condition = alltrue([
      aws_ecr_registry_scanning_configuration.this[0].scan_type == "ENHANCED",
      length(aws_ecr_registry_scanning_configuration.this[0].rule) == 1,
      one(aws_ecr_registry_scanning_configuration.this[0].rule).scan_frequency == "CONTINUOUS_SCAN",
      [for f in one(aws_ecr_registry_scanning_configuration.this[0].rule).repository_filter : f.filter] == ["*"],
    ])
    error_message = "scanning = {} rescans every repository continuously with Inspector."
  }

  assert {
    condition     = contains([for s in jsondecode(output.deployer_requirements.iam_policy).Statement : s.Sid], "EnhancedScanning")
    error_message = "the deployer is told it needs the Inspector actions enhanced scanning uses."
  }
}

run "replication_sends_each_destination_and_names_what_the_other_account_must_allow" {
  command = plan

  assert {
    condition = jsonencode([for d in aws_ecr_replication_configuration.this[0].replication_configuration[0].rule[0].destination : [d.region, d.registry_id]]) == jsonencode([
      ["eu-west-1", "111122223333"], ["eu-west-2", "444455556666"],
    ])
    error_message = "a destination without an account is this account in another Region."
  }

  assert {
    condition     = [for f in aws_ecr_replication_configuration.this[0].replication_configuration[0].rule[0].repository_filter : [f.filter, f.filter_type]] == [["orders", "PREFIX_MATCH"]]
    error_message = "repository prefixes become PREFIX_MATCH filters."
  }

  assert {
    condition = jsonencode(output.replication_destination_requirements) == jsonencode({
      "444455556666" = {
        regions = ["eu-west-2"]
        registry_policy_statement = {
          Sid       = "ReplicationFrom111122223333"
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::111122223333:root" }
          Action    = ["ecr:CreateRepository", "ecr:ReplicateImage"]
          Resource  = "arn:aws:ecr:<region>:444455556666:repository/*"
        }
      }
    })
    error_message = "the other account is told exactly what its registry policy must grant; this account needs nothing."
  }
}

run "pull_through_cache_rules_use_each_upstreams_url" {
  command = plan

  assert {
    condition = alltrue([
      aws_ecr_pull_through_cache_rule.this["docker-hub"].upstream_registry_url == "registry-1.docker.io",
      aws_ecr_pull_through_cache_rule.this["docker-hub"].credential_arn == "arn:aws:secretsmanager:eu-west-2:111122223333:secret:ecr-pullthroughcache/docker-hub-AbCdEf",
      aws_ecr_pull_through_cache_rule.this["ecr-public"].upstream_registry_url == "public.ecr.aws",
      aws_ecr_pull_through_cache_rule.this["ecr-public"].credential_arn == null,
      aws_ecr_pull_through_cache_rule.this["shared"].upstream_registry_url == "444455556666.dkr.ecr.eu-west-2.amazonaws.com",
      aws_ecr_pull_through_cache_rule.this["shared"].custom_role_arn == "arn:aws:iam::111122223333:role/ptc-shared",
      aws_ecr_pull_through_cache_rule.this["shared"].upstream_repository_prefix == "base",
    ])
    error_message = "each upstream gets its documented URL, its secret or role, and nothing it does not use."
  }

  assert {
    condition = jsondecode(output.pull_through_cache_policy_json).Statement[0].Resource == [
      "arn:aws:ecr:eu-west-2:111122223333:repository/docker-hub/*",
      "arn:aws:ecr:eu-west-2:111122223333:repository/ecr-public/*",
      "arn:aws:ecr:eu-west-2:111122223333:repository/shared/*",
    ]
    error_message = "the consumer policy may import and create only under the cache prefixes."
  }
}

run "the_registry_policy_admits_replication_sources_and_cache_users" {
  command = plan

  assert {
    condition = jsondecode(aws_ecr_registry_policy.this[0].policy).Statement == [
      { Sid = "ReplicationFromAccounts", Effect = "Allow", Principal = { AWS = ["arn:aws:iam::777788889999:root"] }, Action = ["ecr:CreateRepository", "ecr:ReplicateImage"], Resource = "arn:aws:ecr:eu-west-2:111122223333:repository/*" },
      { Sid = "PullThroughCache", Effect = "Allow", Principal = { AWS = ["arn:aws:iam::111122223333:role/nodes"] }, Action = ["ecr:BatchImportUpstreamImage", "ecr:CreateRepository"], Resource = ["arn:aws:ecr:eu-west-2:111122223333:repository/docker-hub/*", "arn:aws:ecr:eu-west-2:111122223333:repository/ecr-public/*", "arn:aws:ecr:eu-west-2:111122223333:repository/shared/*"] },
    ]
    error_message = "the registry policy grants replication from the source accounts and cache imports under the cache prefixes, the forms AWS documents."
  }
}

run "templates_create_with_the_module_role_tags_and_lifecycle" {
  command = apply

  assert {
    condition = alltrue([
      aws_ecr_repository_creation_template.this["ROOT"].custom_role_arn == aws_iam_role.templates[0].arn,
      aws_ecr_repository_creation_template.this["ROOT"].image_tag_mutability == "MUTABLE",
      aws_ecr_repository_creation_template.this["ROOT"].encryption_configuration[0].encryption_type == "KMS",
      aws_ecr_repository_creation_template.this["ROOT"].resource_tags == tomap({ CostCenter = "cc-1", ManagedBy = "Terraform", Module = "ecr" }),
      jsondecode(aws_ecr_repository_creation_template.this["ROOT"].lifecycle_policy).rules[1].selection.countNumber == 50,
    ])
    error_message = "a template creates with the module's role, its own mutability and key, the module's tags and its lifecycle policy."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.templates[0].policy).Statement == [
      { Sid = "CreateTemplatedRepositories", Effect = "Allow", Action = ["ecr:CreateRepository", "ecr:ReplicateImage", "ecr:TagResource"], Resource = ["arn:aws:ecr:eu-west-2:111122223333:repository/*"] },
      { Sid = "EncryptTemplatedRepositories", Effect = "Allow", Action = ["kms:CreateGrant", "kms:DescribeKey", "kms:RetireGrant"], Resource = ["arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"] },
    ]
    error_message = "the template role may create, replicate into and tag repositories under its templates' prefixes (ROOT: all), and use only the templates' keys."
  }

  assert {
    condition     = jsondecode(aws_iam_role.templates[0].assume_role_policy).Statement[0].Principal == { Service = "ecr.amazonaws.com" }
    error_message = "ECR assumes the template role."
  }

  assert {
    condition     = [for e in output.kms_key_policy_requirements : e.sid if e.sid == "TemplateGrants0"] == ["TemplateGrants0"]
    error_message = "the template key's owner is told to admit the template role."
  }
}

run "a_template_role_is_scoped_to_its_prefixes" {
  command = plan

  variables {
    registry = {
      enabled            = true
      pull_through_cache = { "ecr-public" = { upstream = "ecr-public" } }
      creation_templates = { "ecr-public" = { applied_for = ["PULL_THROUGH_CACHE"], image_tag_mutability = "MUTABLE" } }
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.templates[0].policy).Statement == [{ Sid = "CreateTemplatedRepositories", Effect = "Allow", Action = ["ecr:CreateRepository", "ecr:ReplicateImage", "ecr:TagResource"], Resource = ["arn:aws:ecr:eu-west-2:111122223333:repository/ecr-public/*"] }]
    error_message = "a prefixed template's role reaches only that prefix, and no key without a template key."
  }

  assert {
    condition     = output.governance.cache_templates == { "ecr-public" = "ecr-public" }
    error_message = "governance shows which template each cache prefix gets."
  }
}

run "the_longest_template_prefix_wins_for_a_cache" {
  command = plan

  variables {
    registry = {
      enabled            = true
      pull_through_cache = { "hub/docker" = { upstream = "docker-hub", credential_secret_arn = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:ecr-pullthroughcache/hub-AbCdEf" } }
      creation_templates = {
        ROOT  = { applied_for = ["PULL_THROUGH_CACHE"], image_tag_mutability = "MUTABLE" }
        "hub" = { applied_for = ["PULL_THROUGH_CACHE"], image_tag_mutability = "MUTABLE" }
      }
    }
  }

  assert {
    condition     = output.governance.cache_templates == { "hub/docker" = "hub" }
    error_message = "hub/docker falls under the hub template, not ROOT."
  }
}

run "account_settings_and_exclusions_are_sent_only_when_set" {
  command = plan

  assert {
    condition = alltrue([
      keys(aws_ecr_account_setting.this) == ["BLOB_MOUNTING", "REGISTRY_POLICY_SCOPE"],
      aws_ecr_account_setting.this["REGISTRY_POLICY_SCOPE"].value == "V2",
      keys(aws_ecr_pull_time_update_exclusion.this) == ["arn:aws:iam::111122223333:role/scanner"],
    ])
    error_message = "only the account settings given are managed, and each exclusion is its own resource."
  }
}

run "registry_failures_reach_the_topic" {
  command = plan

  variables {
    sns_topic_arn = "arn:aws:sns:eu-west-2:111122223333:alerts"
  }

  assert {
    condition = alltrue([
      keys(aws_cloudwatch_event_rule.this) == ["pull-through-cache-failed", "replication-failed"],
      jsondecode(aws_cloudwatch_event_rule.this["replication-failed"].event_pattern).detail == { result = [{ "anything-but" = "SUCCESS" }] },
      jsondecode(aws_cloudwatch_event_rule.this["pull-through-cache-failed"].event_pattern).detail == { "sync-status" = [{ "anything-but" = "SUCCESS" }] },
    ])
    error_message = "a replication or cache sync that did not succeed publishes to the topic; without repositories there is no findings rule."
  }
}

run "the_deployer_may_create_exactly_the_service_linked_roles_in_use" {
  command = plan

  assert {
    condition = [for s in jsondecode(output.deployer_requirements.iam_policy).Statement : s.Resource if startswith(s.Sid, "ServiceLinkedRole")] == [
      "arn:aws:iam::111122223333:role/aws-service-role/pullthroughcache.ecr.amazonaws.com/AWSServiceRoleForECRPullThroughCache",
      "arn:aws:iam::111122223333:role/aws-service-role/ecr.amazonaws.com/AWSServiceRoleForECRTemplate",
      "arn:aws:iam::111122223333:role/aws-service-role/replication.ecr.amazonaws.com/AWSServiceRoleForECRReplication",
    ]
    error_message = "the service-linked roles AWS creates on first use are listed by their exact ARNs."
  }

  assert {
    condition     = one([for s in jsondecode(output.deployer_requirements.iam_policy).Statement : s if s.Sid == "PassTemplateRole"]).Condition == { StringEquals = { "iam:PassedToService" = "ecr.amazonaws.com" } }
    error_message = "the deployer passes the template role to ECR only."
  }
}
