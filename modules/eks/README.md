# AWS EKS Terraform Module

A production-ready Terraform module for deploying Amazon EKS (Elastic Kubernetes Service) clusters with best practices and extensive configuration options.

## Features

- **Complete EKS Cluster Management**: Managed control plane with configurable endpoint access
- **Multiple Node Group Types**: Support for managed node groups, self-managed groups, and Fargate profiles
- **Security Best Practices**:
  - KMS encryption for secrets
  - IMDSv2 enforcement
  - Security group management
  - Private cluster support
- **IRSA (IAM Roles for Service Accounts)**: Built-in support for common Kubernetes controllers
- **CloudWatch Integration**: Cluster logging with configurable retention
- **Multi-Environment Support**: Environment-specific defaults and configurations
- **Access Management**: Modern EKS access entries API support
- **Comprehensive Addons**: VPC-CNI, CoreDNS, Kube-proxy, EBS CSI Driver

## Supported IRSA Roles

The module automatically creates IAM roles for:

- Cluster Autoscaler
- EBS CSI Driver
- AWS Load Balancer Controller
- External DNS
- Cert Manager

## Usage

### Basic Example

```hcl
module "eks" {
  source = "./modules/eks"

  cluster_name    = "my-cluster"
  cluster_version = "1.28"
  environment     = "dev"

  vpc_id     = "vpc-xxxxx"
  subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]

  node_groups = {
    general = {
      desired_size   = 3
      min_size       = 2
      max_size       = 5
      instance_types = ["t3.medium"]
    }
  }

  tags = {
    Environment = "dev"
    Project     = "my-project"
  }
}
```

### Production Example

```hcl
module "eks" {
  source = "./modules/eks"

  cluster_name    = "prod-cluster"
  cluster_version = "1.28"
  environment     = "prod"

  vpc_id     = "vpc-xxxxx"
  subnet_ids = ["subnet-xxxxx", "subnet-yyyyy", "subnet-zzzzz"]

  # Private cluster
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = false

  # Enable encryption
  enable_cluster_encryption = true

  # Multiple node groups
  node_groups = {
    general = {
      desired_size   = 3
      min_size       = 3
      max_size       = 10
      instance_types = ["m5.xlarge"]
      capacity_type  = "ON_DEMAND"

      use_custom_launch_template = true

      labels = {
        role = "general"
      }
    }

    compute = {
      desired_size   = 2
      min_size       = 2
      max_size       = 8
      instance_types = ["c5.2xlarge"]

      taints = [{
        key    = "workload"
        value  = "compute"
        effect = "NoSchedule"
      }]
    }
  }

  # Enable operational tools
  enable_cluster_autoscaler           = true
  enable_ebs_csi_driver              = true
  enable_aws_load_balancer_controller = true
  enable_external_dns                = true
  enable_cert_manager                = true

  # Access control
  authentication_mode = "API"

  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::123456789012:role/AdminRole"
      type         = "STANDARD"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = {
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}
```

## Module Structure

```
eks/
├── versions.tf           # Provider version constraints
├── variables.tf          # Input variables
├── data.tf              # Data sources
├── locals.tf            # Local values
├── main.tf              # EKS cluster and core resources
├── iam.tf               # IAM roles and policies
├── node_groups.tf       # Node groups and Fargate profiles
├── outputs.tf           # Output values
├── templates/
│   ├── userdata.sh.tpl  # EC2 userdata template
│   └── kubeconfig.tpl   # Kubeconfig template
└── README.md            # This file
```

## Environment-Specific Configurations

The module includes environment-specific defaults:

### Development

- Minimal logging (7 days retention)
- Smaller instance types (t3.medium)
- Public endpoint access allowed
- SPOT instances for cost savings

### Staging

- Moderate logging (30 days retention)
- Medium instance types (t3.large)
- Balanced configuration

### Production

- Full logging (90 days retention)
- Production instance types (m5.large+)
- Private endpoint only
- High availability configuration
- Enhanced security

## Important Variables

| Variable                          | Description                    | Type           | Default  | Required |
| --------------------------------- | ------------------------------ | -------------- | -------- | -------- |
| `cluster_name`                    | Name of the EKS cluster        | `string`       | n/a      | yes      |
| `environment`                     | Environment (dev/staging/prod) | `string`       | n/a      | yes      |
| `cluster_version`                 | Kubernetes version             | `string`       | `"1.28"` | no       |
| `vpc_id`                          | VPC ID                         | `string`       | n/a      | yes      |
| `subnet_ids`                      | List of subnet IDs             | `list(string)` | n/a      | yes      |
| `node_groups`                     | Node group configurations      | `map(object)`  | `{}`     | no       |
| `enable_irsa`                     | Enable IRSA                    | `bool`         | `true`   | no       |
| `cluster_endpoint_private_access` | Enable private endpoint        | `bool`         | `true`   | no       |
| `cluster_endpoint_public_access`  | Enable public endpoint         | `bool`         | `false`  | no       |

## Outputs

| Output                                  | Description                 |
| --------------------------------------- | --------------------------- |
| `cluster_id`                            | EKS cluster ID              |
| `cluster_endpoint`                      | EKS cluster endpoint        |
| `cluster_certificate_authority_data`    | Cluster CA certificate      |
| `oidc_provider_arn`                     | OIDC provider ARN           |
| `node_groups`                           | Node group information      |
| `cluster_autoscaler_role_arn`           | Cluster Autoscaler IAM role |
| `ebs_csi_driver_role_arn`               | EBS CSI Driver IAM role     |
| `aws_load_balancer_controller_role_arn` | ALB Controller IAM role     |

## Post-Deployment

### Configure kubectl

```bash
aws eks update-kubeconfig --region <region> --name <cluster-name>
```

### Install Cluster Autoscaler

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

kubectl annotate serviceaccount cluster-autoscaler \
  -n kube-system \
  eks.amazonaws.com/role-arn=<cluster-autoscaler-role-arn>
```

### Install AWS Load Balancer Controller

```bash
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<cluster-name> \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<alb-controller-role-arn>
```

## Security Considerations

1. **Private Clusters**: Set `cluster_endpoint_public_access = false` for production
2. **Encryption**: Enable `enable_cluster_encryption = true`
3. **IMDSv2**: Enforced by default in custom launch templates
4. **Network Policies**: Consider implementing Kubernetes network policies
5. **Pod Security Standards**: Implement pod security admission
6. **Secrets Management**: Use AWS Secrets Manager or External Secrets Operator
7. **Audit Logging**: Enable all control plane logs in production

## Cost Optimization

1. Use SPOT instances for non-critical workloads
2. Right-size node groups based on workload requirements
3. Implement cluster autoscaler for dynamic scaling
4. Use Fargate for sporadic workloads
5. Consider Savings Plans or Reserved Instances for stable workloads

## Upgrade Strategy

1. Review Kubernetes version release notes
2. Test in development environment first
3. Upgrade control plane: `cluster_version`
4. Upgrade node groups gradually
5. Update addons to compatible versions
6. Monitor cluster health and application performance

## Troubleshooting

### Nodes not joining cluster

- Check IAM roles have correct permissions
- Verify security group rules
- Check VPC/subnet configuration
- Review CloudWatch logs

### IRSA not working

- Verify OIDC provider is created
- Check service account annotations
- Ensure trust policy is correct
- Validate IAM policy permissions

### Pod networking issues

- Check VPC-CNI addon version
- Verify subnet IP availability
- Review security group rules
- Check network ACLs

## Contributing

When contributing, ensure:

1. All variables have descriptions and types
2. Sensitive outputs are marked as sensitive
3. Examples are tested and working
4. Documentation is updated
5. Code follows Terraform best practices

## License

This module is provided as-is for use in your projects.

## Support

For issues and questions:

1. Check the AWS EKS documentation
2. Review Terraform AWS provider documentation
3. Check CloudWatch logs for cluster issues
4. Use AWS Support for platform-level issues

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.20 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | >= 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | >= 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eks_access_entry.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_policy_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_policy_association) | resource |
| [aws_eks_addon.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_eks_fargate_profile.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_fargate_profile) | resource |
| [aws_eks_node_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group) | resource |
| [aws_iam_instance_profile.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_openid_connect_provider.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_policy.cert_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.external_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.irsa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.cert_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.external_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.fargate_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.irsa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cert_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.external_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.fargate_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.irsa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key_policy.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key_policy) | resource |
| [aws_launch_template.node_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_security_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.cluster_egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.cluster_ingress_node_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.node_egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.node_ingress_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.node_ingress_cluster_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.node_ingress_self](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_ami.eks_default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_eks_cluster_auth.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster_auth) | data source |
| [aws_iam_policy_document.aws_load_balancer_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.cluster_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.cluster_autoscaler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ebs_csi_driver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.node_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_subnets.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |
| [aws_vpc.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |
| [tls_certificate.cluster](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_entries"></a> [access\_entries](#input\_access\_entries) | Map of access entries to add to the cluster | <pre>map(object({<br>    kubernetes_groups = optional(list(string))<br>    principal_arn     = string<br>    type              = optional(string, "STANDARD")<br>    policy_associations = optional(map(object({<br>      policy_arn = string<br>      access_scope = object({<br>        type       = string<br>        namespaces = optional(list(string))<br>      })<br>    })), {})<br>  }))</pre> | `{}` | no |
| <a name="input_authentication_mode"></a> [authentication\_mode](#input\_authentication\_mode) | Authentication mode for the cluster (API, API\_AND\_CONFIG\_MAP, or CONFIG\_MAP) | `string` | `"API_AND_CONFIG_MAP"` | no |
| <a name="input_aws_auth_accounts"></a> [aws\_auth\_accounts](#input\_aws\_auth\_accounts) | List of account maps to add to the aws-auth configmap | `list(string)` | `[]` | no |
| <a name="input_aws_auth_roles"></a> [aws\_auth\_roles](#input\_aws\_auth\_roles) | List of role maps to add to the aws-auth configmap | <pre>list(object({<br>    rolearn  = string<br>    username = string<br>    groups   = list(string)<br>  }))</pre> | `[]` | no |
| <a name="input_aws_auth_users"></a> [aws\_auth\_users](#input\_aws\_auth\_users) | List of user maps to add to the aws-auth configmap | <pre>list(object({<br>    userarn  = string<br>    username = string<br>    groups   = list(string)<br>  }))</pre> | `[]` | no |
| <a name="input_cert_manager_route53_zone_arns"></a> [cert\_manager\_route53\_zone\_arns](#input\_cert\_manager\_route53\_zone\_arns) | Route53 zone ARNs for Cert Manager | `list(string)` | `[]` | no |
| <a name="input_cloudwatch_log_group_kms_key_id"></a> [cloudwatch\_log\_group\_kms\_key\_id](#input\_cloudwatch\_log\_group\_kms\_key\_id) | KMS key ID to encrypt CloudWatch logs | `string` | `null` | no |
| <a name="input_cloudwatch_log_group_retention_in_days"></a> [cloudwatch\_log\_group\_retention\_in\_days](#input\_cloudwatch\_log\_group\_retention\_in\_days) | Number of days to retain log events | `number` | `90` | no |
| <a name="input_cluster_addons"></a> [cluster\_addons](#input\_cluster\_addons) | Map of cluster addon configurations | <pre>map(object({<br>    version                  = string<br>    resolve_conflicts        = optional(string, "OVERWRITE")<br>    service_account_role_arn = optional(string)<br>    configuration_values     = optional(string)<br>  }))</pre> | <pre>{<br>  "coredns": {<br>    "resolve_conflicts": "OVERWRITE",<br>    "version": "v1.10.1-eksbuild.2"<br>  },<br>  "kube-proxy": {<br>    "resolve_conflicts": "OVERWRITE",<br>    "version": "v1.28.1-eksbuild.1"<br>  },<br>  "vpc-cni": {<br>    "resolve_conflicts": "OVERWRITE",<br>    "version": "v1.15.1-eksbuild.1"<br>  }<br>}</pre> | no |
| <a name="input_cluster_enabled_log_types"></a> [cluster\_enabled\_log\_types](#input\_cluster\_enabled\_log\_types) | List of control plane logging types to enable | `list(string)` | <pre>[<br>  "api",<br>  "audit",<br>  "authenticator",<br>  "controllerManager",<br>  "scheduler"<br>]</pre> | no |
| <a name="input_cluster_encryption_config"></a> [cluster\_encryption\_config](#input\_cluster\_encryption\_config) | Configuration block with encryption configuration for the cluster | <pre>list(object({<br>    provider_key_arn = string<br>    resources        = list(string)<br>  }))</pre> | `[]` | no |
| <a name="input_cluster_endpoint_private_access"></a> [cluster\_endpoint\_private\_access](#input\_cluster\_endpoint\_private\_access) | Enable private API server endpoint | `bool` | `true` | no |
| <a name="input_cluster_endpoint_public_access"></a> [cluster\_endpoint\_public\_access](#input\_cluster\_endpoint\_public\_access) | Enable public API server endpoint | `bool` | `false` | no |
| <a name="input_cluster_endpoint_public_access_cidrs"></a> [cluster\_endpoint\_public\_access\_cidrs](#input\_cluster\_endpoint\_public\_access\_cidrs) | List of CIDR blocks that can access the public API server endpoint | `list(string)` | <pre>[<br>  "0.0.0.0/0"<br>]</pre> | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster | `string` | n/a | yes |
| <a name="input_cluster_security_group_additional_rules"></a> [cluster\_security\_group\_additional\_rules](#input\_cluster\_security\_group\_additional\_rules) | Additional security group rules for the cluster security group | `any` | `{}` | no |
| <a name="input_cluster_security_group_id"></a> [cluster\_security\_group\_id](#input\_cluster\_security\_group\_id) | Existing security group ID for the cluster (if not creating new one) | `string` | `""` | no |
| <a name="input_cluster_tags"></a> [cluster\_tags](#input\_cluster\_tags) | Additional tags for the cluster | `map(string)` | `{}` | no |
| <a name="input_cluster_timeouts"></a> [cluster\_timeouts](#input\_cluster\_timeouts) | Timeout configuration for cluster operations | <pre>object({<br>    create = optional(string)<br>    update = optional(string)<br>    delete = optional(string)<br>  })</pre> | `{}` | no |
| <a name="input_cluster_version"></a> [cluster\_version](#input\_cluster\_version) | Kubernetes version to use for the EKS cluster | `string` | `"1.28"` | no |
| <a name="input_control_plane_subnet_ids"></a> [control\_plane\_subnet\_ids](#input\_control\_plane\_subnet\_ids) | List of subnet IDs for the EKS control plane (if different from worker nodes) | `list(string)` | `[]` | no |
| <a name="input_create_cluster_security_group"></a> [create\_cluster\_security\_group](#input\_create\_cluster\_security\_group) | Whether to create a security group for the cluster | `bool` | `true` | no |
| <a name="input_create_node_security_group"></a> [create\_node\_security\_group](#input\_create\_node\_security\_group) | Whether to create a security group for the nodes | `bool` | `true` | no |
| <a name="input_enable_aws_load_balancer_controller"></a> [enable\_aws\_load\_balancer\_controller](#input\_enable\_aws\_load\_balancer\_controller) | Enable AWS Load Balancer Controller IAM role | `bool` | `true` | no |
| <a name="input_enable_cert_manager"></a> [enable\_cert\_manager](#input\_enable\_cert\_manager) | Enable Cert Manager IAM role | `bool` | `false` | no |
| <a name="input_enable_cluster_autoscaler"></a> [enable\_cluster\_autoscaler](#input\_enable\_cluster\_autoscaler) | Enable Cluster Autoscaler IAM role | `bool` | `true` | no |
| <a name="input_enable_cluster_encryption"></a> [enable\_cluster\_encryption](#input\_enable\_cluster\_encryption) | Enable encryption of Kubernetes secrets | `bool` | `true` | no |
| <a name="input_enable_ebs_csi_driver"></a> [enable\_ebs\_csi\_driver](#input\_enable\_ebs\_csi\_driver) | Enable EBS CSI Driver | `bool` | `true` | no |
| <a name="input_enable_efs_csi_driver"></a> [enable\_efs\_csi\_driver](#input\_enable\_efs\_csi\_driver) | Enable EFS CSI Driver | `bool` | `false` | no |
| <a name="input_enable_external_dns"></a> [enable\_external\_dns](#input\_enable\_external\_dns) | Enable External DNS IAM role | `bool` | `false` | no |
| <a name="input_enable_irsa"></a> [enable\_irsa](#input\_enable\_irsa) | Enable IAM Roles for Service Accounts | `bool` | `true` | no |
| <a name="input_enable_pod_identity"></a> [enable\_pod\_identity](#input\_enable\_pod\_identity) | Enable EKS Pod Identity | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, staging, prod) | `string` | n/a | yes |
| <a name="input_external_dns_route53_zone_arns"></a> [external\_dns\_route53\_zone\_arns](#input\_external\_dns\_route53\_zone\_arns) | Route53 zone ARNs for External DNS | `list(string)` | `[]` | no |
| <a name="input_fargate_profiles"></a> [fargate\_profiles](#input\_fargate\_profiles) | Map of Fargate profile configurations | <pre>map(object({<br>    selectors = list(object({<br>      namespace = string<br>      labels    = optional(map(string), {})<br>    }))<br>    subnet_ids = optional(list(string))<br>    tags       = optional(map(string), {})<br>  }))</pre> | `{}` | no |
| <a name="input_kms_key_administrators"></a> [kms\_key\_administrators](#input\_kms\_key\_administrators) | List of IAM ARNs for KMS key administrators | `list(string)` | `[]` | no |
| <a name="input_manage_aws_auth_configmap"></a> [manage\_aws\_auth\_configmap](#input\_manage\_aws\_auth\_configmap) | Determines whether to manage the aws-auth configmap | `bool` | `true` | no |
| <a name="input_node_groups"></a> [node\_groups](#input\_node\_groups) | Map of node group configurations | <pre>map(object({<br>    desired_size    = number<br>    min_size        = number<br>    max_size        = number<br>    instance_types  = list(string)<br>    capacity_type   = optional(string, "ON_DEMAND")<br>    disk_size       = optional(number, 50)<br>    disk_type       = optional(string, "gp3")<br>    disk_iops       = optional(number)<br>    disk_throughput = optional(number)<br>    ami_type        = optional(string, "AL2_x86_64")<br>    labels          = optional(map(string), {})<br>    taints = optional(list(object({<br>      key    = string<br>      value  = string<br>      effect = string<br>    })), [])<br>    tags                       = optional(map(string), {})<br>    subnet_ids                 = optional(list(string))<br>    use_custom_launch_template = optional(bool, false)<br>    block_device_mappings      = optional(any)<br>    metadata_options = optional(object({<br>      http_endpoint               = string<br>      http_tokens                 = string<br>      http_put_response_hop_limit = number<br>      instance_metadata_tags      = string<br>    }))<br>    update_config = optional(object({<br>      max_unavailable_percentage = optional(number)<br>      max_unavailable            = optional(number)<br>    }))<br>  }))</pre> | `{}` | no |
| <a name="input_node_security_group_additional_rules"></a> [node\_security\_group\_additional\_rules](#input\_node\_security\_group\_additional\_rules) | Additional security group rules for node security group | `any` | `{}` | no |
| <a name="input_node_security_group_tags"></a> [node\_security\_group\_tags](#input\_node\_security\_group\_tags) | Additional tags for node security group | `map(string)` | `{}` | no |
| <a name="input_self_managed_node_groups"></a> [self\_managed\_node\_groups](#input\_self\_managed\_node\_groups) | Map of self-managed node group configurations | `any` | `{}` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs for the EKS cluster | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the cluster will be deployed | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_load_balancer_controller_role_arn"></a> [aws\_load\_balancer\_controller\_role\_arn](#output\_aws\_load\_balancer\_controller\_role\_arn) | IAM role ARN for AWS Load Balancer Controller |
| <a name="output_cert_manager_role_arn"></a> [cert\_manager\_role\_arn](#output\_cert\_manager\_role\_arn) | IAM role ARN for Cert Manager |
| <a name="output_cloudwatch_log_group_arn"></a> [cloudwatch\_log\_group\_arn](#output\_cloudwatch\_log\_group\_arn) | ARN of the CloudWatch log group for cluster logs |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Name of the CloudWatch log group for cluster logs |
| <a name="output_cluster_addons"></a> [cluster\_addons](#output\_cluster\_addons) | Map of cluster addon attributes |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | The ARN of the EKS cluster |
| <a name="output_cluster_auth_token"></a> [cluster\_auth\_token](#output\_cluster\_auth\_token) | Authentication token for the cluster |
| <a name="output_cluster_autoscaler_role_arn"></a> [cluster\_autoscaler\_role\_arn](#output\_cluster\_autoscaler\_role\_arn) | IAM role ARN for Cluster Autoscaler |
| <a name="output_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#output\_cluster\_certificate\_authority\_data) | Base64 encoded certificate data required to communicate with the cluster |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | Endpoint for EKS control plane |
| <a name="output_cluster_iam_role_arn"></a> [cluster\_iam\_role\_arn](#output\_cluster\_iam\_role\_arn) | IAM role ARN of the EKS cluster |
| <a name="output_cluster_iam_role_name"></a> [cluster\_iam\_role\_name](#output\_cluster\_iam\_role\_name) | IAM role name of the EKS cluster |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The ID of the EKS cluster |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | The name of the EKS cluster |
| <a name="output_cluster_oidc_issuer_url"></a> [cluster\_oidc\_issuer\_url](#output\_cluster\_oidc\_issuer\_url) | The URL on the EKS cluster OIDC Issuer |
| <a name="output_cluster_platform_version"></a> [cluster\_platform\_version](#output\_cluster\_platform\_version) | The platform version for the cluster |
| <a name="output_cluster_security_group_id"></a> [cluster\_security\_group\_id](#output\_cluster\_security\_group\_id) | Security group ID attached to the EKS cluster |
| <a name="output_cluster_version"></a> [cluster\_version](#output\_cluster\_version) | The Kubernetes server version for the cluster |
| <a name="output_ebs_csi_driver_role_arn"></a> [ebs\_csi\_driver\_role\_arn](#output\_ebs\_csi\_driver\_role\_arn) | IAM role ARN for EBS CSI Driver |
| <a name="output_external_dns_role_arn"></a> [external\_dns\_role\_arn](#output\_external\_dns\_role\_arn) | IAM role ARN for External DNS |
| <a name="output_fargate_profile_iam_role_arn"></a> [fargate\_profile\_iam\_role\_arn](#output\_fargate\_profile\_iam\_role\_arn) | IAM role ARN for Fargate profiles |
| <a name="output_fargate_profiles"></a> [fargate\_profiles](#output\_fargate\_profiles) | Map of Fargate profile attributes |
| <a name="output_irsa_roles"></a> [irsa\_roles](#output\_irsa\_roles) | Map of IRSA role ARNs |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | KMS key ARN used for cluster encryption |
| <a name="output_kms_key_id"></a> [kms\_key\_id](#output\_kms\_key\_id) | KMS key ID used for cluster encryption |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | kubectl config for connecting to the cluster |
| <a name="output_node_groups"></a> [node\_groups](#output\_node\_groups) | Map of node group attributes |
| <a name="output_node_iam_role_arn"></a> [node\_iam\_role\_arn](#output\_node\_iam\_role\_arn) | IAM role ARN of the EKS nodes |
| <a name="output_node_iam_role_name"></a> [node\_iam\_role\_name](#output\_node\_iam\_role\_name) | IAM role name of the EKS nodes |
| <a name="output_node_instance_profile_arn"></a> [node\_instance\_profile\_arn](#output\_node\_instance\_profile\_arn) | IAM instance profile ARN for EKS nodes |
| <a name="output_node_instance_profile_name"></a> [node\_instance\_profile\_name](#output\_node\_instance\_profile\_name) | IAM instance profile name for EKS nodes |
| <a name="output_node_security_group_id"></a> [node\_security\_group\_id](#output\_node\_security\_group\_id) | Security group ID attached to the EKS nodes |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the OIDC Provider for EKS |
| <a name="output_oidc_provider_url"></a> [oidc\_provider\_url](#output\_oidc\_provider\_url) | URL of the OIDC Provider for EKS |
<!-- END_TF_DOCS -->