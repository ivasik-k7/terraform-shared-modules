# Plan properties of keel-billing. The baseline is fully configured, so the
# module's own checks pass.
#
# What a mock cannot show: AWS accepting a cost category, a managed monitor
# finding an anomaly, a budget firing, a billing view deriving from the
# primary view, RAM sharing it, or the CID template deploying.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "444444444444" }
  }
  mock_data "aws_billing_views" {
    defaults = { billing_view = [{ arn = "arn:aws:billing::444444444444:billingview/primary", billing_view_type = "PRIMARY", description = "", name = "Primary View", owner_account_id = "444444444444" }] }
  }
  mock_resource "aws_sns_topic" {
    override_during = plan
    defaults        = { arn = "arn:aws:sns:us-east-1:444444444444:keel-mock" }
  }
  mock_resource "aws_iam_role" {
    override_during = plan
    defaults        = { arn = "arn:aws:iam::444444444444:role/mock" }
  }
  mock_resource "aws_sqs_queue" {
    override_during = plan
    defaults        = { arn = "arn:aws:sqs:us-east-1:444444444444:mock", url = "https://sqs.us-east-1.amazonaws.com/444444444444/mock" }
  }
  mock_resource "aws_billing_view" {
    override_during = plan
    defaults        = { arn = "arn:aws:billing::444444444444:billingview/custom-mock" }
  }
  mock_resource "aws_ram_resource_share" {
    override_during = plan
    defaults        = { arn = "arn:aws:ram:us-east-1:444444444444:resource-share/mock" }
  }
}

variables {
  cost_allocation_tags = ["Team", "BusinessUnit", "Platform"]
  cost_categories = {
    BusinessUnit = {
      rules            = [{ value = "lending", accounts = ["111111111111"] }, { value = "platform", tag_key = "Team", tag_values = ["platform"] }]
      inherit_from_tag = "BusinessUnit"
    }
  }
  anomaly_detection = {
    cost_category_values = { BusinessUnit = ["lending"] }
    alert                = { min_impact_absolute = 100, emails = ["finops@example.com"] }
    digests              = { weekly = { frequency = "WEEKLY", min_impact_absolute = 50, emails = ["finops@example.com"] } }
  }
  limits = {
    total   = { amount = "100000", owners = ["finops@example.com"] }
    lending = { amount = "40000", scope = { cost_categories = { BusinessUnit = ["lending"] } }, owners = ["lending@example.com"] }
  }
  commitments = {
    savings_plans_utilization = 95
    ri_coverage               = { "Amazon Relational Database Service" = 80 }
  }
  billing_views = {
    ledger = { tag = { key = "Platform", values = ["ledger"] }, share_with = ["111111111111", "222222222222"] }
  }
  finops_agent        = { enabled = true, delegated_admin_account_id = "333333333333" }
  signals             = { control_plane_bus_arn = "arn:aws:events:eu-west-2:333333333333:event-bus/keel" }
  acknowledged_checks = ["finops_agent_is_approved"]
}

run "the_owner_taxonomy_is_built_from_accounts_then_tags_then_the_inherited_tag" {
  command = plan

  assert {
    condition     = length(aws_ce_cost_category.this["BusinessUnit"].rule) == 3
    error_message = "two regular rules and the inherited-value rule."
  }

  assert {
    condition     = aws_ce_cost_category.this["BusinessUnit"].default_value == "Unallocated"
    error_message = "unallocated spend stays visible under its own value."
  }
}

run "managed_monitors_by_service_and_account_and_one_per_business_unit" {
  command = plan

  assert {
    condition     = jsonencode(sort(keys(aws_ce_anomaly_monitor.this))) == jsonencode(["accounts", "category-businessunit-lending", "services"])
    error_message = "the two AWS managed monitors and a monitor per cost category value."
  }
}

run "a_cost_category_value_is_a_customer_managed_monitor" {
  # The provider declares a managed monitor by dimension only; a COST_CATEGORY
  # managed monitor needs a key, so the dimension and the key together failed
  # to plan.
  command = plan

  assert {
    condition     = aws_ce_anomaly_monitor.this["category-businessunit-lending"].monitor_type == "CUSTOM" ? aws_ce_anomaly_monitor.this["category-businessunit-lending"].monitor_dimension == null : false
    error_message = "a business unit is watched by a customer managed monitor, with no dimension."
  }

  assert {
    condition     = aws_ce_anomaly_monitor.this["category-businessunit-lending"].monitor_specification == jsonencode({ CostCategories = { Key = "BusinessUnit", Values = ["lending"] } })
    error_message = "one value per monitor, AWS's limit for cost category values."
  }
}

run "one_immediate_alert_and_digests_to_email" {
  # Each immediate subscription an anomaly matches emits its own event; one
  # keeps the control plane at one event per anomaly.
  command = plan

  assert {
    condition     = length([for k, s in aws_ce_anomaly_subscription.this : k if s.frequency == "IMMEDIATE"]) == 1
    error_message = "exactly one immediate subscription."
  }

  assert {
    condition     = one([for s in aws_ce_anomaly_subscription.this["alert"].subscriber : s.address]) == output.anomaly_alert_topic_arn
    error_message = "the immediate alert publishes to the anomaly alert topic, which is not bridged to the control plane."
  }

  assert {
    condition     = one([for s in aws_ce_anomaly_subscription.this["digest-weekly"].subscriber : s.type]) == "EMAIL"
    error_message = "digests go to the listed emails."
  }
}

run "anomaly_events_reach_the_control_plane_once" {
  command = plan

  assert {
    condition     = contains(module.signals.forwarding.rules, "anomalies")
    error_message = "the Anomaly Detected events are forwarded to the control plane."
  }
}

run "organization_limits_alert_by_severity" {
  command = plan

  assert {
    condition     = jsonencode(module.limits.governance["lending"].scope) == jsonencode(["BusinessUnit = lending"])
    error_message = "a business-unit limit counts its cost category value."
  }

  assert {
    condition     = contains(keys(output.controls), "LIMIT-total") && contains(keys(output.controls), "FC-04")
    error_message = "each limit is a register entry, and the spend limits implement FC-04."
  }
}

run "commitment_targets_become_commitment_limits" {
  command = plan

  assert {
    condition     = module.limits.governance["sp-utilization"].type == "SAVINGS_PLANS_UTILIZATION" && module.limits.governance["sp-utilization"].limit == "95% monthly"
    error_message = "the Savings Plans utilization target is a commitment budget at 95%."
  }

  assert {
    condition     = module.limits.governance["ri-coverage-amazon-relational-database"].type == "RI_COVERAGE"
    error_message = "an RI target is keyed by its service."
  }
}

run "a_billing_view_derives_from_the_primary_view_and_is_shared_in_the_organization" {
  command = plan

  assert {
    condition     = jsonencode(aws_billing_view.this["ledger"].source_views) == jsonencode(["arn:aws:billing::444444444444:billingview/primary"])
    error_message = "the view is a filtered slice of the primary view."
  }

  assert {
    condition     = aws_billing_view.this["ledger"].data_filter_expression[0].tags[0].key == "Platform"
    error_message = "the view filters on its tag."
  }

  assert {
    condition     = !aws_ram_resource_share.views["ledger"].allow_external_principals && length(aws_ram_principal_association.views) == 2
    error_message = "the view is shared with each listed account, inside the organization only."
  }
}

run "finops_agent_is_a_documented_decision_not_a_half_setup" {
  # Trusted access through AWS Organizations alone does not complete the
  # agent's organization setup, so the module creates nothing for it.
  command = plan

  assert {
    condition     = strcontains(output.finops_agent_setup.management_account_policy, "finops-agent:UpdateOrganizationAccess") ? length(output.finops_agent_setup.steps) == 4 : false
    error_message = "the console steps, the delegation and the policy the person needs are emitted."
  }
}

run "finops_agent_warns_until_its_access_is_approved" {
  command = plan

  variables {
    acknowledged_checks = []
  }

  expect_failures = [check.finops_agent_is_approved]
}

run "the_exports_stack_runs_in_the_destinations_region" {
  # The template sends each export to the bucket in the stack's own Region.
  command = plan

  variables {
    data_exports = { enabled = true, destination_account_id = "333333333333", region = "eu-west-2" }
  }

  assert {
    condition     = aws_cloudformation_stack.data_exports_source[0].region == "eu-west-2"
    error_message = "the source stack runs where keel-insights' bucket is."
  }
}

run "the_exports_template_can_come_from_the_estates_mirror" {
  command = plan

  variables {
    data_exports = { enabled = true, destination_account_id = "333333333333", region = "eu-west-2", template_url_prefix = "https://cid-mirror.s3.eu-west-2.amazonaws.com/cfn" }
  }

  assert {
    condition     = aws_cloudformation_stack.data_exports_source[0].template_url == "https://cid-mirror.s3.eu-west-2.amazonaws.com/cfn/data-exports/0.13.0/data-exports-aggregation.yaml" ? output.data_exports_stack.reviewed_sha256 == "1eba08e62689ecc5feb81ce452e6216ad736897c6d66510be605e5da02855009" : false
    error_message = "the template comes from the mirror, with the reviewed hash to compare it against."
  }
}

run "exports_without_a_region_are_rejected" {
  command = plan

  variables {
    data_exports = { enabled = true, destination_account_id = "333333333333" }
  }

  expect_failures = [var.data_exports]
}

run "a_category_tag_that_is_not_activated_warns" {
  # A tag that is not an active cost allocation tag matches no spend.
  command = plan

  variables {
    cost_allocation_tags = ["Team"]
  }

  expect_failures = [check.spend_is_allocated_by_tags]
}

run "a_limit_with_its_own_anomaly_monitor_is_rejected" {
  # Its alerts would reach the control plane twice: through the severity topic
  # and as an Anomaly Detected event.
  command = plan

  variables {
    limits = { total = { amount = "100000", anomaly = {} } }
  }

  expect_failures = [var.limits]
}

run "a_billing_view_on_accounts_and_a_tag_is_rejected" {
  command = plan

  variables {
    billing_views = { both = { accounts = ["111111111111"], tag = { key = "Platform", values = ["x"] } } }
  }

  expect_failures = [var.billing_views]
}

run "a_weekly_digest_without_emails_is_rejected" {
  command = plan

  variables {
    anomaly_detection = { digests = { weekly = { frequency = "WEEKLY", min_impact_absolute = 100, emails = [] } } }
  }

  expect_failures = [var.anomaly_detection]
}

run "create_false_plans_nothing" {
  command = plan

  variables {
    create = false
  }

  assert {
    condition = alltrue([
      length(aws_ce_cost_category.this) == 0, length(aws_ce_anomaly_monitor.this) == 0, length(aws_billing_view.this) == 0,
      output.finops_agent_setup == null, length(output.budget_names) == 0, length(output.topic_arns) == 0,
      output.controls == null, output.governance == null, output.anomaly_alert_topic_arn == null,
    ])
    error_message = "create = false creates nothing and leaves outputs null or empty."
  }
}
