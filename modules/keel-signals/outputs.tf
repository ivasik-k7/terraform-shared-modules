output "topic_arns" {
  description = "The severity topics, by severity (info, warning, high, critical): give them to keel-limits, and point alarms and anomaly alerts at them."
  value       = { for s, t in aws_sns_topic.severity : s => t.arn }
}

output "forwarding" {
  description = "What reaches the control plane from this account and Region: { bus, rules }. Null when no bus is set."
  value       = !local.forward ? null : { bus = var.control_plane_bus_arn, rules = sort(keys(local.forward_rules)), region = local.region }
}

output "kms_key_policy_requirements" {
  description = "What the customer managed key must allow, in contract version 2: the services publishing to the encrypted topics, and the pipes reading the encrypted queue."
  value = !local.create || var.kms_key_arn == "" ? null : concat(
    [for svc in ["budgets.amazonaws.com", "costalerts.amazonaws.com", "cloudwatch.amazonaws.com"] : {
      key        = var.kms_key_arn
      sid        = "${replace(title(replace(var.name, "-", " ")), " ", "")}${replace(title(split(".", svc)[0]), "-", "")}ToSignals"
      principals = { services = [svc], arns = [], roles = [] }
      actions    = ["kms:GenerateDataKey*", "kms:Decrypt"]
      conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] }]
      purpose    = "${split(".", svc)[0]} publishes to ${var.name}'s encrypted severity topics."
    }],
    !local.forward ? [] : [
      {
        key        = var.kms_key_arn
        sid        = "${replace(title(replace(var.name, "-", " ")), " ", "")}SnsToSignalQueue"
        principals = { services = ["sns.amazonaws.com"], arns = [], roles = [] }
        actions    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] }]
        purpose    = "The severity topics deliver to the encrypted signal queue."
      },
    ],
  )
}

output "verify_commands" {
  description = "Commands to run from CloudShell in this account and Region: publish a test signal and watch it leave."
  value = !local.create ? null : {
    test_warning = "aws sns publish --region ${local.region} --topic-arn ${one([for s, t in aws_sns_topic.severity : t.arn if s == "warning"])} --subject 'Keel test' --message 'A test signal from ${var.name}'"
    pipes        = "aws pipes list-pipes --region ${local.region} --name-prefix ${var.name}- --query 'Pipes[].[Name,CurrentState]' --output table"
    queue_depth  = local.forward ? "aws sqs get-queue-attributes --region ${local.region} --queue-url ${aws_sqs_queue.signals[0].url} --attribute-names ApproximateNumberOfMessages" : null
  }
}
