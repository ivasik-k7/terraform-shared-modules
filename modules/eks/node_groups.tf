################################################################################
# EKS Managed Node Groups
################################################################################

resource "aws_eks_node_group" "this" {
  for_each = local.node_groups_config

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = each.value.subnet_ids

  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  ami_type       = each.value.ami_type
  capacity_type  = each.value.capacity_type
  disk_size      = each.value.use_custom_launch_template ? null : each.value.disk_size
  instance_types = each.value.instance_types

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints

    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  dynamic "update_config" {
    for_each = each.value.update_config != null ? [each.value.update_config] : []

    content {
      max_unavailable_percentage = update_config.value.max_unavailable_percentage
      max_unavailable            = update_config.value.max_unavailable
    }
  }

  dynamic "launch_template" {
    for_each = each.value.use_custom_launch_template ? [1] : []

    content {
      id      = aws_launch_template.node_group[each.key].id
      version = aws_launch_template.node_group[each.key].latest_version
    }
  }

  tags = each.value.tags

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      scaling_config[0].desired_size,
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
  ]
}

################################################################################
# Launch Templates for Custom Node Groups
################################################################################

resource "aws_launch_template" "node_group" {
  for_each = {
    for k, v in local.node_groups_config : k => v
    if v.use_custom_launch_template
  }

  name_prefix = "${var.cluster_name}-${each.key}-"
  description = "Launch template for ${var.cluster_name} ${each.key} node group"

  dynamic "block_device_mappings" {
    for_each = each.value.block_device_mappings != null ? [each.value.block_device_mappings] : [local.encrypted_block_device_mappings[0]]

    content {
      device_name = block_device_mappings.value.device_name

      ebs {
        volume_size           = coalesce(each.value.disk_size, 50)
        volume_type           = coalesce(each.value.disk_type, "gp3")
        iops                  = each.value.disk_iops
        throughput            = each.value.disk_throughput
        encrypted             = lookup(block_device_mappings.value.ebs, "encrypted", true)
        kms_key_id            = lookup(block_device_mappings.value.ebs, "kms_key_id", null)
        delete_on_termination = lookup(block_device_mappings.value.ebs, "delete_on_termination", true)
      }
    }
  }

  metadata_options {
    http_endpoint               = each.value.metadata_options != null ? each.value.metadata_options.http_endpoint : local.metadata_options_imdsv2.http_endpoint
    http_tokens                 = each.value.metadata_options != null ? each.value.metadata_options.http_tokens : local.metadata_options_imdsv2.http_tokens
    http_put_response_hop_limit = each.value.metadata_options != null ? each.value.metadata_options.http_put_response_hop_limit : local.metadata_options_imdsv2.http_put_response_hop_limit
    instance_metadata_tags      = each.value.metadata_options != null ? each.value.metadata_options.instance_metadata_tags : local.metadata_options_imdsv2.instance_metadata_tags
  }

  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = var.create_node_security_group ? [aws_security_group.node[0].id] : []
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      each.value.tags,
      {
        Name = "${var.cluster_name}-${each.key}"
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      each.value.tags,
      {
        Name = "${var.cluster_name}-${each.key}"
      }
    )
  }

  user_data = base64encode(templatefile("${path.module}/templates/userdata.sh.tpl", {
    cluster_name         = aws_eks_cluster.this.name
    cluster_endpoint     = aws_eks_cluster.this.endpoint
    cluster_ca           = aws_eks_cluster.this.certificate_authority[0].data
    bootstrap_extra_args = ""
  }))

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-${each.key}-lt"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Fargate Profiles
################################################################################

resource "aws_eks_fargate_profile" "this" {
  for_each = local.fargate_profiles_config

  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = each.key
  pod_execution_role_arn = aws_iam_role.fargate_profile[0].arn
  subnet_ids             = each.value.subnet_ids

  dynamic "selector" {
    for_each = each.value.selectors

    content {
      namespace = selector.value.namespace
      labels    = selector.value.labels
    }
  }

  tags = each.value.tags

  depends_on = [
    aws_iam_role_policy_attachment.fargate_profile,
  ]
}
