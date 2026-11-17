# Warnings, not refusals: postures a real configuration may want, but a
# reviewer should see in every plan and HCP Terraform health assessment.
# Each is silent under create = false and once named in acknowledged_checks.

locals {
  ack_hint = "Acknowledge it with acknowledged_checks if this is intended."
}

check "somebody_hears_a_failure" {
  assert {
    condition = !local.create ? true : (contains(local.acknowledged, "somebody_hears_a_failure") ? true : (
      var.sns_topic_arn != "" ? (var.create_event_rules ? true : var.create_alarms) : (var.create_event_rules ? false : (var.create_alarms ? length(local.alarm_actions) > 0 : false))
    ))
    error_message = "Something is not heard: with no sns_topic_arn the event rules (failed launches, failed refreshes) cannot exist, and without alarm_actions neither do alarm notifications; or both are off. A launch that fails on a KMS grant, a quota or a missing subnet leaves the apply green and the group short. ${local.ack_hint}"
  }
}

check "fleet_survives_an_az" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "fleet_survives_an_az") ? true : (local.subnet_count >= 2 ? local.capacity_floor >= 2 : false))
    error_message = "The group can run in one AZ: ${local.subnet_count} subnet(s), and a floor of ${local.capacity_floor} instance(s) (min_size, or a scheduled action's lower one). Losing that AZ, or that instance, is an outage until a replacement launches elsewhere. ${local.ack_hint}"
  }
}

check "spot_fleets_keep_an_on_demand_floor" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "spot_fleets_keep_an_on_demand_floor") ? true : !local.spot_without_floor)
    error_message = "The whole fleet is Spot (on_demand_base_capacity = 0, on_demand_percentage_above_base_capacity = 0). Every instance can be reclaimed at once with two minutes' notice. ${local.ack_hint}"
  }
}

check "volumes_use_a_customer_key" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "volumes_use_a_customer_key") ? true : var.kms_key_arn != "")
    error_message = "Volumes are encrypted with the account's EBS key, not a key you control: access cannot be revoked by key policy. ${local.ack_hint}"
  }
}

check "burstable_credits_are_bounded" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "burstable_credits_are_bounded") ? true : !local.unbounded_credits)
    error_message = "cpu_credits = unlimited on burstable instances: a sustained load is billed per vCPU-hour of surplus credits ($0.05 on Linux in eu-west-2), with no ceiling, per instance. ${local.ack_hint}"
  }
}

check "instances_are_reached_without_ssh_keys" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "instances_are_reached_without_ssh_keys") ? true : var.key_name == "")
    error_message = "key_name is set: anyone holding the private key, and able to reach port 22, has a shell on every instance, and the session is not recorded. Session Manager needs no key. ${local.ack_hint}"
  }
}

check "instances_have_no_public_ip" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "instances_have_no_public_ip") ? true : var.public_ip != "assign")
    error_message = "public_ip = assign: every instance gets a public IPv4 ($0.005 per hour), and in a public subnet every port the security groups open is on the internet. ${local.ack_hint}"
  }
}

check "launch_template_changes_reach_the_fleet" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "launch_template_changes_reach_the_fleet") ? true : local.refresh_enabled)
    error_message = "instance_refresh is off: a new AMI or user data reaches only instances launched afterwards, so the fleet runs mixed versions until scale-in or failures replace the old ones. ${local.ack_hint}"
  }
}

check "containers_cannot_reach_instance_credentials" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "containers_cannot_reach_instance_credentials") ? true : !local.imds_reachable_by_tasks)
    error_message = "metadata_hop_limit = ${var.metadata_hop_limit}: containers on the host can reach the instance metadata service, and with it the instance role's credentials. ${local.ack_hint}"
  }
}

check "retained_instances_are_cleaned_up" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "retained_instances_are_cleaned_up") ? true : var.terminate_hook_abandon != "retain")
    error_message = "terminate_hook_abandon = retain: every instance whose drain fails stays, billing, beside its replacement, until someone terminates it (verify_commands.terminate_retained). Nothing in the group bounds how many accumulate. ${local.ack_hint}"
  }
}

check "ami_is_pinned" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "ami_is_pinned") ? true : !local.ami_moves_on_its_own)
    error_message = "The AMI comes from ${var.ami_ssm_parameter}, read at every plan: when AWS publishes a new image, an unrelated apply moves the launch template${local.refresh_enabled ? " and replaces the whole fleet" : ""}. Pin ami to take images deliberately. ${local.ack_hint}"
  }
}
