# Plan properties of keel-signals.
#
# What a mock cannot show: Budgets, Anomaly Detection or CloudWatch publishing
# through the topic policy, SNS delivering to the queues, the pipe parsing the
# SQS body for its input template, or EventBridge delivering across accounts
# and Regions.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_resource "aws_sns_topic" {
    override_during = plan
    defaults        = { arn = "arn:aws:sns:eu-west-2:111111111111:lending-mock" }
  }
  mock_resource "aws_iam_role" {
    override_during = plan
    defaults        = { arn = "arn:aws:iam::111111111111:role/mock" }
  }
  mock_resource "aws_sqs_queue" {
    override_during = plan
    defaults        = { arn = "arn:aws:sqs:eu-west-2:111111111111:lending-signals", url = "https://sqs.eu-west-2.amazonaws.com/111111111111/lending-signals" }
  }
}

variables {
  name                  = "lending"
  emails                = { high = ["leads@example.com"] }
  control_plane_bus_arn = "arn:aws:events:eu-west-2:333333333333:event-bus/keel"
  forward               = { alarm_name_prefixes = ["lending-"], anomalies = true }
}

run "four_severity_topics_open_to_the_cost_services_of_this_account" {
  command = plan

  assert {
    condition     = length(aws_sns_topic.severity) == 4 ? aws_sns_topic.severity["critical"].tags["Severity"] == "CRITICAL" : false
    error_message = "a topic per severity, tagged with it."
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.severity["high"].policy).Statement[1].Condition.ArnLike["aws:SourceArn"] == "arn:aws:budgets::111111111111:*"
    error_message = "Budgets may publish only for this account's budgets."
  }
}

run "each_severity_has_its_own_queue_and_an_unfiltered_pipe" {
  # A pipe deletes the SQS messages its filter does not match, so pipes
  # sharing a queue lose each other's signals.
  command = plan

  assert {
    condition     = length(aws_sqs_queue.signals) == 4 ? aws_pipes_pipe.severity["high"].source == aws_sqs_queue.signals["high"].arn : false
    error_message = "a queue per severity, and the HIGH pipe reads the HIGH queue."
  }

  assert {
    condition     = alltrue([for p in aws_pipes_pipe.severity : length(p.source_parameters[0].filter_criteria) == 0])
    error_message = "no pipe filters, so no pipe deletes a signal it does not carry."
  }

  assert {
    condition     = aws_sns_topic_subscription.to_queue["critical"].endpoint == aws_sqs_queue.signals["critical"].arn
    error_message = "each topic delivers to its own queue."
  }
}

run "the_pipe_puts_the_envelope_on_the_default_bus_with_its_severity" {
  # A pipe can target only the default bus of its own account and Region.
  command = plan

  assert {
    condition     = aws_pipes_pipe.severity["high"].target == "arn:aws:events:eu-west-2:111111111111:event-bus/default"
    error_message = "the pipe puts on this account's default bus."
  }

  assert {
    condition     = aws_pipes_pipe.severity["high"].target_parameters[0].eventbridge_event_bus_parameters[0].source == "keel.high" ? strcontains(aws_pipes_pipe.severity["high"].target_parameters[0].input_template, "<$.body>") : false
    error_message = "the severity travels in the source and the SNS envelope in the detail."
  }
}

run "a_signal_that_cannot_leave_raises_an_alarm" {
  command = plan

  assert {
    condition     = jsondecode(aws_sqs_queue.signals["warning"].redrive_policy).maxReceiveCount == 5
    error_message = "a message the pipe fails five times is parked in the dead-letter queue."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.undelivered) == 1 ? length(aws_cloudwatch_metric_alarm.stalled) == 1 : false
    error_message = "parked and stalled signals each have an alarm."
  }
}

run "the_forwarding_rule_takes_only_this_instances_signals" {
  # Without resources, every instance in the account and Region would forward
  # every other instance's signals too.
  command = plan

  assert {
    condition     = length(jsondecode(aws_cloudwatch_event_rule.forward["signals"].event_pattern).resources) == 4
    error_message = "the rule matches the events whose resources are this instance's queues."
  }

  assert {
    condition     = jsonencode(jsondecode(aws_cloudwatch_event_rule.forward["alarms"].event_pattern).detail.state.value) == jsonencode(["ALARM"])
    error_message = "alarms are forwarded when they enter ALARM, not on every state change."
  }
}

run "the_customer_key_contract_covers_the_pipes_role" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-2:111111111111:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = length([for r in output.kms_key_policy_requirements : r if length(r.principals.arns) > 0]) == 1
    error_message = "the pipes' role is named in the key policy contract."
  }
}

run "the_default_bus_forwards_signals_alarms_and_anomalies" {
  command = plan

  assert {
    condition     = jsonencode(output.forwarding.rules) == jsonencode(["alarms", "anomalies", "signals"])
    error_message = "the three forwarding rules exist."
  }

  assert {
    condition     = aws_cloudwatch_event_target.forward["signals"].arn == "arn:aws:events:eu-west-2:333333333333:event-bus/keel"
    error_message = "the rules target the control plane bus."
  }
}

run "without_a_bus_signals_stay_in_the_account" {
  command = plan

  variables {
    control_plane_bus_arn = ""
  }

  assert {
    condition     = length(aws_pipes_pipe.severity) == 0 ? (length(aws_sqs_queue.signals) == 0 ? output.forwarding == null : false) : false
    error_message = "no queue, pipes or rules without a control plane."
  }
}

run "an_email_on_an_unknown_severity_is_rejected" {
  command = plan

  variables {
    emails = { urgent = ["x@example.com"] }
  }

  expect_failures = [var.emails]
}

run "create_false_plans_nothing" {
  command = plan

  variables {
    create = false
  }

  assert {
    condition     = length(aws_sns_topic.severity) == 0 && length(aws_pipes_pipe.severity) == 0 && length(output.topic_arns) == 0 && output.forwarding == null && output.verify_commands == null
    error_message = "create = false creates nothing and leaves the outputs empty."
  }
}
