# plan-level, mocked. hosted content is a pure function of vars, so exact
# bytes are assertable offline.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { name = "us-east-1" }
  }
}

variables {
  name = "checkout"
}

# --- minimal: an application and nothing else --------------------------------
run "defaults" {
  command = plan

  assert {
    condition     = length(aws_appconfig_application.this) == 1
    error_message = "Application should be created"
  }

  assert {
    condition = alltrue([
      length(aws_appconfig_environment.this) == 0,
      length(aws_appconfig_configuration_profile.this) == 0,
      length(aws_appconfig_hosted_configuration_version.this) == 0,
      length(aws_appconfig_deployment.this) == 0,
      length(aws_iam_role.monitor) == 0,
      length(aws_appconfig_extension.events) == 0,
    ])
    error_message = "Nothing beyond the application should exist by default"
  }
}

# --- feature flags render into the AWS format --------------------------------
run "feature_flags_render" {
  command = plan

  variables {
    profiles = {
      flags = {
        type = "feature-flags"
        flags = {
          checkout-v2 = {
            description = "new checkout path"
            enabled     = true
            attributes = {
              limit  = { type = "number", value = "42", required = true, minimum = 1, maximum = 100 }
              sticky = { type = "boolean", value = "true" }
              tier   = { type = "string", value = "gold", enum = ["gold", "silver"] }
            }
          }
          dark-mode = {
            enabled = false
          }
        }
      }
    }
  }

  assert {
    condition     = length(aws_appconfig_hosted_configuration_version.this) == 1
    error_message = "Feature-flags profile should produce a hosted version"
  }

  assert {
    condition = alltrue([
      strcontains(aws_appconfig_hosted_configuration_version.this["flags"].content, "\"version\":\"1\""),
      strcontains(aws_appconfig_hosted_configuration_version.this["flags"].content, "\"name\":\"checkout-v2\""),
      strcontains(aws_appconfig_hosted_configuration_version.this["flags"].content, "\"enabled\":true"),
      strcontains(aws_appconfig_hosted_configuration_version.this["flags"].content, "\"enabled\":false"),
    ])
    error_message = "Rendered document must carry the AWS format markers"
  }

  # type-correct values: number unquoted, boolean real, string quoted
  assert {
    condition = alltrue([
      strcontains(aws_appconfig_hosted_configuration_version.this["flags"].content, "\"limit\":42"),
      strcontains(aws_appconfig_hosted_configuration_version.this["flags"].content, "\"sticky\":true"),
      strcontains(aws_appconfig_hosted_configuration_version.this["flags"].content, "\"tier\":\"gold\""),
    ])
    error_message = "Attribute values must be cast to their declared types"
  }

  assert {
    condition = alltrue([
      strcontains(aws_appconfig_hosted_configuration_version.this["flags"].content, "\"required\":true"),
      strcontains(aws_appconfig_hosted_configuration_version.this["flags"].content, "\"minimum\":1"),
      strcontains(aws_appconfig_hosted_configuration_version.this["flags"].content, "\"enum\":[\"gold\",\"silver\"]"),
    ])
    error_message = "Constraints must render"
  }

  assert {
    condition     = aws_appconfig_configuration_profile.this["flags"].type == "AWS.AppConfig.FeatureFlags"
    error_message = "Profile type must map to the AWS enum"
  }
}

# --- freeform hosted: content passes through untouched ------------------------
run "freeform_hosted" {
  command = plan

  variables {
    profiles = {
      settings = {
        content     = "{\"timeout_ms\":250}"
        json_schema = "{\"type\":\"object\",\"required\":[\"timeout_ms\"]}"
      }
    }
  }

  assert {
    condition     = aws_appconfig_hosted_configuration_version.this["settings"].content == "{\"timeout_ms\":250}"
    error_message = "Freeform content must pass through untouched"
  }

  assert {
    condition     = aws_appconfig_configuration_profile.this["settings"].type == "AWS.Freeform"
    error_message = "Freeform profile type must map to the AWS enum"
  }
}

# --- external source: no hosted version, retrieval role wired -----------------
run "external_profile" {
  command = plan

  variables {
    profiles = {
      params = {
        location_uri       = "ssm-parameter://prod/checkout/config"
        retrieval_role_arn = "arn:aws:iam::123456789012:role/appconfig-retrieval"
      }
    }
  }

  assert {
    condition     = length(aws_appconfig_hosted_configuration_version.this) == 0
    error_message = "External profiles must not create hosted versions"
  }
}

# --- environments with alarms get the monitor role automatically --------------
run "monitor_role" {
  command = plan

  variables {
    environments = {
      prod    = { alarm_arns = ["arn:aws:cloudwatch:us-east-1:123456789012:alarm:api-5xx"] }
      staging = {}
    }
  }

  assert {
    condition = alltrue([
      length(aws_appconfig_environment.this) == 2,
      length(aws_iam_role.monitor) == 1,
      length(aws_iam_role_policy.monitor) == 1,
    ])
    error_message = "Alarmed environments should auto-create the monitor role"
  }
}

run "monitor_role_byo" {
  command = plan

  variables {
    environments = {
      prod = { alarm_arns = ["arn:aws:cloudwatch:us-east-1:123456789012:alarm:api-5xx"] }
    }
    monitor_role_arn = "arn:aws:iam::123456789012:role/my-monitor"
  }

  assert {
    condition     = length(aws_iam_role.monitor) == 0
    error_message = "BYO monitor role should suppress role creation"
  }
}

# --- custom strategy + deployments --------------------------------------------
run "strategy_and_deployments" {
  command = plan

  variables {
    environments = {
      prod = {}
    }
    profiles = {
      settings = { content = "{\"timeout_ms\":250}" }
    }
    deployment_strategies = {
      careful = {
        deployment_duration_minutes = 30
        growth_factor               = 10
        growth_type                 = "LINEAR"
        bake_time_minutes           = 15
      }
    }
    deployments = [
      { environment = "prod", profile = "settings", strategy = "careful" },
    ]
  }

  assert {
    condition = alltrue([
      aws_appconfig_deployment_strategy.this["careful"].deployment_duration_in_minutes == 30,
      aws_appconfig_deployment_strategy.this["careful"].growth_factor == 10,
      aws_appconfig_deployment_strategy.this["careful"].final_bake_time_in_minutes == 15,
    ])
    error_message = "Custom strategy attributes should pass through"
  }

  assert {
    condition     = length(aws_appconfig_deployment.this) == 1
    error_message = "One deployment should be planned"
  }
}

# --- preset strategy needs no created resource ---------------------------------
run "preset_strategy" {
  command = plan

  variables {
    environments = { prod = {} }
    profiles = {
      settings = { content = "{}" }
    }
    deployments = [
      { environment = "prod", profile = "settings" }, # default = canary preset
    ]
  }

  assert {
    condition     = length(aws_appconfig_deployment_strategy.this) == 0 && length(aws_appconfig_deployment.this) == 1
    error_message = "Preset strategies deploy without creating strategy resources"
  }
}

# --- notifications: topic, scoped role, extension, association -----------------
run "notifications" {
  command = plan

  variables {
    enable_notifications = true
    alert_emails         = ["platform@example.com"]
  }

  assert {
    condition = alltrue([
      length(aws_sns_topic.events) == 1,
      length(aws_sns_topic_subscription.email) == 1,
      length(aws_iam_role.events) == 1,
      length(aws_appconfig_extension.events) == 1,
      length(aws_appconfig_extension_association.events) == 1,
    ])
    error_message = "Notifications should build topic, role, extension, association"
  }
}

run "notifications_byo_topic" {
  command = plan

  variables {
    enable_notifications = true
    alert_sns_topic_arn  = "arn:aws:sns:us-east-1:123456789012:existing"
  }

  assert {
    condition     = length(aws_sns_topic.events) == 0 && length(aws_appconfig_extension.events) == 1
    error_message = "BYO topic should suppress topic creation but keep the extension"
  }
}

# --- create = false still renders the review artifacts -------------------------
run "create_false_renders" {
  command = plan

  variables {
    create = false
    profiles = {
      flags = {
        type  = "feature-flags"
        flags = { dark-mode = { enabled = true } }
      }
    }
  }

  assert {
    condition     = length(aws_appconfig_application.this) == 0
    error_message = "create=false must build nothing"
  }

  assert {
    condition     = strcontains(output.feature_flags_json["flags"], "\"dark-mode\"")
    error_message = "feature_flags_json must render offline (create=false) for review/CI"
  }
}

# --- per_environment overlay: one generated profile per env -------------------
run "env_overlay" {
  command = plan

  variables {
    environments = {
      staging = {}
      prod    = {}
    }
    profiles = {
      flags = {
        type = "feature-flags"
        flags = {
          checkout-v2 = {
            enabled = false # base
            attributes = {
              rollout-percent = { type = "number", value = "10" }
            }
            per_environment = {
              staging = { enabled = true }
              prod    = { attributes = { rollout-percent = "50" } }
            }
          }
        }
      }
    }
    deployments = [
      { environment = "prod", profile = "flags" },
    ]
  }

  # fan-out: one instance per environment, correctly named
  assert {
    condition = alltrue([
      length(aws_appconfig_configuration_profile.this) == 2,
      length(aws_appconfig_hosted_configuration_version.this) == 2,
      aws_appconfig_configuration_profile.this["flags:prod"].name == "flags-prod",
      aws_appconfig_configuration_profile.this["flags:staging"].name == "flags-staging",
    ])
    error_message = "Specialized profile should fan out into one named instance per environment"
  }

  # staging: enabled overridden true, base attribute value kept
  assert {
    condition = alltrue([
      strcontains(aws_appconfig_hosted_configuration_version.this["flags:staging"].content, "\"enabled\":true"),
      strcontains(aws_appconfig_hosted_configuration_version.this["flags:staging"].content, "\"rollout-percent\":10"),
    ])
    error_message = "Staging instance must carry the enabled override and the base attribute value"
  }

  # prod: base enabled kept, attribute value overridden (and type-cast)
  assert {
    condition = alltrue([
      strcontains(aws_appconfig_hosted_configuration_version.this["flags:prod"].content, "\"enabled\":false"),
      strcontains(aws_appconfig_hosted_configuration_version.this["flags:prod"].content, "\"rollout-percent\":50"),
    ])
    error_message = "Prod instance must inherit enabled and carry the overridden attribute value"
  }

  # a deployment of the specialized profile resolves to its env's instance
  assert {
    condition     = length(aws_appconfig_deployment.this) == 1
    error_message = "Deployment must resolve to the env-specialized instance"
  }
}

# --- overlay renders offline too ----------------------------------------------
run "env_overlay_create_false" {
  command = plan

  variables {
    create       = false
    environments = { prod = {} }
    profiles = {
      flags = {
        type = "feature-flags"
        flags = {
          dark-mode = { enabled = false, per_environment = { prod = { enabled = true } } }
        }
      }
    }
  }

  assert {
    condition     = strcontains(output.feature_flags_json["flags:prod"], "\"enabled\":true")
    error_message = "Env-specialized documents must render with create = false"
  }
}

# ============================================================================
# VALIDATION FAILURES
# ============================================================================

run "bad_profile_type_fails" {
  command = plan
  variables {
    profiles = { x = { type = "yaml" } }
  }
  expect_failures = [var.profiles]
}

run "flags_with_content_fails" {
  command = plan
  variables {
    profiles = {
      x = { type = "feature-flags", content = "{}", flags = { f = { enabled = true } } }
    }
  }
  expect_failures = [var.profiles]
}

run "flags_with_schema_fails" {
  command = plan
  variables {
    profiles = {
      x = { type = "feature-flags", json_schema = "{}", flags = { f = { enabled = true } } }
    }
  }
  expect_failures = [var.profiles]
}

run "external_without_retrieval_role_fails" {
  command = plan
  variables {
    profiles = { x = { location_uri = "ssm-parameter://thing" } }
  }
  expect_failures = [var.profiles]
}

run "uncastable_number_fails" {
  command = plan
  variables {
    profiles = {
      x = {
        type  = "feature-flags"
        flags = { f = { enabled = true, attributes = { n = { type = "number", value = "not-a-number" } } } }
      }
    }
  }
  expect_failures = [var.profiles]
}

run "required_without_value_fails" {
  command = plan
  variables {
    profiles = {
      x = {
        type  = "feature-flags"
        flags = { f = { enabled = true, attributes = { n = { type = "string", required = true } } } }
      }
    }
  }
  expect_failures = [var.profiles]
}

run "too_many_alarms_fails" {
  command = plan
  variables {
    environments = {
      prod = { alarm_arns = ["a1", "a2", "a3", "a4", "a5", "a6"] }
    }
  }
  expect_failures = [var.environments]
}

run "bad_growth_type_fails" {
  command = plan
  variables {
    deployment_strategies = {
      x = { deployment_duration_minutes = 10, growth_type = "SIGMOID" }
    }
  }
  expect_failures = [var.deployment_strategies]
}

run "reserved_strategy_name_fails" {
  command = plan
  variables {
    deployment_strategies = {
      "AppConfig.Sneaky" = { deployment_duration_minutes = 10 }
    }
  }
  expect_failures = [var.deployment_strategies]
}

run "deployment_unknown_environment_fails" {
  command = plan
  variables {
    profiles    = { settings = { content = "{}" } }
    deployments = [{ environment = "nope", profile = "settings" }]
  }
  expect_failures = [var.deployments]
}

run "duplicate_deployment_pair_fails" {
  command = plan
  variables {
    environments = { prod = {} }
    profiles     = { settings = { content = "{}" } }
    deployments = [
      { environment = "prod", profile = "settings" },
      { environment = "prod", profile = "settings", strategy = "AppConfig.AllAtOnce" },
    ]
  }
  expect_failures = [var.deployments]
}

run "deployment_of_external_without_version_fails" {
  command = plan
  variables {
    environments = { prod = {} }
    profiles = {
      params = {
        location_uri       = "ssm-parameter://thing"
        retrieval_role_arn = "arn:aws:iam::123456789012:role/r"
      }
    }
    deployments = [{ environment = "prod", profile = "params" }]
  }
  expect_failures = [var.deployments]
}

run "bad_notification_point_fails" {
  command = plan
  variables {
    enable_notifications = true
    notification_points  = ["ON_COFFEE_BREAK"]
  }
  expect_failures = [var.notification_points]
}

# shared flags definition + per-env tfvars workspaces: this state only declares
# prod, but the code carries dev/stage overrides too - they are ignored here
# and only the declared env's instance renders
run "overlay_foreign_envs_ignored" {
  command = plan
  variables {
    environments = { prod = {} }
    profiles = {
      x = {
        type = "feature-flags"
        flags = {
          f = {
            enabled = false
            per_environment = {
              dev   = { enabled = true }
              stage = { enabled = true }
              prod  = { enabled = false }
            }
          }
        }
      }
    }
  }

  assert {
    condition = alltrue([
      length(aws_appconfig_configuration_profile.this) == 1,
      contains(keys(aws_appconfig_configuration_profile.this), "x:prod"),
      strcontains(aws_appconfig_hosted_configuration_version.this["x:prod"].content, "\"enabled\":false"),
    ])
    error_message = "Only the declared environment's instance should render; foreign override keys are ignored"
  }
}

run "overlay_unknown_attribute_fails" {
  command = plan
  variables {
    environments = { prod = {} }
    profiles = {
      x = {
        type = "feature-flags"
        flags = {
          f = {
            enabled         = true
            attributes      = { a = { type = "string", value = "x" } }
            per_environment = { prod = { attributes = { nope = "y" } } }
          }
        }
      }
    }
  }
  expect_failures = [var.profiles]
}

run "overlay_uncastable_override_fails" {
  command = plan
  variables {
    environments = { prod = {} }
    profiles = {
      x = {
        type = "feature-flags"
        flags = {
          f = {
            enabled         = true
            attributes      = { n = { type = "number", value = "1" } }
            per_environment = { prod = { attributes = { n = "not-a-number" } } }
          }
        }
      }
    }
  }
  expect_failures = [var.profiles]
}

run "bad_default_strategy_fails" {
  command = plan
  variables {
    default_deployment_strategy = "yolo"
  }
  expect_failures = [var.default_deployment_strategy]
}
