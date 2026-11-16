# Warnings, not refusals: postures a real configuration may want, but a
# reviewer should see in every plan and HCP Terraform health assessment.
# Each is silent under create = false and once named in acknowledged_checks.

locals {
  ack_hint = "Acknowledge it with acknowledged_checks if this is intended."
}

check "somebody_hears_a_failure" {
  assert {
    condition = !local.create ? true : (contains(local.acknowledged, "somebody_hears_a_failure") ? true : (
      length(local.services) == 0 ? true : (var.sns_topic_arn != "" ? (var.create_event_rules ? true : var.create_alarms) : (var.create_event_rules ? false : (var.create_alarms ? length(local.alarm_actions) > 0 : false)))
    ))
    error_message = "Something is not heard: with no sns_topic_arn the event rules (failed deployments, impaired services, failed jobs) cannot exist, and without alarm_actions neither do alarm notifications; or both create_event_rules and create_alarms are off. A deployment the circuit breaker rolls back, a service whose tasks cannot start and a scheduled job that fails all leave the apply green and tell nobody. ${local.ack_hint}"
  }
}

check "deployments_roll_back" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "deployments_roll_back") ? true : length(local.services_without_rollback) == 0)
    error_message = "Services without circuit-breaker rollback: ${join(", ", local.services_without_rollback)}. A revision whose tasks never become healthy keeps being retried, and without minimum_healthy_percent headroom the old tasks are already gone. ${local.ack_hint}"
  }
}

check "images_are_pinned" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "images_are_pinned") ? true : length(local.unpinned_images) == 0)
    error_message = "Images without a tag or digest, or tagged latest: ${join("; ", local.unpinned_images)}. Every task start (a scale-out, a replaced Spot task) pulls whatever the tag points to then, so two tasks of one revision can run different code. Pin a version tag in a repository with tag immutability, or an @sha256 digest; governance.mutable_tag_images lists every image not pinned by digest. ${local.ack_hint}"
  }
}

check "log_retention_is_bounded" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "log_retention_is_bounded") ? true : length(local.unbounded_log_groups) == 0)
    error_message = "Log groups kept forever (retention 0): ${join(", ", local.unbounded_log_groups)}. Storage is billed every month for everything ever written. ${local.ack_hint}"
  }
}

check "logs_use_a_customer_key" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "logs_use_a_customer_key") ? true : length(local.created_log_groups_without_key) == 0)
    error_message = "Log groups the module creates without a customer key: ${join(", ", local.created_log_groups_without_key)}. They use CloudWatch Logs' own encryption, so access cannot be revoked by key policy. ${local.ack_hint}"
  }
}

check "services_survive_an_az" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "services_survive_an_az") ? true : length(local.single_task_services) == 0)
    error_message = "Services that run fewer than two tasks (desired_count, or autoscaling.min): ${join(", ", local.single_task_services)}. One task is one AZ; losing it, or a Spot interruption, is an outage until a replacement starts. ${local.ack_hint}"
  }
}

check "spot_services_keep_an_on_demand_floor" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "spot_services_keep_an_on_demand_floor") ? true : length(local.spot_without_floor) == 0)
    error_message = "Services on Fargate Spot with no on-demand share: ${join(", ", local.spot_without_floor)}. When Spot has no capacity Fargate does not fall back to on-demand; the service waits with too few tasks. Use capacity = \"balanced\" for a base of one on-demand task. ${local.ack_hint}"
  }
}

check "shell_access_is_intended" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "shell_access_is_intended") ? true : length(local.services_with_shell_access) == 0)
    error_message = "ECS Exec is on for: ${join(", ", local.services_with_shell_access)}. Anyone with ecs:ExecuteCommand on the cluster gets a root shell in those containers. ${local.ack_hint}"
  }
}

check "task_costs_are_attributable" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "task_costs_are_attributable") ? true : length(local.untagged_task_services) == 0)
    error_message = "propagate_tags = NONE on: ${join(", ", local.untagged_task_services)}. Their tasks carry only the ECS managed tags, so they are missing from tag-based cost allocation and SCPs. ${local.ack_hint}"
  }
}

check "running_task_alarms_have_data" {
  assert {
    condition = !local.create ? true : (contains(local.acknowledged, "running_task_alarms_have_data") ? true : (
      var.create_alarms ? (length(local.replica) == 0 ? true : var.container_insights != "disabled") : true
    ))
    error_message = "container_insights is disabled, so RunningTaskCount is not published and no running-task alarm is created. A service whose tasks keep failing to start is only visible in its events. ${local.ack_hint}"
  }
}

check "failed_schedules_are_kept" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "failed_schedules_are_kept") ? true : length(local.schedules_without_dlq) == 0)
    error_message = "Scheduled workloads without a dead_letter_queue_arn: ${join(", ", local.schedules_without_dlq)}. When EventBridge Scheduler cannot start the task (throttling, no capacity, a missing role) and its retries run out, the invocation is dropped with no record. ${local.ack_hint}"
  }
}

check "shell_sessions_are_recorded" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "shell_sessions_are_recorded") ? true : length(local.unrecorded_shell_services) == 0)
    error_message = "ECS Exec is on for ${join(", ", local.unrecorded_shell_services)} with execute_command.logging = NONE: root shells leave no transcript. ${local.ack_hint}"
  }
}

check "containers_stay_on_their_side" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "containers_stay_on_their_side") ? true : length(local.host_access) == 0)
    error_message = "Containers with access to their host: ${join("; ", local.host_access)}. Whoever controls that image controls the instance, its role and the other tasks on it. ${local.ack_hint}"
  }
}

check "roles_are_not_administrators" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "roles_are_not_administrators") ? true : length(local.administrator_roles) == 0)
    error_message = "Workload roles with administrator-level policies: ${join("; ", local.administrator_roles)}. A compromised container would own the account. ${local.ack_hint}"
  }
}

check "secrets_are_not_in_environment" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "secrets_are_not_in_environment") ? true : length(local.secret_looking_environment) == 0)
    error_message = "Environment variables named like secrets: ${join(", ", local.secret_looking_environment)}. Plain environment values are in state, in the plan, and readable by anyone with ecs:DescribeTaskDefinition; use secrets. ${local.ack_hint}"
  }
}
