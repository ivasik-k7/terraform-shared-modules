locals {
  create = var.create

  common_tags = merge(var.tags, {
    "ManagedBy" = "Terraform"
    "Module"    = "appconfig"
  })

  # ---- env specialization ----
  # any per_environment override fans the profile out into one generated
  # AppConfig profile per declared environment (instance key "pk:ek", name
  # "pk-ek"). plain profiles stay a single "pk" instance. profiles are free,
  # so the fan-out costs nothing.
  is_specialized = {
    for pk, p in var.profiles :
    pk => p.type == "feature-flags" && anytrue([for fk, f in p.flags : length(f.per_environment) > 0])
  }

  profile_instances = merge(
    { for pk, p in var.profiles : pk => { profile = pk, env = "" } if !local.is_specialized[pk] },
    merge([
      for pk, p in var.profiles : {
        for ek in keys(var.environments) : "${pk}:${ek}" => { profile = pk, env = ek }
      } if local.is_specialized[pk]
    ]...),
  )

  # env-resolved flag state: enabled + attribute values may come from the
  # overlay; constraints never do (one schema, different values).
  # nested ternaries, not &&-chains: terraform < 1.10 evaluates eagerly and
  # would index the map even when contains() said no
  resolved_enabled = {
    for ik, inst in local.profile_instances : ik => {
      for fk, f in var.profiles[inst.profile].flags : fk => (
        inst.env == "" ? f.enabled : (
          !contains(keys(f.per_environment), inst.env) ? f.enabled : (
            f.per_environment[inst.env].enabled != null ? f.per_environment[inst.env].enabled : f.enabled
          )
        )
      )
    } if var.profiles[inst.profile].type == "feature-flags"
  }

  resolved_attr_values = {
    for ik, inst in local.profile_instances : ik => {
      for fk, f in var.profiles[inst.profile].flags : fk => {
        for ak, a in f.attributes : ak => (
          inst.env == "" ? a.value : (
            !contains(keys(f.per_environment), inst.env) ? a.value :
            lookup(f.per_environment[inst.env].attributes, ak, a.value)
          )
        )
      }
    } if var.profiles[inst.profile].type == "feature-flags"
  }

  # ---- feature flags: HCL -> AWS.AppConfig.FeatureFlags json ----
  # attribute values are strings in the variable and cast here by declared
  # type. the per-type sub-maps are deliberate: terraform won't unify
  # mixed-type map values.
  feature_flags_json = {
    for ik, inst in local.profile_instances : ik => jsonencode({
      version = "1"
      flags = {
        for fk, f in var.profiles[inst.profile].flags : fk => merge(
          { name = fk },
          f.description != "" ? { description = f.description } : {},
          length(f.attributes) > 0 ? {
            attributes = {
              for ak, a in f.attributes : ak => {
                constraints = merge(
                  { type = a.type },
                  a.required ? { required = true } : {},
                  length(a.enum) > 0 ? { enum = a.enum } : {},
                  a.pattern != "" ? { pattern = a.pattern } : {},
                  a.minimum != null ? { minimum = a.minimum } : {},
                  a.maximum != null ? { maximum = a.maximum } : {},
                )
              }
            }
          } : {},
        )
      }
      values = {
        for fk, f in var.profiles[inst.profile].flags : fk => merge(
          { enabled = local.resolved_enabled[ik][fk] },
          { for ak, a in f.attributes : ak => local.resolved_attr_values[ik][fk][ak] if a.type == "string" && local.resolved_attr_values[ik][fk][ak] != "" },
          { for ak, a in f.attributes : ak => tonumber(local.resolved_attr_values[ik][fk][ak]) if a.type == "number" && local.resolved_attr_values[ik][fk][ak] != "" },
          { for ak, a in f.attributes : ak => lower(local.resolved_attr_values[ik][fk][ak]) == "true" if a.type == "boolean" && local.resolved_attr_values[ik][fk][ak] != "" },
        )
      }
    }) if var.profiles[inst.profile].type == "feature-flags"
  }

  # rendered flags, or the caller's freeform content (per instance)
  hosted_content = {
    for ik, inst in local.profile_instances :
    ik => var.profiles[inst.profile].type == "feature-flags" ? local.feature_flags_json[ik] : var.profiles[inst.profile].content
    if var.profiles[inst.profile].location_uri == "hosted" && (var.profiles[inst.profile].type == "feature-flags" || var.profiles[inst.profile].content != "")
  }

  hosted_content_type = {
    for ik, inst in local.profile_instances :
    ik => var.profiles[inst.profile].type == "feature-flags" ? "application/json" : var.profiles[inst.profile].content_type
  }

  profile_type_api = {
    for ik, inst in local.profile_instances :
    ik => var.profiles[inst.profile].type == "feature-flags" ? "AWS.AppConfig.FeatureFlags" : "AWS.Freeform"
  }

  # ---- monitors ----
  any_alarms          = anytrue([for k, e in var.environments : length(e.alarm_arns) > 0])
  create_monitor_role = local.create && local.any_alarms && var.monitor_role_arn == ""
  monitor_role_arn    = var.monitor_role_arn != "" ? var.monitor_role_arn : one(aws_iam_role.monitor[*].arn)

  # "" -> module default; AppConfig.* -> preset id used as-is; else a strategy
  # created here
  deployment_strategy_id = {
    for i, d in var.deployments : "${d.environment}:${d.profile}" => (
      d.strategy == "" ? (
        startswith(var.default_deployment_strategy, "AppConfig.")
        ? var.default_deployment_strategy
        : aws_appconfig_deployment_strategy.this[var.default_deployment_strategy].id
      ) :
      startswith(d.strategy, "AppConfig.") ? d.strategy : aws_appconfig_deployment_strategy.this[d.strategy].id
    )
  }

  deployments = { for d in var.deployments : "${d.environment}:${d.profile}" => d }

  # a deployment of a specialized profile lands on its env's generated instance
  deployment_profile_instance = {
    for d in var.deployments : "${d.environment}:${d.profile}" => (
      local.is_specialized[d.profile] ? "${d.profile}:${d.environment}" : d.profile
    )
  }

  # ---- notifications ----
  create_topic = local.create && var.enable_notifications && var.alert_sns_topic_arn == ""
  topic_arn    = var.alert_sns_topic_arn != "" ? var.alert_sns_topic_arn : one(aws_sns_topic.events[*].arn)
}
