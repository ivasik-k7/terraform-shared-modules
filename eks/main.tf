################################################################################
# EKS Cluster
################################################################################

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = local.control_plane_subnet_ids
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
    security_group_ids      = var.create_cluster_security_group ? [aws_security_group.cluster[0].id] : []
  }

  enabled_cluster_log_types = var.cluster_enabled_log_types

  dynamic "encryption_config" {
    for_each = local.cluster_encryption_config

    content {
      provider {
        key_arn = encryption_config.value.provider_key_arn
      }
      resources = encryption_config.value.resources
    }
  }

  access_config {
    authentication_mode                         = var.authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.authentication_mode == "API" ? true : false
  }

  dynamic "timeouts" {
    for_each = var.cluster_timeouts != null ? [var.cluster_timeouts] : []

    content {
      create = lookup(timeouts.value, "create", null)
      update = lookup(timeouts.value, "update", null)
      delete = lookup(timeouts.value, "delete", null)
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]

  tags = local.cluster_tags
}

################################################################################
# CloudWatch Log Group
################################################################################

resource "aws_cloudwatch_log_group" "cluster" {
  name              = local.cloudwatch_log_group_name
  retention_in_days = var.cloudwatch_log_group_retention_in_days
  kms_key_id        = var.cloudwatch_log_group_kms_key_id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-logs"
    }
  )
}

################################################################################
# KMS Key for Cluster Encryption
################################################################################

resource "aws_kms_key" "cluster" {
  count = local.create_kms_key ? 1 : 0

  description             = "EKS Secret Encryption Key for ${var.cluster_name}"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-eks-secrets"
    }
  )
}

resource "aws_kms_alias" "cluster" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.cluster[0].key_id
}

resource "aws_kms_key_policy" "cluster" {
  count = local.create_kms_key ? 1 : 0

  key_id = aws_kms_key.cluster[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key for EKS"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })
}

################################################################################
# Cluster Security Group
################################################################################

resource "aws_security_group" "cluster" {
  count = var.create_cluster_security_group ? 1 : 0

  name_prefix = "${var.cluster_name}-cluster-"
  description = "EKS cluster security group"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-cluster-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "cluster_egress" {
  count = var.create_cluster_security_group ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cluster[0].id
  description       = "Allow all egress"
}

################################################################################
# Node Security Group
################################################################################

resource "aws_security_group" "node" {
  count = var.create_node_security_group ? 1 : 0

  name_prefix = "${var.cluster_name}-node-"
  description = "Security group for all nodes in the cluster"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    var.node_security_group_tags,
    {
      Name                                        = "${var.cluster_name}-node-sg"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "node_ingress_self" {
  count = var.create_node_security_group ? 1 : 0

  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.node[0].id
  description       = "Allow nodes to communicate with each other"
}

resource "aws_security_group_rule" "node_ingress_cluster" {
  count = var.create_node_security_group ? 1 : 0

  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = local.cluster_security_group_id
  security_group_id        = aws_security_group.node[0].id
  description              = "Allow worker pods to receive communication from the cluster control plane"
}

resource "aws_security_group_rule" "node_ingress_cluster_https" {
  count = var.create_node_security_group ? 1 : 0

  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = local.cluster_security_group_id
  security_group_id        = aws_security_group.node[0].id
  description              = "Allow pods to communicate with the cluster API Server"
}

resource "aws_security_group_rule" "node_egress" {
  count = var.create_node_security_group ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node[0].id
  description       = "Allow all egress"
}

resource "aws_security_group_rule" "cluster_ingress_node_https" {
  count = var.create_cluster_security_group && var.create_node_security_group ? 1 : 0

  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.node[0].id
  security_group_id        = aws_security_group.cluster[0].id
  description              = "Allow pods to communicate with the cluster API Server"
}

################################################################################
# IRSA (IAM Roles for Service Accounts)
################################################################################

resource "aws_iam_openid_connect_provider" "cluster" {
  count = var.enable_irsa ? 1 : 0

  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster[0].certificates[0].sha1_fingerprint]

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-eks-irsa"
    }
  )
}

################################################################################
# EKS Addons
################################################################################

resource "aws_eks_addon" "this" {
  for_each = var.cluster_addons

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value.version
  resolve_conflicts_on_create = each.value.resolve_conflicts
  resolve_conflicts_on_update = each.value.resolve_conflicts
  service_account_role_arn    = each.value.service_account_role_arn
  configuration_values        = each.value.configuration_values

  tags = local.common_tags

  depends_on = [
    aws_eks_node_group.this,
  ]
}

################################################################################
# EKS Access Entries
################################################################################

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.value.principal_arn
  kubernetes_groups = each.value.kubernetes_groups
  type              = each.value.type

  tags = local.common_tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each = merge([
    for entry_key, entry in var.access_entries : {
      for policy_key, policy in coalesce(entry.policy_associations, {}) :
      "${entry_key}_${policy_key}" => {
        entry_key  = entry_key
        policy_key = policy_key
        policy     = policy
      }
    }
  ]...)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.access_entries[each.value.entry_key].principal_arn
  policy_arn    = each.value.policy.policy_arn

  access_scope {
    type       = each.value.policy.access_scope.type
    namespaces = each.value.policy.access_scope.namespaces
  }

  depends_on = [
    aws_eks_access_entry.this
  ]
}
