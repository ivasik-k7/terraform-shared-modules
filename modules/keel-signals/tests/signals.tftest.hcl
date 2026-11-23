# Plan properties of keel-signals.
#
# What a mock cannot show: Budgets, Anomaly Detection or CloudWatch publishing
# through the topic policy, SNS delivering to the queue, the pipe parsing the
# SQS body to filter on TopicArn, or EventBridge delivering across accounts
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
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/mock" }
  }
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:eu-west-2:111111111111:lending-signals", url = "https://sqs.eu-west-2.amazonaws.com/111111111111/lending-signals" }
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

run "each_severity_has_its_own_pipe_to_the_default_bus" {
  # A pipe can target only the default bus of its own account and Region.
  command = plan

  assert {
    condition     = aws_pipes_pipe.severity["high"].target == "arn:aws:events:eu-west-2:111111111111:event-bus/default"
    error_message = "the pipe puts on this account's default bus."
  }

  assert {
    condition     = aws_pipes_pipe.severity["high"].target_parameters[0].eventbridge_event_bus_parameters[0].source == "keel.high"
    error_message = "the severity travels in the event source."
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
    condition     = length(aws_pipes_pipe.severity) == 0 && length(aws_sqs_queue.signals) == 0 && output.forwarding == null
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
