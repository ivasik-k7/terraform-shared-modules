locals {
  cluster_name = var.cluster_name

  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Cluster     = var.cluster_name
    }
  )

  cluster_tags = merge(
    local.common_tags,
    var.cluster_tags,
    {
      Name = var.cluster_name
    }
  )

  # Subnet configuration
  control_plane_subnet_ids = length(var.control_plane_subnet_ids) > 0 ? var.control_plane_subnet_ids : var.subnet_ids

  # OIDC configuration
  oidc_provider_arn = var.enable_irsa ? aws_iam_openid_connect_provider.cluster[0].arn : ""
  oidc_provider_url = var.enable_irsa ? replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "") : ""

  # Node group defaults
  node_group_defaults = {
    ami_type       = "AL2_x86_64"
    disk_size      = 50
    disk_type      = "gp3"
    capacity_type  = "ON_DEMAND"
    instance_types = ["t3.medium"]
  }

  # Security group IDs
  cluster_security_group_id = var.create_cluster_security_group ? aws_security_group.cluster[0].id : var.cluster_security_group_id
  node_security_group_id    = var.create_node_security_group ? aws_security_group.node[0].id : ""

  # KMS key for encryption
  create_kms_key      = var.enable_cluster_encryption && length(var.cluster_encryption_config) == 0
  cluster_kms_key_id  = local.create_kms_key ? aws_kms_key.cluster[0].arn : (length(var.cluster_encryption_config) > 0 ? var.cluster_encryption_config[0].provider_key_arn : null)
  cluster_kms_key_arn = local.create_kms_key ? aws_kms_key.cluster[0].arn : (length(var.cluster_encryption_config) > 0 ? var.cluster_encryption_config[0].provider_key_arn : null)

  # Encryption configuration
  cluster_encryption_config = local.cluster_kms_key_arn != null ? [{
    provider_key_arn = local.cluster_kms_key_arn
    resources        = ["secrets"]
  }] : []

  addon_service_accounts = {
    vpc-cni = {
      namespace       = "kube-system"
      service_account = "aws-node"
    }
    coredns = {
      namespace       = "kube-system"
      service_account = "coredns"
    }
    kube-proxy = {
      namespace       = "kube-system"
      service_account = "kube-proxy"
    }
  }

  # Node IAM role policies
  node_iam_role_policies = {
    AmazonEKSWorkerNodePolicy          = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    AmazonEKS_CNI_Policy               = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
    AmazonEC2ContainerRegistryReadOnly = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    AmazonSSMManagedInstanceCore       = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # Fargate profile IAM role policies
  fargate_profile_iam_role_policies = {
    AmazonEKSFargatePodExecutionRolePolicy = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  }

  # IRSA configurations for common services
  irsa_roles = merge(
    var.enable_cluster_autoscaler ? {
      cluster_autoscaler = {
        namespace       = "kube-system"
        service_account = "cluster-autoscaler"
        policy_document = data.aws_iam_policy_document.cluster_autoscaler[0].json
        policy_name     = "${var.cluster_name}-cluster-autoscaler"
      }
    } : {},
    var.enable_ebs_csi_driver ? {
      ebs_csi_driver = {
        namespace       = "kube-system"
        service_account = "ebs-csi-controller-sa"
        policy_document = data.aws_iam_policy_document.ebs_csi_driver[0].json
        policy_name     = "${var.cluster_name}-ebs-csi-driver"
      }
    } : {},
    var.enable_aws_load_balancer_controller ? {
      aws_load_balancer_controller = {
        namespace       = "kube-system"
        service_account = "aws-load-balancer-controller"
        policy_document = data.aws_iam_policy_document.aws_load_balancer_controller[0].json
        policy_name     = "${var.cluster_name}-aws-load-balancer-controller"
      }
    } : {}
  )

  # Node group configurations with defaults applied
  node_groups_config = {
    for k, v in var.node_groups : k => merge(
      local.node_group_defaults,
      v,
      {
        subnet_ids = coalesce(v.subnet_ids, var.subnet_ids)
        labels = merge(
          {
            "node-group"  = k
            "environment" = var.environment
          },
          coalesce(v.labels, {})
        )
        tags = merge(
          local.common_tags,
          {
            "Name"                                          = "${var.cluster_name}-${k}"
            "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
            "k8s.io/cluster-autoscaler/enabled"             = "true"
          },
          coalesce(v.tags, {})
        )
      }
    )
  }

  # Fargate profile configurations with subnet defaults
  fargate_profiles_config = {
    for k, v in var.fargate_profiles : k => merge(
      v,
      {
        subnet_ids = coalesce(v.subnet_ids, var.subnet_ids)
        tags = merge(
          local.common_tags,
          {
            Name = "${var.cluster_name}-${k}"
          },
          coalesce(v.tags, {})
        )
      }
    )
  }

  # Environment-specific defaults
  environment_defaults = {
    dev = {
      log_retention_days = 7
      instance_types     = ["t3.medium"]
    }
    staging = {
      log_retention_days = 30
      instance_types     = ["t3.large"]
    }
    prod = {
      log_retention_days = 90
      instance_types     = ["m5.large", "m5.xlarge"]
    }
  }

  environment_config = local.environment_defaults[var.environment]

  # CloudWatch log group
  cloudwatch_log_group_name = "/aws/eks/${var.cluster_name}/cluster"

  # Metadata options for IMDSv2
  metadata_options_imdsv2 = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  # Block device mappings for encrypted EBS volumes
  encrypted_block_device_mappings = [
    {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = 50
        volume_type           = "gp3"
        iops                  = 3000
        throughput            = 125
        encrypted             = true
        delete_on_termination = true
      }
    }
  ]
}
