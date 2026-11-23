# Plan properties of keel-control-plane.
#
# What a mock cannot show: EventBridge matching a real event, Firehose writing
# to an Object Lock bucket, or a topic delivering.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "333333333333" }
  }
}

variables {
  sources = { organization_id = "o-abcdefghij" }
  severity = {
    emails = { warning = ["finops@example.com"], high = ["finops@example.com"], critical = ["oncall@example.com"] }
  }
  evidence = { mode = "COMPLIANCE" }
}

run "anomalies_are_routed_by_impact_band" {
  command = plan

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.anomaly["high"].event_pattern).detail.impact.totalImpact[0].numeric == [">=", 1000, "<", 5000]
    error_message = "HIGH is an impact of 1000 up to 5000."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.anomaly["critical"].event_pattern).detail.impact.totalImpact[0].numeric == [">=", 5000]
    error_message = "CRITICAL is 5000 or more."
  }
}

run "the_burn_alarm_is_critical_and_others_high_without_duplicates" {
  command = plan

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.alarm["critical"].event_pattern).detail.alarmName == [{ suffix = "-ai-burn" }]
    error_message = "alarms ending -ai-burn are CRITICAL."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.alarm["high"].event_pattern).detail.alarmName == [{ "anything-but" = { suffix = "-ai-burn" } }]
    error_message = "every other alarm is HIGH, so no alarm reaches two topics."
  }
}

run "signals_are_routed_at_the_severity_of_their_topic" {
  command = plan

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.signal["high"].event_pattern).source[0] == "keel.high" ? aws_cloudwatch_event_target.signal["high"].arn == output.topic_arns["high"] : false
    error_message = "a signal from an account's HIGH topic goes to the HIGH topic here."
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.signal) == 4
    error_message = "one rule per severity."
  }
}

run "every_event_is_kept_in_a_locked_bucket" {
  command = plan

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.evidence[0].event_pattern) == { version = ["0"] }
    error_message = "the evidence rule matches every event."
  }

  assert {
    condition     = output.evidence_bucket == "keel-evidence-333333333333-eu-west-2" ? aws_kinesis_firehose_delivery_stream.evidence[0].extended_s3_configuration[0].bucket_arn == "arn:aws:s3:::keel-evidence-333333333333-eu-west-2" : false
    error_message = "the stream writes to the evidence bucket."
  }
}

run "the_organization_may_send" {
  command = plan

  assert {
    condition     = jsondecode(aws_cloudwatch_event_bus_policy.this[0].policy).Statement[0].Condition.StringEquals["aws:PrincipalOrgID"] == "o-abcdefghij"
    error_message = "every account in the organization may put events, and no one else."
  }
}

run "governance_mode_warns" {
  command = plan

  variables {
    evidence = { mode = "GOVERNANCE" }
  }

  expect_failures = [check.evidence_is_immutable]
}

run "inverted_bands_are_rejected" {
  command = plan

  variables {
    severity = { anomaly_warning = 1000, anomaly_high = 500 }
  }

  expect_failures = [var.severity]
}

run "create_false_plans_nothing" {
  command = plan

  variables {
    create = false
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus.this) == 0 && length(aws_sns_topic.severity) == 0 && output.event_bus_arn == null && output.controls == null
    error_message = "create = false creates nothing."
  }
}
