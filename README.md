# AWS Infrastructure Framework

This repository contains a modularized Infrastructure-as-Code (IaC) framework designed to deploy a full-stack AWS environment. It uses a **composition-based architecture** where core service logic is encapsulated in sub-modules and orchestrated from the root.

## 🏗️ Repository Structure

The repository is organized to allow both independent module development and unified environment orchestration.

```text
.
├── main.tf             # Root Orchestrator: Calls and connects modules
├── variables.tf        # Global variables (Project name, Environment, Region)
├── providers.tf        # Provider configurations (AWS, Helm, Kubernetes)
├── outputs.tf          # Aggregated outputs from all modules
│
├── eks/                # Amazon EKS: Managed Kubernetes Cluster [ACTIVE]
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
│
├── s3/                 # Amazon S3: Static Assets & State [PLANNED]
├── cloudfront/         # Amazon CloudFront: CDN & Edge Security [PLANNED]
└── route53/            # Route53: DNS & Traffic Management [PLANNED]

```

---

## 🛠️ Global Orchestration

The root `main.tf` is used to define how different components interact. For example, the EKS module might require a VPC ID or an S3 bucket ARN for backups.

### Implementation Pattern

```hcl
# root/main.tf

module "eks" {
  source = "./eks"

  cluster_name = "${var.project_name}-${var.environment}"
  vpc_id       = var.vpc_id
  # ...
}

# Future: Passing EKS outputs to CloudFront or S3
# module "s3_assets" {
#   source = "./s3"
#   bucket_name = "${module.eks.cluster_id}-assets"
# }

```

---

## 📦 Service Catalog

| Service                                          | Status            | Key Features                                               |
| ------------------------------------------------ | ----------------- | ---------------------------------------------------------- |
| **[EKS](https://www.google.com/search?q=./eks)** | ✅ **Production** | Managed Node Groups, IRSA roles, KMS encryption, and OIDC. |
| **S3**                                           | 🏗️ _Draft_        | Private buckets, versioning, and cross-region replication. |
| **CloudFront**                                   | 🏗️ _Draft_        | OAI/OAC integration with S3 and WAF protection.            |
| **Route53**                                      | 🏗️ _Draft_        | Public/Private zones and latency-based routing.            |

---

## ⚙️ Core Configuration

### Common Variables

These variables are defined in the root `variables.tf` and passed down to all modules to ensure consistency:

- **`project_name`**: Used as a prefix for all resources.
- **`environment`**: (dev/staging/prod) triggers different scaling and logging logic.
- **`tags`**: A map of standard tags applied to every resource.

### Provider Strategy

We use a centralized `providers.tf` to manage authentication. This ensures that the Kubernetes and Helm providers used for EKS configurations are automatically synced with the cluster created in the same run.

---

## 🚀 Deployment Workflow

1. **Initialize**:

```bash
terraform init
```

2. **Environment Selection**:
   We recommend using Terraform Workspaces or separate `.tfvars` files for different environments.

```bash
terraform plan -var-file="environments/prod.tfvars"
```

3. **Apply**:

```bash
terraform apply -var-file="environments/prod.tfvars"
```

---

## 🔐 Security Standards

Every module within this repository must adhere to the following:

- **Encryption**: All data at rest must be encrypted using AWS KMS.
- **Identity**: Use IAM Roles for Service Accounts (IRSA) for Kubernetes instead of node-level permissions.
- **Networking**: Resources must be deployed in private subnets unless public access is explicitly required.
- **IMDSv2**: Enforce the use of Instance Metadata Service Version 2 for all compute resources.

---

## 📈 Roadmap

- [ ] Integrate **AWS Load Balancer Controller** setup within the EKS module.
- [ ] Add **S3** module with automated lifecycle policies.
- [ ] Implement **CloudFront** with WAF (Web Application Firewall).
- [ ] Create a `networking` module to manage VPCs and Subnets.

---
