data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_vpc" "selected" { id = var.vpc_id }

data "aws_ami" "bastion" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = var.ami_owners

  dynamic "filter" {
    for_each = var.ami_filters
    content {
      name   = filter.key
      values = filter.value
    }
  }
}

locals {
  name_prefix = "${var.name}-${var.environment}"
  ami_id      = var.ami_id != null ? var.ami_id : data.aws_ami.bastion[0].id

  common_tags = merge(
    {
      Name        = local.name_prefix
      Module      = "bastion"
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )

  cloudwatch_log_group_name = var.cloudwatch_log_group_name != null ? var.cloudwatch_log_group_name : "/bastion/${local.name_prefix}"

  create_iam_resources = var.iam_instance_profile_arn == null
}

resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-bastion"
  description = "Security group for ${local.name_prefix} bastion host"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-bastion" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh_cidr" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.bastion.id
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  description       = "SSH from ${each.value}"

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "ssh_ipv6" {
  for_each = toset(var.allowed_ipv6_cidr_blocks)

  security_group_id = aws_security_group.bastion.id
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  ip_protocol       = "tcp"
  cidr_ipv6         = each.value
  description       = "SSH from ${each.value} (IPv6)"

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "ssh_sg" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.bastion.id
  from_port                    = var.ssh_port
  to_port                      = var.ssh_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value
  description                  = "SSH from SG ${each.value}"

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  for_each = toset(var.egress_cidr_blocks)

  security_group_id = aws_security_group.bastion.id
  ip_protocol       = "-1"
  cidr_ipv4         = each.value
  description       = "Allow all outbound IPv4"

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  for_each = toset(var.egress_ipv6_cidr_blocks)

  security_group_id = aws_security_group.bastion.id
  ip_protocol       = "-1"
  cidr_ipv6         = each.value
  description       = "Allow all outbound IPv6"

  tags = local.common_tags
}

data "aws_iam_policy_document" "assume_role" {
  count = local.create_iam_resources ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  count = local.create_iam_resources ? 1 : 0

  name                 = "${local.name_prefix}-bastion-role"
  assume_role_policy   = data.aws_iam_policy_document.assume_role[0].json
  permissions_boundary = var.iam_role_permissions_boundary

  tags = merge(local.common_tags, var.iam_role_tags, { Name = "${local.name_prefix}-bastion-role" })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = local.create_iam_resources && var.ssm_enabled ? 1 : 0

  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  count = local.create_iam_resources && var.cloudwatch_logs_enabled ? 1 : 0

  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "extra" {
  for_each = local.create_iam_resources ? {
    for idx, arn in var.iam_extra_policy_arns : tostring(idx) => arn
  } : {}

  role       = aws_iam_role.bastion[0].name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "bastion" {
  count = local.create_iam_resources ? 1 : 0

  name = "${local.name_prefix}-bastion-profile"
  role = aws_iam_role.bastion[0].name

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-bastion-profile" })
}

locals {
  instance_profile_arn = var.iam_instance_profile_arn != null ? var.iam_instance_profile_arn : aws_iam_instance_profile.bastion[0].arn
}

# ============================================================
# CLOUDWATCH LOG GROUP
# ============================================================

resource "aws_cloudwatch_log_group" "bastion" {
  count = var.cloudwatch_logs_enabled ? 1 : 0

  name              = local.cloudwatch_log_group_name
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.cloudwatch_log_group_kms_key_id

  tags = merge(local.common_tags, { Name = local.cloudwatch_log_group_name })
}

# ============================================================
# USER DATA
# ============================================================

locals {
  default_user_data = <<-USERDATA
    #!/usr/bin/env bash
    set -euo pipefail

    ### ── Package updates ──────────────────────────────────────────
    dnf update -y --security

    ### ── SSH authorised keys ──────────────────────────────────────
    %{for key in var.ssh_authorized_keys~}
    echo "${key}" >> /home/ec2-user/.ssh/authorized_keys
    %{endfor~}
    chmod 600 /home/ec2-user/.ssh/authorized_keys
    chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys

    %{if var.ssh_hardening_enabled~}
    ### ── SSH hardening ─────────────────────────────────────────────
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/'         /etc/ssh/sshd_config
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/'             /etc/ssh/sshd_config
    sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/'                /etc/ssh/sshd_config
    sed -i 's/^#\?LoginGraceTime.*/LoginGraceTime 30/'           /etc/ssh/sshd_config
    sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
    sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 2/'  /etc/ssh/sshd_config
    systemctl restart sshd
    %{endif~}

    %{if var.ssm_enabled~}
    ### ── AWS SSM Agent ─────────────────────────────────────────────
    dnf install -y amazon-ssm-agent
    systemctl enable --now amazon-ssm-agent
    %{endif~}

    %{if var.cloudwatch_logs_enabled~}
    ### ── CloudWatch Agent ──────────────────────────────────────────
    dnf install -y amazon-cloudwatch-agent
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CW_EOF'
    {
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/secure",
                "log_group_name": "${local.cloudwatch_log_group_name}",
                "log_stream_name": "{instance_id}/secure",
                "retention_in_days": ${var.cloudwatch_log_retention_days}
              },
              {
                "file_path": "/var/log/messages",
                "log_group_name": "${local.cloudwatch_log_group_name}",
                "log_stream_name": "{instance_id}/messages",
                "retention_in_days": ${var.cloudwatch_log_retention_days}
              }
            ]
          }
        }
      }
    }
    CW_EOF
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 \
      -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    %{endif~}

    ### ── Extra commands ────────────────────────────────────────────
    ${var.user_data_extra}
  USERDATA

  user_data_final = var.user_data != null ? var.user_data : local.default_user_data
}

# ============================================================
# LAUNCH TEMPLATE
# ============================================================

resource "aws_launch_template" "bastion" {
  name_prefix   = "${local.name_prefix}-bastion-"
  image_id      = local.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  user_data = base64encode(local.user_data_final)

  iam_instance_profile {
    arn = local.instance_profile_arn
  }

  network_interfaces {
    associate_public_ip_address = var.associate_public_ip
    security_groups = concat(
      [aws_security_group.bastion.id],
      var.additional_security_group_ids
    )
    delete_on_termination = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      iops                  = contains(["gp3", "io1", "io2"], var.root_volume_type) ? var.root_volume_iops : null
      throughput            = var.root_volume_type == "gp3" ? var.root_volume_throughput : null
      encrypted             = var.root_volume_encrypted
      kms_key_id            = var.root_volume_kms_key_id
      delete_on_termination = var.root_volume_delete_on_termination
    }
  }

  metadata_options {
    http_tokens                 = var.metadata_http_tokens
    http_endpoint               = "enabled"
    http_put_response_hop_limit = var.metadata_http_put_response_hop_limit
    instance_metadata_tags      = var.metadata_instance_metadata_tags
  }

  monitoring { enabled = true }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${local.name_prefix}-bastion" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "${local.name_prefix}-bastion-root" })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = merge(local.common_tags, { Name = "${local.name_prefix}-bastion-eni" })
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-bastion-lt" })

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================
# AUTO SCALING GROUP
# ============================================================

resource "aws_autoscaling_group" "bastion" {
  name_prefix         = "${local.name_prefix}-bastion-"
  vpc_zone_identifier = var.subnet_ids
  desired_capacity    = var.asg_desired_capacity
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size

  health_check_type         = var.asg_health_check_type
  health_check_grace_period = var.asg_health_check_grace_period

  termination_policies = var.asg_termination_policies

  launch_template {
    id      = aws_launch_template.bastion.id
    version = "$Latest"
  }

  dynamic "instance_refresh" {
    for_each = var.asg_instance_refresh_enabled ? [1] : []
    content {
      strategy = "Rolling"
      preferences {
        min_healthy_percentage = var.asg_instance_refresh_min_healthy_percentage
      }
    }
  }

  dynamic "warm_pool" {
    for_each = var.asg_warm_pool_enabled ? [1] : []
    content {
      min_size                    = var.asg_warm_pool_min_size
      pool_state                  = var.asg_warm_pool_state
      max_group_prepared_capacity = var.asg_max_size
    }
  }

  dynamic "tag" {
    for_each = merge(local.common_tags, { Name = "${local.name_prefix}-bastion" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# ============================================================
# SNS NOTIFICATIONS
# ============================================================

resource "aws_autoscaling_notification" "bastion" {
  count = var.sns_notifications_enabled && var.sns_topic_arn != null ? 1 : 0

  group_names   = [aws_autoscaling_group.bastion.name]
  notifications = var.sns_notification_types
  topic_arn     = var.sns_topic_arn
}

# ============================================================
# SCHEDULED SCALING
# ============================================================

resource "aws_autoscaling_schedule" "scale_up" {
  count = var.schedule_enabled ? 1 : 0

  scheduled_action_name  = "${local.name_prefix}-bastion-scale-up"
  autoscaling_group_name = aws_autoscaling_group.bastion.name
  recurrence             = var.schedule_scale_up_recurrence
  desired_capacity       = var.schedule_scale_up_desired
  min_size               = var.asg_min_size
  max_size               = var.asg_max_size
}

resource "aws_autoscaling_schedule" "scale_down" {
  count = var.schedule_enabled ? 1 : 0

  scheduled_action_name  = "${local.name_prefix}-bastion-scale-down"
  autoscaling_group_name = aws_autoscaling_group.bastion.name
  recurrence             = var.schedule_scale_down_recurrence
  desired_capacity       = var.schedule_scale_down_desired
  min_size               = 0
  max_size               = var.asg_max_size
}

# ============================================================
# ELASTIC IP  (single-instance mode only)
# ============================================================

resource "aws_eip" "bastion" {
  count  = var.eip_enabled && var.asg_desired_capacity == 1 ? 1 : 0
  domain = "vpc"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-bastion-eip" })
}

# EIP association is handled by the SSM association / user-data script below
# because ASGs don't natively support EIP attachment.
resource "aws_ssm_association" "eip_association" {
  count = var.eip_enabled && var.asg_desired_capacity == 1 ? 1 : 0

  name = "AWS-RunShellScript"

  targets {
    key    = "tag:Name"
    values = ["${local.name_prefix}-bastion"]
  }

  parameters = {
    commands = join("\n", [
      "INSTANCE_ID=$(curl -s -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' -X PUT http://169.254.169.254/latest/api/token | xargs -I{} curl -s -H 'X-aws-ec2-metadata-token: {}' http://169.254.169.254/latest/meta-data/instance-id)",
      "aws ec2 associate-address --instance-id $INSTANCE_ID --allocation-id ${aws_eip.bastion[0].id} --region ${data.aws_region.current.name}",
    ])
  }

  depends_on = [aws_autoscaling_group.bastion]
}
