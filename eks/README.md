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
