locals {
  create = var.create

  partition = coalesce(one(data.aws_partition.current[*].partition), "aws")

  module_tags = { ManagedBy = "Terraform", Module = "keel-guardrails" }
  tags        = merge(var.tags, local.module_tags)

  acknowledged = toset(var.acknowledged_checks)

  # Tag policy syntax: tag_key, tag_value, enforced_for, report_required_tag_for.
  # https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_example-tag-policies.html
  tag_policy = jsonencode({
    tags = { for k, t in var.required_tags : lower(k) => merge(
      { tag_key = { "@@assign" = k } },
      length(t.values) > 0 ? { tag_value = { "@@assign" = t.values } } : {},
      length(t.enforce_for) > 0 ? { enforced_for = { "@@assign" = t.enforce_for } } : {},
      length(t.report_for) > 0 ? { report_required_tag_for = { "@@assign" = t.report_for } } : {},
    ) }
  })

  untagged_exemption = length(var.deny_untagged.exempt_principals) == 0 ? {} : {
    ArnNotLike = { "aws:PrincipalArn" = var.deny_untagged.exempt_principals }
  }
  # One statement per tag and resource pattern, with the actions that create
  # that resource: a statement joins every action to every resource it lists.
  untagged_resources = sort(distinct(values(var.deny_untagged.actions)))
  deny_untagged_policy = jsonencode({
    Version = "2012-10-17"
    Statement = flatten([for t in var.deny_untagged.tags : [for i, r in local.untagged_resources : {
      Sid       = "RequireTag${replace(title(replace(t, "/[^A-Za-z0-9]/", " ")), " ", "")}${i}"
      Effect    = "Deny"
      Action    = sort([for a, res in var.deny_untagged.actions : a if res == r])
      Resource  = r
      Condition = merge({ Null = { "aws:RequestTag/${t}" = "true" } }, local.untagged_exemption)
    }]])
  })

  model_exemption = length(var.bedrock_models.exempt_principals) == 0 ? {} : {
    ArnNotLike = { "aws:PrincipalArn" = var.bedrock_models.exempt_principals }
  }
  model_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [merge(
      {
        Sid    = "ApprovedModelsOnly"
        Effect = "Deny"
        Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        # Profiles pass through; the model each one routes to is checked too.
        NotResource = concat(
          flatten([for r in var.bedrock_models.allowed_regions : [
            for m in var.bedrock_models.allowed_models : "arn:${local.partition}:bedrock:${r}::foundation-model/${m}"
          ]]),
          ["arn:${local.partition}:bedrock:*:*:inference-profile/*", "arn:${local.partition}:bedrock:*:*:application-inference-profile/*"],
        )
      },
      length(local.model_exemption) > 0 ? { Condition = local.model_exemption } : {},
    )]
  })

  # https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_ai-opt-out_syntax.html
  ai_opt_out_policy = jsonencode({
    services = { for s in var.ai_services_opt_out.services : s => { opt_out_policy = { "@@assign" = "optOut" } } }
  })

  # SCP 10,240 characters, tag policy 10,000, AI opt-out policy 2,500.
  # https://docs.aws.amazon.com/organizations/latest/userguide/orgs_reference_limits.html
  policies = merge(
    length(var.required_tags) > 0 ? { tags = { type = "TAG_POLICY", content = local.tag_policy, limit = 10000, description = "Keel mandatory tags" } } : {},
    var.deny_untagged.enabled ? { untagged = { type = "SERVICE_CONTROL_POLICY", content = local.deny_untagged_policy, limit = 10240, description = "Keel: no resource without its mandatory tags" } } : {},
    var.bedrock_models.enabled ? { models = { type = "SERVICE_CONTROL_POLICY", content = local.model_policy, limit = 10240, description = "Keel: approved Bedrock models only" } } : {},
    var.ai_services_opt_out.enabled ? { ai-opt-out = { type = "AISERVICES_OPT_OUT_POLICY", content = local.ai_opt_out_policy, limit = 2500, description = "Keel: AI services do not keep or learn from the organization's content" } } : {},
  )
  active_policies = local.create ? local.policies : {}

  attachments = { for pair in setproduct(keys(local.active_policies), var.targets) : "${pair[0]}/${pair[1]}" => { policy = pair[0], target = pair[1] } }
}

resource "aws_organizations_policy" "this" {
  for_each = local.active_policies

  name        = "${var.name}-${each.key}"
  description = each.value.description
  type        = each.value.type
  content     = each.value.content
  tags        = local.tags

  lifecycle {
    precondition {
      condition     = length(each.value.content) <= each.value.limit
      error_message = "The ${each.key} policy is ${length(each.value.content)} characters; AWS Organizations accepts at most ${each.value.limit} for this type. Fewer tags, actions or models."
    }
  }
}

resource "aws_organizations_policy_attachment" "this" {
  for_each = local.attachments

  policy_id = aws_organizations_policy.this[each.value.policy].id
  target_id = each.value.target
}
