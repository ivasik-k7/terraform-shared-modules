locals {
  create                = var.create
  create_iam_role       = local.create && var.create_iam_role && var.iam_instance_profile_name == null
  create_security_group = local.create && var.create_security_group

  instance_profile_name = local.create_iam_role ? aws_iam_instance_profile.this[0].name : var.iam_instance_profile_name

  security_group_ids = compact(concat(
    local.create_security_group ? [aws_security_group.this[0].id] : [],
    var.security_group_ids,
  ))

  use_mixed_instances = length(var.instance_types) > 0 || var.spot_enabled
  override_types      = length(var.instance_types) > 0 ? var.instance_types : [var.instance_type]

  # caller passes map-migrated=<server-id> in tags so MAP credits actually land
  common_tags = merge(
    var.tags,
    {
      "Module"    = "bastion-isolated"
      "ManagedBy" = "Terraform"
    },
  )

  # ssh_* helpers -> one ingress map. nobody wants to write rule objects by hand
  ssh_cidr_rules = {
    for i, c in var.ssh_allowed_cidr_blocks : "ssh-cidr-${i}" => {
      from_port      = var.ssh_port, to_port = var.ssh_port, ip_protocol = "tcp",
      cidr_ipv4      = c, cidr_ipv6 = null, referenced_security_group_id = null,
      prefix_list_id = null, description = "SSH from ${c}"
    }
  }
  ssh_ipv6_rules = {
    for i, c in var.ssh_allowed_ipv6_cidr_blocks : "ssh-ipv6-${i}" => {
      from_port      = var.ssh_port, to_port = var.ssh_port, ip_protocol = "tcp",
      cidr_ipv4      = null, cidr_ipv6 = c, referenced_security_group_id = null,
      prefix_list_id = null, description = "SSH from ${c}"
    }
  }
  ssh_sg_rules = {
    for i, s in var.ssh_allowed_security_group_ids : "ssh-sg-${i}" => {
      from_port      = var.ssh_port, to_port = var.ssh_port, ip_protocol = "tcp",
      cidr_ipv4      = null, cidr_ipv6 = null, referenced_security_group_id = s,
      prefix_list_id = null, description = "SSH from security group ${s}"
    }
  }
  ssh_prefix_rules = {
    for i, p in var.ssh_allowed_prefix_list_ids : "ssh-pl-${i}" => {
      from_port      = var.ssh_port, to_port = var.ssh_port, ip_protocol = "tcp",
      cidr_ipv4      = null, cidr_ipv6 = null, referenced_security_group_id = null,
      prefix_list_id = p, description = "SSH from prefix list ${p}"
    }
  }
  ingress_rules = merge(
    var.security_group_ingress_rules,
    local.ssh_cidr_rules,
    local.ssh_ipv6_rules,
    local.ssh_sg_rules,
    local.ssh_prefix_rules,
  )

  # auto_shutdown = the finops win (scale to 0 after hours). merge w/ custom
  auto_shutdown_schedules = var.auto_shutdown != null && var.auto_shutdown.enabled ? {
    "${var.name}-scale-down" = {
      recurrence       = var.auto_shutdown.scale_down_recurrence
      start_time       = null
      end_time         = null
      time_zone        = var.auto_shutdown.time_zone
      min_size         = var.auto_shutdown.off_min_size
      max_size         = var.auto_shutdown.off_max_size
      desired_capacity = var.auto_shutdown.off_desired_capacity
    }
    "${var.name}-scale-up" = {
      recurrence       = var.auto_shutdown.scale_up_recurrence
      start_time       = null
      end_time         = null
      time_zone        = var.auto_shutdown.time_zone
      min_size         = var.min_size
      max_size         = var.max_size
      desired_capacity = var.desired_capacity
    }
  } : {}

  scheduled_actions = merge(var.scheduled_actions, local.auto_shutdown_schedules)
}
