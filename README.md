# AWS Infrastructure Terraform Modules

[![Terraform CI](https://github.com/ivasik-k7/terraform-shared-modules/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/ivasik-k7/terraform-shared-modules/actions)
[![Security Scan](https://img.shields.io/badge/Security-Checkov-brightgreen)](https://www.checkov.io/)
[![Cost Control](https://img.shields.io/badge/Costs-Infracost-blueviolet)](https://www.infracost.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5.0-blue)](https://www.terraform.io/)
[![Support](https://img.shields.io/badge/Support-Crypto-orange)](#donations)

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

### 🐳 [ECR](./modules/ecr)

Elastic Container Registry for managing Docker container images.

**Key Features:**

- Private repositories with fine-grained access control
- Image lifecycle policies for cost optimization
- Image scanning with vulnerability detection
- Cross-account/cross-region replication
- Registry pull-through cache

**Use Case:** Container image storage and distribution for EKS, ECS workloads

---

### ☸️ [EKS](./modules/eks)

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

### 📂 [EFS](./modules/efs)

Elastic File System for shared NFS storage across EC2 and containers.

**Key Features:**

- Multi-zone file system with automatic failover
- Optional auto-created security group with configurable access
- Lifecycle policies for cost optimization (Standard → IA → Archive)
- Access points for application-specific mounting
- Cross-region replication for disaster recovery
- Automated backup policies
- Support for both multi-zone and one-zone deployments

**Use Case:** Shared storage for containerized applications, NFS mount targets for EKS/EC2

---

### 📨 [SQS](./modules/sqs)

Simple Queue Service for decoupling microservices and managing distributed message workloads.

**Key Features:**

- **Dual Queue Support:** Provision either **Standard** (best-effort ordering, maximum throughput) or **FIFO** (exactly-once processing, strict ordering) queues.
- **Built-in Dead Letter Queue (DLQ):** Optional automated DLQ creation with configurable `max_receive_count` to isolate and troubleshoot poisonous messages.
- **Cost-Optimized Encryption:** Supports both **SSE-SQS** (free-tier optimized, managed by SQS) and **SSE-KMS** (customer-managed keys) for compliance.
- **Efficiency Controls:** Native support for **Long Polling** (`receive_wait_time_seconds`) to reduce empty receive requests and lower AWS costs.
- **Flexible FIFO Logic:** Configurable `deduplication_scope` and `throughput_limit` (per queue or message group) to scale high-order requirements.
- **Automated Naming:** Intelligently handles the mandatory `.fifo` suffix for both primary and dead-letter queues.
- **Granular Access Control:** Integrated `queue_policy` support for cross-account access and resource-based IAM permissions.

**Use Case:** Decoupling microservices, asynchronous task processing, buffering bursty workloads, and implementing event-driven architectures.

---

### 📨 [SNS](./modules/sns)

Simple Notification Service for pub/sub messaging and mobile notifications.

**Key Features:**

- Standard and FIFO topics
- Delivery status logging
- SMS and Mobile Push support
- Message filtering and fanout patterns
- Encrypted topics

**Use Case:** Event-driven architectures, user notifications, fanout to queues

---

### 🌐 [Network Hub](./modules/network-hub)

Enterprise-grade VPC module for centralized network infrastructure.

**Key Features:**

- Multi-AZ VPC with public/private/db subnets
- Transit Gateway integration ready
- VPC Peering and Endpoints
- Flow Logs and DNS configuration
- Flexible NAT Gateway strategies

**Use Case:** Landing zone network foundation, hub-and-spoke architectures

---

#### Free Tier Tip 💡

To stay under the **1 Million Free Requests** per month, this module is optimized to use **Long Polling (20s)** and **SQS-Managed Encryption**. This combination provides maximum power and security without consuming KMS budget or inflating API request counts.

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
- [x] EFS module with mount targets and lifecycle policies
- [x] SNS module with filtering and delivery logging
- [x] Networking (Network Hub) module for foundational infrastructure
- [ ] S3 module with lifecycle and replication policies
- [ ] CloudFront distribution with WAF integration
- [ ] Route53 for DNS and traffic management
- [ ] Secrets Manager module for credential management
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
