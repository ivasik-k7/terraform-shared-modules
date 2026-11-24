# Plan properties of keel-control-plane.
#
# What a mock cannot show: EventBridge matching a real event, Firehose writing
# to an Object Lock bucket, or a topic delivering.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  # modules/s3 reads its Region from the endpoint.
  mock_data "aws_region" {
    defaults = { region = "eu-west-2", endpoint = "ec2.eu-west-2.amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "333333333333" }
  }
  mock_resource "aws_sns_topic" {
    override_during = plan
    defaults        = { arn = "arn:aws:sns:eu-west-2:333333333333:keel-mock" }
  }
  mock_resource "aws_cloudwatch_event_bus" {
    override_during = plan
    defaults        = { arn = "arn:aws:events:eu-west-2:333333333333:event-bus/keel" }
  }
}

# A fully configured baseline: a customer key, and access logging
# acknowledged because this module exposes no log target for the bucket.
variables {
  kms_key_arn         = "arn:aws:kms:eu-west-2:333333333333:key/11111111-2222-3333-4444-555555555555"
  acknowledged_checks = ["access_is_logged"]
  sources             = { organization_id = "o-abcdefghij" }
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

  assert {
    condition     = aws_cloudwatch_event_target.signal["high"].input_transformer[0].input_paths["message"] == "$.detail.sns.Message"
    error_message = "the message is read from the SNS envelope keel-signals puts in detail.sns."
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
    error_message = "accounts in the organization may put events."
  }

  assert {
    # Without it any role in the organization could page CRITICAL and write
    # a record the evidence lock keeps.
    condition     = jsonencode(jsondecode(aws_cloudwatch_event_bus_policy.this[0].policy).Statement[0].Condition.ArnLike["aws:PrincipalArn"]) == jsonencode(["arn:*:iam::*:role/*-signal-forward-*"])
    error_message = "only keel-signals' forwarding roles may put events."
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
