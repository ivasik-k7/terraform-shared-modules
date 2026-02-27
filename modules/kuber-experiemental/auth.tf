# ─────────────────────────────────────────────────────────────────────────────
# auth.tf – Cluster authentication
#
# Supports two modes (controlled by var.auth_mode):
#
#   "CONFIG_MAP"   – legacy aws-auth ConfigMap (default; all K8s versions)
#   "API"          – EKS Access Entries API (GA since April 2024; EKS ≥ 1.23)
#   "API_AND_CONFIG_MAP" – both simultaneously during migration
#
# New clusters should use "API". Existing clusters can stay on "CONFIG_MAP"
# indefinitely; change to "API_AND_CONFIG_MAP" to migrate safely, then "API".
# ─────────────────────────────────────────────────────────────────────────────

# ── Cluster authentication mode (must be set on the cluster resource) ─────────
# Injected via a separate aws_eks_cluster_auth_config resource so the main
# cluster resource stays clean and this file owns auth concerns entirely.

# ─────────────────────────────────────────────────────────────────────────────
# PATH A: aws-auth ConfigMap  (auth_mode = CONFIG_MAP or API_AND_CONFIG_MAP)
# ─────────────────────────────────────────────────────────────────────────────

resource "kubernetes_config_map_v1_data" "aws_auth" {
  count = contains(["CONFIG_MAP", "API_AND_CONFIG_MAP"], var.auth_mode) ? 1 : 0

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
  force = true

  data = {
    mapRoles = yamlencode(local.aws_auth_roles_combined)
    mapUsers = length(var.aws_auth_users) > 0 ? yamlencode(var.aws_auth_users) : ""
  }

  depends_on = [aws_eks_cluster.this, module.node_group]
}

# ─────────────────────────────────────────────────────────────────────────────
# PATH B: EKS Access Entries  (auth_mode = API or API_AND_CONFIG_MAP)
#
# Access Entries replace aws-auth with a native AWS API — no Kubernetes
# provider dependency for IAM wiring, and changes are instantly consistent.
# ─────────────────────────────────────────────────────────────────────────────

# Node group roles as EC2_LINUX access entries (replaces the aws-auth node rows)
resource "aws_eks_access_entry" "node_groups" {
  for_each = contains(["API", "API_AND_CONFIG_MAP"], var.auth_mode) ? {
    for k, v in module.node_group : k => v.node_group_role_arn
  } : {}

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "EC2_LINUX"
  tags          = merge(local.common_tags, { "access-entry-type" = "node-group" })
}

# Caller-supplied IAM role access entries
resource "aws_eks_access_entry" "roles" {
  for_each = contains(["API", "API_AND_CONFIG_MAP"], var.auth_mode) ? {
    for r in var.access_entries : r.principal_arn => r
  } : {}

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.value.principal_arn
  type              = each.value.type
  kubernetes_groups = each.value.kubernetes_groups
  tags              = merge(local.common_tags, { "access-entry-principal" = each.value.principal_arn })
}

resource "aws_eks_access_policy_association" "roles" {
  for_each = contains(["API", "API_AND_CONFIG_MAP"], var.auth_mode) ? {
    for r in var.access_entries : r.principal_arn => r
    if r.access_policy_arn != null
  } : {}

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.access_policy_arn

  access_scope {
    type       = each.value.access_scope_type
    namespaces = each.value.access_scope_namespaces
  }

  depends_on = [aws_eks_access_entry.roles]
}
