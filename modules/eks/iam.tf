################################################################################
# Cluster IAM Role
################################################################################

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-cluster-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSVPCResourceController",
  ])

  policy_arn = each.value
  role       = aws_iam_role.cluster.name
}

################################################################################
# Node IAM Role
################################################################################

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-node-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.node_iam_role_policies

  policy_arn = each.value
  role       = aws_iam_role.node.name
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.cluster_name}-node-instance-profile"
  role = aws_iam_role.node.name

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-node-instance-profile"
    }
  )
}

################################################################################
# Fargate Profile IAM Role
################################################################################

resource "aws_iam_role" "fargate_profile" {
  count = length(var.fargate_profiles) > 0 ? 1 : 0

  name = "${var.cluster_name}-fargate-profile-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks-fargate-pods.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-fargate-profile-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "fargate_profile" {
  for_each = length(var.fargate_profiles) > 0 ? local.fargate_profile_iam_role_policies : {}

  policy_arn = each.value
  role       = aws_iam_role.fargate_profile[0].name
}

################################################################################
# IRSA Roles for Common Services
################################################################################

resource "aws_iam_role" "irsa" {
  for_each = var.enable_irsa ? local.irsa_roles : {}

  name = "${var.cluster_name}-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url}:sub" = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
            "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-${each.key}"
    }
  )
}

resource "aws_iam_policy" "irsa" {
  for_each = var.enable_irsa ? local.irsa_roles : {}

  name   = each.value.policy_name
  policy = each.value.policy_document

  tags = merge(
    local.common_tags,
    {
      Name = each.value.policy_name
    }
  )
}

resource "aws_iam_role_policy_attachment" "irsa" {
  for_each = var.enable_irsa ? local.irsa_roles : {}

  role       = aws_iam_role.irsa[each.key].name
  policy_arn = aws_iam_policy.irsa[each.key].arn
}

################################################################################
# External DNS IAM Role
################################################################################

resource "aws_iam_role" "external_dns" {
  count = var.enable_external_dns && var.enable_irsa ? 1 : 0

  name = "${var.cluster_name}-external-dns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:external-dns"
            "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-external-dns"
    }
  )
}

resource "aws_iam_policy" "external_dns" {
  count = var.enable_external_dns && var.enable_irsa ? 1 : 0

  name = "${var.cluster_name}-external-dns"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = var.external_dns_route53_zone_arns
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = ["*"]
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-external-dns"
    }
  )
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  count = var.enable_external_dns && var.enable_irsa ? 1 : 0

  role       = aws_iam_role.external_dns[0].name
  policy_arn = aws_iam_policy.external_dns[0].arn
}

################################################################################
# Cert Manager IAM Role
################################################################################

resource "aws_iam_role" "cert_manager" {
  count = var.enable_cert_manager && var.enable_irsa ? 1 : 0

  name = "${var.cluster_name}-cert-manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url}:sub" = "system:serviceaccount:cert-manager:cert-manager"
            "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-cert-manager"
    }
  )
}

resource "aws_iam_policy" "cert_manager" {
  count = var.enable_cert_manager && var.enable_irsa ? 1 : 0

  name = "${var.cluster_name}-cert-manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange"
        ]
        Resource = ["arn:${data.aws_partition.current.partition}:route53:::change/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = var.cert_manager_route53_zone_arns
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZonesByName"
        ]
        Resource = ["*"]
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-cert-manager"
    }
  )
}

resource "aws_iam_role_policy_attachment" "cert_manager" {
  count = var.enable_cert_manager && var.enable_irsa ? 1 : 0

  role       = aws_iam_role.cert_manager[0].name
  policy_arn = aws_iam_policy.cert_manager[0].arn
}
