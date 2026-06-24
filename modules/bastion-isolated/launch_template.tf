# byo ami - isolated accounts don't run cloud-init so someone bakes the image
# and we just attach it. imdsv2 forced, root encrypted. don't lean on user_data.

resource "aws_launch_template" "this" {
  count = local.create ? 1 : 0

  name_prefix   = "${var.name}-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  ebs_optimized = var.ebs_optimized

  user_data = var.user_data_base64 != null ? var.user_data_base64 : (var.user_data != null ? base64encode(var.user_data) : null)

  dynamic "iam_instance_profile" {
    for_each = local.instance_profile_name != null ? [1] : []
    content {
      name = local.instance_profile_name
    }
  }

  network_interfaces {
    associate_public_ip_address = var.associate_public_ip
    security_groups             = local.security_group_ids
    delete_on_termination       = true
  }

  metadata_options {
    http_endpoint               = var.metadata_options.http_endpoint
    http_tokens                 = var.metadata_options.http_tokens
    http_put_response_hop_limit = var.metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = var.metadata_options.instance_metadata_tags
  }

  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  block_device_mappings {
    device_name = var.root_block_device.device_name
    ebs {
      volume_size           = var.root_block_device.volume_size
      volume_type           = var.root_block_device.volume_type
      iops                  = var.root_block_device.iops
      throughput            = var.root_block_device.throughput
      encrypted             = var.root_block_device.encrypted
      kms_key_id            = var.root_block_device.kms_key_id
      delete_on_termination = var.root_block_device.delete_on_termination
    }
  }

  # extra disks if anyone needs them - rare on a bastion
  dynamic "block_device_mappings" {
    for_each = var.ebs_block_devices
    content {
      device_name = block_device_mappings.value.device_name
      ebs {
        volume_size           = block_device_mappings.value.volume_size
        volume_type           = block_device_mappings.value.volume_type
        iops                  = block_device_mappings.value.iops
        throughput            = block_device_mappings.value.throughput
        encrypted             = block_device_mappings.value.encrypted
        kms_key_id            = block_device_mappings.value.kms_key_id
        snapshot_id           = block_device_mappings.value.snapshot_id
        delete_on_termination = block_device_mappings.value.delete_on_termination
      }
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { "Name" = var.name })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { "Name" = var.name })
  }

  tags = merge(local.common_tags, { "Name" = "${var.name}-bastion" })

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length(local.security_group_ids) > 0
      error_message = "The bastion needs at least one security group: set create_security_group = true or provide security_group_ids."
    }

    # no profile = no ssm = you can't get in. block it unless ssh is the plan.
    precondition {
      condition     = local.instance_profile_name != null || (!var.enable_ssm && !var.create_iam_role)
      error_message = "No instance profile resolved. Set create_iam_role = true or provide iam_instance_profile_name (required for SSM access)."
    }
  }
}
