# Warnings, not refusals: postures a real configuration may want, but a
# reviewer should see in every plan and HCP Terraform health assessment.
# Each is silent under create = false and once named in acknowledged_checks.

locals {
  acknowledged = toset(var.acknowledged_checks)
  ack_hint     = "Acknowledge it with acknowledged_checks if this is intended."

  shared_privileged_pools = sort([for k, p in local.active_pools : k if p.privileged ? (p.capacity_per_instance != 1 || p.max_use_count != 1) : false])
  aws_pools               = sort([for k, p in local.active_pools : k if p.jobs_use_aws])
}

check "privileged_jobs_get_their_own_instance" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "privileged_jobs_get_their_own_instance") ? true : length(local.shared_privileged_pools) == 0)
    error_message = "Privileged pools whose instances run more than one job, side by side or one after another: ${join(", ", local.shared_privileged_pools)}. A privileged container is root on the instance, so one job can read or change another's source, secrets and caches. capacity_per_instance = 1 and max_use_count = 1 give each job a fresh instance. ${local.ack_hint}"
  }
}

check "jobs_hold_aws_credentials" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "jobs_hold_aws_credentials") ? true : length(local.aws_pools) == 0)
    error_message = "Every job on ${join(", ", local.aws_pools)} can use the pool's AWS access (aws_access), whatever branch or fork it comes from. Make each of these runners protected in GitLab, so only protected branches and tags run on it, then acknowledge this check. ${local.ack_hint}"
  }
}
