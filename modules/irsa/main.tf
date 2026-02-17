# -----------------------------------------------------------------------------
# IAM Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "this" {
  count = var.create_role ? 1 : 0

  name                  = var.use_name_prefix ? null : local.role_name
  name_prefix           = var.use_name_prefix ? "${local.role_name}-" : null
  path                  = var.role_path
  description           = var.role_description != null ? var.role_description : "IRSA role for ${var.service_account_name} in ${var.cluster_name}"
  max_session_duration  = var.max_session_duration
  permissions_boundary  = var.role_permissions_boundary_arn
  assume_role_policy    = data.aws_iam_policy_document.assume_role.json
  force_detach_policies = var.force_detach_policies

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = var.create_role ? toset(local.policy_arns) : []

  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}

# -----------------------------------------------------------------------------
# Custom Inline Policy
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "custom" {
  count = var.create_role && local.has_custom_policy ? 1 : 0

  dynamic "statement" {
    for_each = var.policy_statements
    content {
      sid       = lookup(statement.value, "sid", null)
      effect    = lookup(statement.value, "effect", "Allow")
      actions   = lookup(statement.value, "actions", [])
      resources = lookup(statement.value, "resources", ["*"])

      dynamic "condition" {
        for_each = lookup(statement.value, "conditions", [])
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_iam_role_policy" "custom" {
  count = var.create_role && local.has_custom_policy ? 1 : 0

  name   = var.custom_policy_name != null ? var.custom_policy_name : "${local.role_name}-custom"
  role   = aws_iam_role.this[0].id
  policy = data.aws_iam_policy_document.custom[0].json
}

# -----------------------------------------------------------------------------
# Pre-built Policy: Cluster Autoscaler
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "cluster_autoscaler" {
  count = var.create_role && var.attach_cluster_autoscaler_policy ? 1 : 0

  statement {
    sid = "ClusterAutoscalerAll"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ClusterAutoscalerOwn"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeImages",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  count = var.create_role && var.attach_cluster_autoscaler_policy ? 1 : 0

  name        = var.use_name_prefix ? null : "${local.role_name}-cluster-autoscaler"
  name_prefix = var.use_name_prefix ? "${local.role_name}-cluster-autoscaler-" : null
  description = "Cluster Autoscaler policy for EKS cluster ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.cluster_autoscaler[0].json

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Pre-built Policy: AWS Load Balancer Controller
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "alb_controller" {
  count = var.create_role && var.attach_alb_controller_policy ? 1 : 0

  statement {
    sid = "ALBControllerIAMPermissions"
    actions = [
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid = "ALBControllerEC2Permissions"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ALBControllerELBPermissions"
    actions = [
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ALBControllerModifyPermissions"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid = "ALBControllerTagging"
    actions = [
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ALBControllerModifyLoadBalancer"
    actions = [
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid = "ALBControllerRegisterTargets"
    actions = [
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:ModifyRule",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ALBControllerWAFPermissions"
    actions = [
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ALBControllerShieldPermissions"
    actions = [
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ALBControllerCognitoPermissions"
    actions = [
      "cognito-idp:DescribeUserPoolClient",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ALBControllerACMPermissions"
    actions = [
      "acm:ListCertificates",
      "acm:DescribeCertificate",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "alb_controller" {
  count = var.create_role && var.attach_alb_controller_policy ? 1 : 0

  name        = var.use_name_prefix ? null : "${local.role_name}-alb-controller"
  name_prefix = var.use_name_prefix ? "${local.role_name}-alb-controller-" : null
  description = "AWS Load Balancer Controller policy for EKS cluster ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.alb_controller[0].json

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Pre-built Policy: External DNS
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "external_dns" {
  count = var.create_role && var.attach_external_dns_policy ? 1 : 0

  statement {
    sid = "ExternalDNSRoute53"
    actions = [
      "route53:ChangeResourceRecordSets",
    ]
    resources = var.external_dns_hosted_zone_arns != null ? var.external_dns_hosted_zone_arns : ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/*"]
  }

  statement {
    sid = "ExternalDNSRoute53List"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "external_dns" {
  count = var.create_role && var.attach_external_dns_policy ? 1 : 0

  name        = var.use_name_prefix ? null : "${local.role_name}-external-dns"
  name_prefix = var.use_name_prefix ? "${local.role_name}-external-dns-" : null
  description = "External DNS policy for EKS cluster ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.external_dns[0].json

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Pre-built Policy: Cert Manager
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "cert_manager" {
  count = var.create_role && var.attach_cert_manager_policy ? 1 : 0

  statement {
    sid = "CertManagerRoute53"
    actions = [
      "route53:GetChange",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::change/*"]
  }

  statement {
    sid = "CertManagerRoute53HostedZones"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
    ]
    resources = var.cert_manager_hosted_zone_arns != null ? var.cert_manager_hosted_zone_arns : ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/*"]
  }

  statement {
    sid = "CertManagerRoute53List"
    actions = [
      "route53:ListHostedZonesByName",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cert_manager" {
  count = var.create_role && var.attach_cert_manager_policy ? 1 : 0

  name        = var.use_name_prefix ? null : "${local.role_name}-cert-manager"
  name_prefix = var.use_name_prefix ? "${local.role_name}-cert-manager-" : null
  description = "Cert Manager policy for EKS cluster ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.cert_manager[0].json

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Pre-built Policy: External Secrets
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "external_secrets" {
  count = var.create_role && var.attach_external_secrets_policy ? 1 : 0

  statement {
    sid = "ExternalSecretsSecretsManager"
    actions = [
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = var.external_secrets_secrets_manager_arns != null ? var.external_secrets_secrets_manager_arns : ["*"]
  }

  statement {
    sid = "ExternalSecretsSSM"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParameterHistory",
      "ssm:GetParametersByPath",
    ]
    resources = var.external_secrets_ssm_parameter_arns != null ? var.external_secrets_ssm_parameter_arns : ["*"]
  }

  dynamic "statement" {
    for_each = var.external_secrets_kms_key_arns != null ? [1] : []
    content {
      sid = "ExternalSecretsKMS"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = var.external_secrets_kms_key_arns
    }
  }
}

resource "aws_iam_policy" "external_secrets" {
  count = var.create_role && var.attach_external_secrets_policy ? 1 : 0

  name        = var.use_name_prefix ? null : "${local.role_name}-external-secrets"
  name_prefix = var.use_name_prefix ? "${local.role_name}-external-secrets-" : null
  description = "External Secrets Operator policy for EKS cluster ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.external_secrets[0].json

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Kubernetes Service Account
# -----------------------------------------------------------------------------
resource "kubernetes_service_account_v1" "this" {
  count = var.create_service_account ? 1 : 0

  metadata {
    name      = var.service_account_name
    namespace = var.service_account_namespace

    labels = merge(
      {
        "app.kubernetes.io/managed-by" = "terraform"
      },
      var.service_account_labels
    )

    annotations = merge(
      {
        "eks.amazonaws.com/role-arn" = var.create_role ? aws_iam_role.this[0].arn : var.existing_role_arn
      },
      var.service_account_annotations
    )
  }

  dynamic "image_pull_secret" {
    for_each = var.service_account_image_pull_secrets
    content {
      name = image_pull_secret.value
    }
  }

  automount_service_account_token = var.automount_service_account_token
}
