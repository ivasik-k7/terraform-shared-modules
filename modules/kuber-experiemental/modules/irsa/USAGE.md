# IRSA Module – Usage Guide

## Minimal (backward-compatible)

```hcl
module "irsa_my_app" {
  source = "./modules/irsa"

  cluster_name      = "my-cluster"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  role_name         = "my-cluster-irsa-my-app"
  namespace         = "my-app"
  service_account   = "my-app-sa"
  policy_arns       = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
}
```

---

## Multiple ServiceAccounts on one role

```hcl
module "irsa_shared_reader" {
  source = "./modules/irsa"

  cluster_name      = "my-cluster"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  role_name         = "my-cluster-shared-reader"

  service_accounts = [
    { namespace = "team-alpha", service_account = "app-sa" },
    { namespace = "team-beta",  service_account = "app-sa" },
    { namespace = "monitoring", service_account = "prometheus-sa" },
  ]
  policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}
```

---

## Wildcard namespace (all SAs in a namespace)

```hcl
module "irsa_namespace_wildcard" {
  source = "./modules/irsa"

  cluster_name         = "my-cluster"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  role_name            = "my-cluster-data-reader"
  use_wildcard_subject = true   # uses StringLike instead of StringEquals

  service_accounts = [
    { namespace = "data-*", service_account = "*" }
  ]
  policy_arns = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
}
```

---

## Inline policy + permissions boundary

```hcl
module "irsa_scoped" {
  source = "./modules/irsa"

  cluster_name                  = "my-cluster"
  oidc_provider_arn             = module.eks.oidc_provider_arn
  oidc_provider_url             = module.eks.oidc_provider_url
  role_name                     = "my-cluster-scoped-app"
  role_permissions_boundary_arn = "arn:aws:iam::123456789012:policy/OrgBoundary"
  namespace                     = "my-app"
  service_account               = "my-app-sa"
  max_session_duration          = 7200

  inline_policies = {
    dynamodb-access = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
        Resource = "arn:aws:dynamodb:eu-west-1:123456789012:table/my-cluster-*"
      }]
    })
  }
}
```

---

## FinOps tagging

```hcl
module "irsa_finops" {
  source = "./modules/irsa"

  cluster_name      = "prod-cluster"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  role_name         = "prod-cluster-payments-api"
  namespace         = "payments"
  service_account   = "payments-api-sa"

  tags = {
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}
```

---

## Bring-your-own role (create_role = false)

```hcl
module "irsa_external_role" {
  source = "./modules/irsa"

  create_role       = false
  role_arn          = "arn:aws:iam::123456789012:role/ExistingRole"
  cluster_name      = "my-cluster"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = "my-app"
  service_account   = "my-app-sa"
}

# Use the annotation output directly:
resource "kubernetes_service_account" "app" {
  metadata {
    name        = "my-app-sa"
    namespace   = "my-app"
    annotations = module.irsa_external_role.service_account_annotation
  }
}
```

---

## Cross-account trust alongside IRSA

```hcl
module "irsa_cross_account" {
  source = "./modules/irsa"

  cluster_name      = "my-cluster"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  role_name         = "my-cluster-cross-account-app"
  namespace         = "my-app"
  service_account   = "my-app-sa"

  # GitLab CI/CD runner in a different account can also assume this role
  additional_trust_statements = [
    jsonencode({
      Sid    = "GitLabCI"
      Effect = "Allow"
      Principal = { AWS = "arn:aws:iam::987654321098:role/GitLabRunner" }
      Action    = "sts:AssumeRole"
    })
  ]
}
```

---

## Outputs reference

| Output                       | Description                                           |
| ---------------------------- | ----------------------------------------------------- |
| `role_arn`                   | IAM role ARN – use in Helm chart annotations          |
| `role_name`                  | IAM role name                                         |
| `role_unique_id`             | Stable ID for S3 bucket policies                      |
| `oidc_subjects`              | List of trusted `system:serviceaccount:ns:sa` strings |
| `trusted_service_accounts`   | Resolved list of `{namespace, service_account}`       |
| `service_account_annotation` | Ready `eks.amazonaws.com/role-arn` annotation map     |
