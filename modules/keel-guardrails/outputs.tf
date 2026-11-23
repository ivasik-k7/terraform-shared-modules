output "policy_ids" {
  description = "Organization policy IDs, by role: tags, untagged, models, ai-opt-out."
  value       = { for k, p in aws_organizations_policy.this : k => p.id }
}

output "provider_setting" {
  description = "What the teams' AWS provider sets so a plan fails on a resource missing a required tag (the tag policy's report_for): tag_policy_compliance = \"error\". Null without required_tags."
  value       = !local.create || length(var.required_tags) == 0 ? null : { tag_policy_compliance = "error" }
}

output "controls" {
  description = "The Keel controls this module implements, as register entries."
  value = !local.create ? null : merge(
    length(var.required_tags) == 0 && !var.deny_untagged.enabled ? {} : {
      "FC-02" = {
        statement      = "Resources missing mandatory tags are denied"
        type           = "Prevent"
        threshold      = "${length(var.required_tags)} required keys${var.deny_untagged.enabled ? "; creation refused without ${join(", ", var.deny_untagged.tags)}" : ""}"
        evidence       = "Tag policy and SCP (this configuration); AWS Organizations tag compliance reports; CloudTrail AccessDenied"
        implemented_by = sort([for k, p in aws_organizations_policy.this : p.name if contains(["tags", "untagged"], k)])
      }
    },
    !var.bedrock_models.enabled ? {} : {
      "AI-MODELS" = {
        statement      = "Only approved models are called, in approved Regions"
        type           = "Prevent"
        threshold      = "${join(", ", var.bedrock_models.allowed_models)} in ${join(", ", var.bedrock_models.allowed_regions)}"
        evidence       = "The SCP (this configuration); CloudTrail AccessDenied on bedrock:InvokeModel"
        implemented_by = [for k, p in aws_organizations_policy.this : p.name if k == "models"]
      }
    },
    !var.ai_services_opt_out.enabled ? {} : {
      "AI-OPT-OUT" = {
        statement      = "AWS AI services do not keep or learn from the organization's content"
        type           = "Prevent"
        threshold      = "Opted out: ${join(", ", var.ai_services_opt_out.services)}"
        evidence       = "The AI services opt-out policy (this configuration); describe-effective-policy per account"
        implemented_by = [for k, p in aws_organizations_policy.this : p.name if k == "ai-opt-out"]
      }
    },
  )
}

output "deployer_requirements" {
  description = "IAM the identity running Terraform needs in the management account (or a delegated administrator for policies)."
  value = !local.create ? null : {
    actions = [
      "organizations:CreatePolicy", "organizations:UpdatePolicy", "organizations:DeletePolicy", "organizations:DescribePolicy",
      "organizations:AttachPolicy", "organizations:DetachPolicy", "organizations:ListTargetsForPolicy", "organizations:TagResource",
    ]
    prerequisite = "The TAG_POLICY, SERVICE_CONTROL_POLICY and (with ai_services_opt_out) AISERVICES_OPT_OUT_POLICY policy types enabled on the organization root."
  }
}

output "governance" {
  description = "The guardrails' posture as data."
  value = !local.create ? null : {
    targets                = sort(var.targets)
    required_tags          = { for k, t in var.required_tags : k => { values = t.values, report_for = t.report_for, enforce_for = t.enforce_for } }
    deny_untagged          = var.deny_untagged.enabled ? { tags = var.deny_untagged.tags, actions = sort(keys(var.deny_untagged.actions)), exempt = var.deny_untagged.exempt_principals } : null
    bedrock_models         = var.bedrock_models.enabled ? { models = var.bedrock_models.allowed_models, regions = var.bedrock_models.allowed_regions, exempt = var.bedrock_models.exempt_principals } : null
    ai_services_opt_out    = var.ai_services_opt_out.enabled ? sort(var.ai_services_opt_out.services) : null
    policy_sizes           = { for k, p in local.active_policies : k => "${length(p.content)} of ${p.limit}" }
    scps_without_exemption = local.scps_without_exemption
    acknowledged_checks    = sort(var.acknowledged_checks)
  }
}

output "verify_commands" {
  description = "Read-only commands to run from CloudShell in the management account."
  value = !local.create ? null : {
    policies       = "aws organizations list-policies --filter SERVICE_CONTROL_POLICY --query \"Policies[?starts_with(Name, '${var.name}-')].[Name,Id]\" --output table"
    effective_tags = "aws organizations describe-effective-policy --policy-type TAG_POLICY --target-id <account id>"
    effective_ai   = "aws organizations describe-effective-policy --policy-type AISERVICES_OPT_OUT_POLICY --target-id <account id>"
    tag_compliance = "aws resourcegroupstaggingapi get-compliance-summary --region <region>"
  }
}
