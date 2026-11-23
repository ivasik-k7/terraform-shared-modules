locals {
  create = var.create

  partition  = coalesce(one(data.aws_partition.current[*].partition), "aws")
  region     = coalesce(one(data.aws_region.current[*].region), "us-east-1")
  account_id = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")

  module_tags = { ManagedBy = "Terraform", Module = "keel-billing" }
  tags        = merge(var.tags, local.module_tags)

  acknowledged = toset(var.acknowledged_checks)

  topic_arns = module.signals.topic_arns

  # Managed monitors: one per dimension, and one per cost category or tag key.
  managed_monitors = merge(
    var.anomaly_detection.services ? { services = { dimension = "SERVICE", specification = null } } : {},
    var.anomaly_detection.linked_accounts ? { accounts = { dimension = "LINKED_ACCOUNT", specification = null } } : {},
    { for c in var.anomaly_detection.cost_categories : "category-${lower(replace(c, " ", "-"))}" => {
      dimension     = "COST_CATEGORY"
      specification = jsonencode({ CostCategories = { Key = c } })
    } },
    { for t in var.anomaly_detection.tags : "tag-${lower(replace(t, "/[^A-Za-z0-9-]/", "-"))}" => {
      dimension     = "TAG"
      specification = jsonencode({ Tags = { Key = t } })
    } },
  )
  active_monitors = local.create ? local.managed_monitors : {}
  alert           = local.create && length(local.managed_monitors) > 0 ? var.anomaly_detection.alert.enabled : false
  active_digests  = local.create && length(local.managed_monitors) > 0 ? var.anomaly_detection.digests : {}

  # Commitment targets as keel-limits commitment limits; RI keys carry the
  # service as a slug.
  slug = { for svc in distinct(concat(keys(var.commitments.ri_utilization), keys(var.commitments.ri_coverage))) :
    svc => trim(substr(lower(replace(svc, "/[^A-Za-z0-9]+/", "-")), 0, 26), "-")
  }
  commitment_limits = merge(
    var.commitments.savings_plans_utilization == 0 ? {} : { sp-utilization = { type = "SAVINGS_PLANS_UTILIZATION", target_percent = var.commitments.savings_plans_utilization, owners = var.commitments.owners, scope = {} } },
    var.commitments.savings_plans_coverage == 0 ? {} : { sp-coverage = { type = "SAVINGS_PLANS_COVERAGE", target_percent = var.commitments.savings_plans_coverage, owners = var.commitments.owners, scope = {} } },
    { for svc, p in var.commitments.ri_utilization : "ri-utilization-${local.slug[svc]}" => { type = "RI_UTILIZATION", target_percent = p, owners = var.commitments.owners, scope = { services = [svc] } } if p > 0 },
    { for svc, p in var.commitments.ri_coverage : "ri-coverage-${local.slug[svc]}" => { type = "RI_COVERAGE", target_percent = p, owners = var.commitments.owners, scope = { services = [svc] } } if p > 0 },
  )
  limits       = { for k, l in merge(var.limits, local.commitment_limits) : k => l if local.create }
  limit_checks = ["production_changes_only_by_people", "every_limit_has_an_owner"]

  spend_limit_keys = sort([for k, l in local.limits : k if contains(["COST", "USAGE"], try(l.type, "COST"))])

  cost_category_names = keys(var.cost_categories)
  watched_categories  = toset(var.anomaly_detection.cost_categories)
  unwatched_categories = sort([
    for c in local.cost_category_names : c if !contains(local.watched_categories, c)
  ])

  forward_anomalies = local.alert ? var.signals.control_plane_bus_arn != "" : false
}
