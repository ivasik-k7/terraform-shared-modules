# Plan properties of keel-limits.
#
# What a mock cannot show: AWS Budgets accepting a filter, a budget firing, a
# lock or SCP action running, or an anomaly monitor accepting its
# specification.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_resource "aws_iam_role" {
    override_during = plan
    defaults        = { arn = "arn:aws:iam::111111111111:role/mock" }
  }
  mock_resource "aws_iam_policy" {
    override_during = plan
    defaults        = { arn = "arn:aws:iam::111111111111:policy/mock" }
  }
}

variables {
  name = "lending"
  topic_arns = {
    info     = "arn:aws:sns:eu-west-2:111111111111:lending-info"
    warning  = "arn:aws:sns:eu-west-2:111111111111:lending-warning"
    high     = "arn:aws:sns:eu-west-2:111111111111:lending-high"
    critical = "arn:aws:sns:eu-west-2:111111111111:lending-critical"
  }
  limits = {
    account = { amount = "100000", owners = ["owner@example.com"] }
    ledger  = { amount = "70000", scope = { tags = { Platform = ["ledger"] } }, anomaly = { min_impact = 1000 } }
    payments-eu = {
      amount = "35000"
      scope  = { tags = { Platform = ["payments"] }, regions = ["eu-west-2", "eu-west-1"] }
    }
    dev = {
      tier   = "non-production"
      amount = "6000"
      scope  = { tags = { Environment = ["dev"] } }
      action = { lock_roles = ["developer"] }
    }
    inter-az       = { type = "USAGE", amount = "200000", unit = "GB", scope = { usage_type_groups = ["EC2: Data Transfer - Inter AZ"] } }
    sp-utilization = { type = "SAVINGS_PLANS_UTILIZATION", target_percent = 95 }
    rds-ri         = { type = "RI_COVERAGE", target_percent = 80, scope = { services = ["Amazon Relational Database Service"] } }
  }
}

run "thresholds_alert_at_their_severity" {
  command = plan

  assert {
    condition     = jsonencode(output.thresholds["account"]) == jsonencode(["forecasted 80%: WARNING", "forecasted 100%: WARNING", "actual 90%: WARNING", "actual 100%: HIGH", "actual 120%: CRITICAL"])
    error_message = "production: forecasts WARNING, actual WARNING below the limit, HIGH from it, CRITICAL from 120%."
  }

  assert {
    condition     = one([for n in aws_budgets_budget.spend["account"].notification : n.subscriber_sns_topic_arns if n.threshold == 120 && n.notification_type == "ACTUAL"]) == toset(["arn:aws:sns:eu-west-2:111111111111:lending-critical"])
    error_message = "the 120% notification goes to the critical topic."
  }
}

run "an_unscoped_limit_uses_cost_types_and_a_scoped_one_its_metric" {
  # The provider takes metrics only with a filter.
  command = plan

  assert {
    condition     = aws_budgets_budget.spend["account"].metrics == null && aws_budgets_budget.spend["account"].cost_types[0].use_amortized
    error_message = "the whole-account limit is amortized through cost_types."
  }

  assert {
    condition     = jsonencode(aws_budgets_budget.spend["ledger"].metrics) == jsonencode(["AmortizedCost"]) && aws_budgets_budget.spend["ledger"].filter_expression[0].tags[0].key == "Platform"
    error_message = "a one-tag limit filters on the tag directly."
  }
}

run "a_scope_of_several_filters_is_anded" {
  command = plan

  assert {
    condition     = length(aws_budgets_budget.spend["payments-eu"].filter_expression[0].and) == 2
    error_message = "the platform tag and the Regions are joined with and."
  }
}

run "a_usage_limit_counts_usage_quantity" {
  command = plan

  assert {
    condition     = jsonencode(aws_budgets_budget.spend["inter-az"].metrics) == jsonencode(["UsageQuantity"]) && aws_budgets_budget.spend["inter-az"].limit_unit == "GB"
    error_message = "a usage limit measures usage in its unit."
  }
}

run "commitment_limits_alert_below_target" {
  command = plan

  assert {
    condition     = aws_budgets_budget.commitment["sp-utilization"].limit_amount == "100" && aws_budgets_budget.commitment["sp-utilization"].limit_unit == "PERCENTAGE"
    error_message = "commitment budgets measure against 100 percent."
  }

  assert {
    condition     = one(aws_budgets_budget.commitment["sp-utilization"].notification).comparison_operator == "LESS_THAN" && one(aws_budgets_budget.commitment["sp-utilization"].notification).threshold == 95
    error_message = "the alert fires when utilization falls below the target."
  }

  assert {
    condition     = one(aws_budgets_budget.commitment["rds-ri"].cost_filter).name == "Service"
    error_message = "an RI budget names its service."
  }
}

run "an_anomaly_monitor_watches_exactly_the_limits_scope" {
  command = plan

  assert {
    condition     = aws_ce_anomaly_monitor.this["ledger"].monitor_specification == jsonencode({ Tags = { Key = "Platform", Values = ["ledger"] } })
    error_message = "the monitor watches the platform's tag value."
  }

  assert {
    condition     = one(aws_ce_anomaly_subscription.this["ledger"].subscriber).address == "arn:aws:sns:eu-west-2:111111111111:lending-high"
    error_message = "production anomalies alert HIGH."
  }
}

run "a_non_production_limit_locks_its_roles_automatically" {
  command = plan

  assert {
    condition     = aws_budgets_budget_action.this["dev"].approval_model == "AUTOMATIC" && aws_budgets_budget_action.this["dev"].action_type == "APPLY_IAM_POLICY"
    error_message = "non-production may lock without a person."
  }

  assert {
    condition     = contains(jsondecode(aws_iam_policy.lock["dev"].policy).Statement[0].Action, "ec2:RunInstances")
    error_message = "the lock denies the actions that start new spend."
  }
}

run "an_automatic_action_in_production_warns" {
  command = plan

  variables {
    limits = { account = { amount = "100000", owners = ["owner@example.com"], action = { lock_roles = ["developer"] } } }
  }

  expect_failures = [check.production_changes_only_by_people]
}

run "an_anomaly_monitor_on_two_filters_is_refused" {
  # A monitor watches one tag key, one cost category or one set of accounts.
  command = plan

  variables {
    limits = { both = { amount = "1", scope = { tags = { Platform = ["x"] }, regions = ["eu-west-2"] }, anomaly = {} } }
  }

  expect_failures = [aws_ce_anomaly_monitor.this["both"]]
}

run "a_net_metric_without_a_scope_is_rejected" {
  # An unscoped budget takes its basis from cost_types, which have no net option.
  command = plan

  variables {
    limits = { account = { amount = "1", metric = "NetAmortizedCost" } }
  }

  expect_failures = [var.limits]
}

run "an_action_on_a_commitment_limit_is_rejected" {
  command = plan

  variables {
    limits = { sp = { type = "SAVINGS_PLANS_COVERAGE", target_percent = 80, action = { lock_roles = ["x"] } } }
  }

  expect_failures = [var.limits]
}

run "a_severity_without_a_topic_warns" {
  command = plan

  variables {
    topic_arns = { warning = "arn:aws:sns:eu-west-2:111111111111:lending-warning" }
    limits     = { account = { amount = "100000", owners = ["owner@example.com"] } }
  }

  expect_failures = [check.every_limit_has_an_owner]
}

run "a_threshold_nobody_receives_is_refused" {
  # AWS Budgets refuses a notification with no subscriber, at apply.
  command = plan

  variables {
    topic_arns          = { warning = "arn:aws:sns:eu-west-2:111111111111:lending-warning" }
    limits              = { account = { amount = "100000" } }
    acknowledged_checks = ["every_limit_has_an_owner"]
  }

  expect_failures = [aws_budgets_budget.spend["account"]]
}

run "a_lock_reaches_roles_under_a_path" {
  # A role at a path has an ARN role/<path>/<name>; a policy on role/<name>
  # alone left the lock unable to attach.
  command = plan

  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.lock["dev"].policy).Statement[0].Resource, "arn:aws:iam::111111111111:role/*/developer")
    error_message = "the lock may attach to the named role at any path."
  }
}

run "aws_budgets_assumes_the_action_role_only_for_this_accounts_budgets" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.action["dev"].assume_role_policy).Statement[0].Condition.ArnLike["aws:SourceArn"] == "arn:aws:budgets::111111111111:budget/*"
    error_message = "the trust names the budgets, as AWS's example does."
  }
}

run "a_commitment_limit_on_a_tag_is_rejected" {
  # A commitment budget filters on services and accounts only; a tag scope
  # was dropped and the whole account measured.
  command = plan

  variables {
    limits = { sp = { type = "SAVINGS_PLANS_COVERAGE", target_percent = 80, scope = { tags = { Platform = ["ledger"] } } } }
  }

  expect_failures = [var.limits]
}

run "a_cost_category_monitor_on_two_values_is_refused" {
  # A customer managed monitor tracks one cost category value.
  command = plan

  variables {
    limits = { units = { amount = "1", scope = { cost_categories = { BusinessUnit = ["lending", "payments"] } }, anomaly = {} } }
  }

  expect_failures = [aws_ce_anomaly_monitor.this["units"]]
}

run "create_false_plans_nothing" {
  command = plan

  variables {
    create = false
  }

  assert {
    condition     = length(aws_budgets_budget.spend) + length(aws_budgets_budget.commitment) + length(aws_ce_anomaly_monitor.this) + length(aws_budgets_budget_action.this) == 0 && output.controls == null && output.governance == null && length(output.budget_names) == 0
    error_message = "create = false creates nothing and leaves the outputs empty."
  }
}
