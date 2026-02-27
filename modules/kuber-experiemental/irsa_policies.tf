# ─────────────────────────────────────────────────────────────────────────────
# irsa_policies.tf – IAM policies consumed by the built-in IRSA roles
#
# Kept separate from irsa.tf so policy JSON is easy to audit without wading
# through module call blocks.
# ─────────────────────────────────────────────────────────────────────────────

# ── AWS Load Balancer Controller ──────────────────────────────────────────────
# Policy source: https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller
# Loaded from a local JSON file so the full ~150-action policy stays readable.

resource "aws_iam_policy" "aws_load_balancer_controller" {
  count       = var.enable_irsa_aws_load_balancer_controller ? 1 : 0
  name        = "${local.name}-AWSLoadBalancerControllerIAMPolicy"
  description = "IAM policy for the AWS Load Balancer Controller running in ${local.name}"
  policy      = file("${path.module}/policies/aws_load_balancer_controller.json")
  tags        = local.common_tags
}

# ── Cluster Autoscaler ────────────────────────────────────────────────────────

resource "aws_iam_policy" "cluster_autoscaler" {
  count       = var.enable_irsa_cluster_autoscaler ? 1 : 0
  name        = "${local.name}-ClusterAutoscalerPolicy"
  description = "IAM policy for Cluster Autoscaler running in ${local.name}"
  tags        = local.common_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOnly"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup",
        ]
        Resource = ["*"]
      },
      {
        Sid    = "ScaleActions"
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
        ]
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/kubernetes.io/cluster/${local.name}" = "owned"
          }
        }
      },
    ]
  })
}

# ── ExternalDNS ───────────────────────────────────────────────────────────────

resource "aws_iam_policy" "external_dns" {
  count       = var.enable_irsa_external_dns ? 1 : 0
  name        = "${local.name}-ExternalDNSPolicy"
  description = "IAM policy for ExternalDNS running in ${local.name}"
  tags        = local.common_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ChangeRecordSets"
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Sid    = "ListZonesAndRecords"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource",
        ]
        Resource = ["*"]
      },
    ]
  })
}

# ── External Secrets Operator ─────────────────────────────────────────────────

resource "aws_iam_policy" "external_secrets" {
  count       = var.enable_irsa_external_secrets ? 1 : 0
  name        = "${local.name}-ExternalSecretsPolicy"
  description = "IAM policy for External Secrets Operator running in ${local.name}"
  tags        = local.common_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
          "secretsmanager:ListSecrets",
        ]
        Resource = ["*"]
      },
      {
        Sid    = "SSMParameterStore"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:DescribeParameters",
        ]
        Resource = ["*"]
      },
      {
        Sid      = "KMSDecrypt"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = ["*"]
      },
    ]
  })
}
