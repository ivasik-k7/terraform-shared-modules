# AWS Infrastructure Terraform Modules

Production-grade, enterprise-ready Terraform modules for deploying AWS infrastructure components. Built with security, scalability, and operational excellence as core principles.

## Overview

This repository provides a collection of reusable Terraform modules for common AWS services. Each module is independently deployable, fully tested, and follows AWS best practices. Modules can be composed together to build complete infrastructure solutions.

## Quick Start

### Prerequisites

- **Terraform** `>= 1.3.0`
- **AWS Provider** `>= 5.0`
- **AWS Credentials** configured with appropriate permissions
- **AWS Account** with necessary service limits

### Basic Usage

```hcl
module "aurora" {
  source = "./aurora"

  cluster_identifier = "my-database"
  engine             = "aurora-postgresql"
  engine_version     = "15.3"

  vpc_id             = aws_vpc.main.id
  subnet_ids         = aws_subnet.private[*].id

  master_username    = "admin"
  master_password    = var.db_password  # Use var.sensitive = true

  tags = {
    Environment = "production"
    Project     = "my-app"
  }
}
```

See module-specific READMEs for detailed configuration options and examples.

## Available Modules

### 📊 [Aurora](./aurora)

Managed relational database with high availability and disaster recovery.

**Key Features:**

- Multi-AZ deployments with automatic failover
- Global database for cross-region replication
- Serverless v2 auto-scaling
- Enhanced monitoring and CloudWatch alarms
- Automated backups with PITR
- KMS encryption at rest

**Use Case:** Production databases requiring HA, read replicas, and compliance

---

### 🐳 [ECR](./ecr)

Elastic Container Registry for managing Docker container images.

**Key Features:**

- Private repositories with fine-grained access control
- Image lifecycle policies for cost optimization
- Image scanning with vulnerability detection
- Cross-account/cross-region replication
- Registry pull-through cache

**Use Case:** Container image storage and distribution for EKS, ECS workloads

---

### ☸️ [EKS](./eks)

Amazon Elastic Kubernetes Service for managed container orchestration.

**Key Features:**

- Managed Kubernetes control plane
- Auto-scaling node groups with Spot instance support
- IAM Roles for Service Accounts (IRSA)
- Built-in cluster addons (VPC CNI, CoreDNS, kube-proxy)
- KMS envelope encryption for etcd
- Advanced networking and security controls

**Use Case:** Microservices orchestration, containerized applications at scale

---

### 🗺️ Planned Modules

- **S3** - Object storage with lifecycle policies and replication
- **CloudFront** - Global CDN with WAF integration
- **Route53** - DNS and traffic management
- **Networking** - VPC, subnets, and security infrastructure

## Architecture Patterns

### Composition Model

Modules are designed to be independently useful while supporting composition:

```hcl
# Deploy complete application stack
module "aurora" {
  source = "./aurora"
  # configuration...
}

module "eks" {
  source = "./eks"
  # configuration...
}

module "ecr" {
  source = "./ecr"
  # configuration...
}
```

### Best Practices Implemented

Each module enforces:

✅ **Encryption** - All data at rest encrypted with AWS KMS  
✅ **Least Privilege** - IAM roles and security groups follow principle of least privilege  
✅ **High Availability** - Multi-AZ deployment where applicable  
✅ **Observability** - CloudWatch monitoring, logging, and alarms included  
✅ **Backup & Recovery** - Automated backups with retention policies  
✅ **Versioning** - Explicit provider and resource versioning  
✅ **Tagging Strategy** - Consistent tagging across all resources

## Requirements

### Terraform

```hcl
terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
```

### AWS Account Setup

1. Create a dedicated IAM user or role for Terraform
2. Attach appropriate service permissions (see module docs)
3. Configure AWS credentials: `aws configure` or environment variables
4. Ensure account has service quotas for required resources

## Usage

### Initialize Terraform

```bash
terraform init
```

### Plan Changes

```bash
terraform plan -out=tfplan
```

### Apply Changes

```bash
terraform apply tfplan
```

### Environment Separation

Use `.tfvars` files for environment-specific variables:

```bash
# Development
terraform apply -var-file="dev.tfvars"

# Production
terraform apply -var-file="prod.tfvars"
```

## Security Considerations

### Credential Management

- **Never commit secrets** to version control
- Use Terraform variables marked as `sensitive = true`
- Store sensitive values in AWS Secrets Manager or environment variables
- Use AWS SSO or federated authentication

### Network Security

- Deploy resources in private subnets by default
- Use security groups for inbound/outbound rules
- Enable VPC Flow Logs for network monitoring
- Implement network ACLs for additional isolation

### Access Control

- Use IAM roles with minimum required permissions
- Enable MFA for AWS console access
- Audit IAM policies regularly
- Use resource-based policies where applicable

### Data Protection

- Enable encryption at rest (KMS) for all services
- Use encryption in transit (TLS/SSL)
- Enable versioning for stateful resources
- Implement automated backup strategies

## Module Documentation

Each module includes:

- Detailed `README.md` with examples
- Input variables with descriptions and validations
- Output values for resource information
- Required AWS permissions
- Troubleshooting guidance

See individual module directories for complete documentation.

## Contributing

### Development Workflow

1. Create a feature branch: `git checkout -b feature/module-improvement`
2. Make changes following Terraform conventions
3. Run `terraform fmt -recursive` to format code
4. Test module configuration locally
5. Submit pull request with description

### Code Standards

- Use `terraform fmt` for consistent formatting
- Include descriptive variable and output names
- Add validation rules for critical inputs
- Document non-obvious configurations
- Include helpful error messages in validations

### Testing

Before submitting changes:

- Run `terraform validate` on all modules
- Check for syntax errors with `terraform fmt -check`
- Review security implications
- Test with sample `tfvars` configurations

## Troubleshooting

### Common Issues

**"Provider version not available"**

- Run `terraform init -upgrade` to fetch latest compatible version
- Check [AWS Provider Changelog](https://github.com/hashicorp/terraform-provider-aws/releases)

**"AWS credentials not found"**

- Verify AWS credentials: `aws sts get-caller-identity`
- Check environment variables: `$AWS_ACCESS_KEY_ID`, `$AWS_SECRET_ACCESS_KEY`
- Confirm IAM permissions for required services

**"Resource already exists"**

- Check current infrastructure: `terraform state list`
- Use `terraform import` to manage existing resources
- Review AWS Console for unmanaged resources

For module-specific issues, see the module's README file.

## Support

### Getting Help

- Review module-specific documentation in each directory
- Check AWS service documentation links in module comments
- Examine Terraform AWS Provider documentation
- Open an issue for bugs or feature requests

### Reporting Issues

Include:

- Module name and version
- Error message and logs
- Configuration snippet (without secrets)
- Expected vs. actual behavior

## Roadmap

- [x] Aurora DB module with full HA and monitoring
- [x] ECR module with image scanning and replication
- [x] EKS module with managed node groups
- [ ] S3 module with lifecycle and replication policies
- [ ] CloudFront distribution with WAF integration
- [ ] Route53 for DNS and traffic management
- [ ] Secrets Manager module for credential management
- [ ] VPC/Networking module for foundational infrastructure
- [ ] Monitoring module with centralized alerting
- [ ] Cost optimization configurations and examples

## License

This project is provided as-is for infrastructure management. Review licensing terms before use in commercial environments.

## Maintenance

Modules are maintained to support:

- Latest Terraform versions
- AWS provider updates (typically within 30 days of release)
- Security patches and vulnerability fixes
- AWS service deprecations and new features

Regular updates recommended to benefit from:

- Enhanced security controls
- Performance optimizations
- New AWS service capabilities
- Bug fixes and stability improvements

---

**Last Updated:** January 2026  
**Terraform Version:** 1.3+  
**AWS Provider Version:** 5.0+
