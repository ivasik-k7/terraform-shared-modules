################################################################################
# Cluster Outputs
################################################################################

output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = aws_eks_cluster.this.id
}

output "cluster_arn" {
  description = "The ARN of the EKS cluster"
  value       = aws_eks_cluster.this.arn
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "The Kubernetes server version for the cluster"
  value       = aws_eks_cluster.this.version
}

output "cluster_platform_version" {
  description = "The platform version for the cluster"
  value       = aws_eks_cluster.this.platform_version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = try(aws_security_group.cluster[0].id, "")
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = try(aws_security_group.node[0].id, "")
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = aws_iam_role.cluster.arn
}

output "cluster_iam_role_name" {
  description = "IAM role name of the EKS cluster"
  value       = aws_iam_role.cluster.name
}

################################################################################
# OIDC Provider Outputs
################################################################################

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for EKS"
  value       = var.enable_irsa ? aws_iam_openid_connect_provider.cluster[0].arn : ""
}

output "oidc_provider_url" {
  description = "URL of the OIDC Provider for EKS"
  value       = local.oidc_provider_url
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = try(aws_eks_cluster.this.identity[0].oidc[0].issuer, "")
}

################################################################################
# Node Group Outputs
################################################################################

output "node_groups" {
  description = "Map of node group attributes"
  value = {
    for k, v in aws_eks_node_group.this : k => {
      id            = v.id
      arn           = v.arn
      status        = v.status
      capacity_type = v.capacity_type
      node_role_arn = v.node_role_arn
      resources     = v.resources
    }
  }
}

output "node_iam_role_arn" {
  description = "IAM role ARN of the EKS nodes"
  value       = aws_iam_role.node.arn
}

output "node_iam_role_name" {
  description = "IAM role name of the EKS nodes"
  value       = aws_iam_role.node.name
}

output "node_instance_profile_arn" {
  description = "IAM instance profile ARN for EKS nodes"
  value       = aws_iam_instance_profile.node.arn
}

output "node_instance_profile_name" {
  description = "IAM instance profile name for EKS nodes"
  value       = aws_iam_instance_profile.node.name
}

################################################################################
# Fargate Profile Outputs
################################################################################

output "fargate_profiles" {
  description = "Map of Fargate profile attributes"
  value = {
    for k, v in aws_eks_fargate_profile.this : k => {
      id     = v.id
      arn    = v.arn
      status = v.status
    }
  }
}

output "fargate_profile_iam_role_arn" {
  description = "IAM role ARN for Fargate profiles"
  value       = try(aws_iam_role.fargate_profile[0].arn, "")
}

################################################################################
# Addon Outputs
################################################################################

output "cluster_addons" {
  description = "Map of cluster addon attributes"
  value = {
    for k, v in aws_eks_addon.this : k => {
      id            = v.id
      arn           = v.arn
      addon_version = v.addon_version
    }
  }
}

################################################################################
# IRSA Role Outputs
################################################################################

output "irsa_roles" {
  description = "Map of IRSA role ARNs"
  value = {
    for k, v in aws_iam_role.irsa : k => {
      arn  = v.arn
      name = v.name
    }
  }
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler"
  value       = var.enable_cluster_autoscaler && var.enable_irsa ? aws_iam_role.irsa["cluster_autoscaler"].arn : ""
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI Driver"
  value       = var.enable_ebs_csi_driver && var.enable_irsa ? aws_iam_role.irsa["ebs_csi_driver"].arn : ""
}

output "aws_load_balancer_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = var.enable_aws_load_balancer_controller && var.enable_irsa ? aws_iam_role.irsa["aws_load_balancer_controller"].arn : ""
}

output "external_dns_role_arn" {
  description = "IAM role ARN for External DNS"
  value       = var.enable_external_dns && var.enable_irsa ? aws_iam_role.external_dns[0].arn : ""
}

output "cert_manager_role_arn" {
  description = "IAM role ARN for Cert Manager"
  value       = var.enable_cert_manager && var.enable_irsa ? aws_iam_role.cert_manager[0].arn : ""
}

################################################################################
# CloudWatch Outputs
################################################################################

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for cluster logs"
  value       = aws_cloudwatch_log_group.cluster.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for cluster logs"
  value       = aws_cloudwatch_log_group.cluster.arn
}

################################################################################
# KMS Outputs
################################################################################

output "kms_key_id" {
  description = "KMS key ID used for cluster encryption"
  value       = try(aws_kms_key.cluster[0].id, "")
}

output "kms_key_arn" {
  description = "KMS key ARN used for cluster encryption"
  value       = try(aws_kms_key.cluster[0].arn, "")
}

################################################################################
# Kubernetes Provider Config
################################################################################

output "kubeconfig" {
  description = "kubectl config for connecting to the cluster"
  value = templatefile("${path.module}/templates/kubeconfig.tpl", {
    cluster_name           = aws_eks_cluster.this.name
    cluster_endpoint       = aws_eks_cluster.this.endpoint
    cluster_ca_certificate = aws_eks_cluster.this.certificate_authority[0].data
  })
  sensitive = true
}

output "cluster_auth_token" {
  description = "Authentication token for the cluster"
  value       = data.aws_eks_cluster_auth.cluster.token
  sensitive   = true
}
