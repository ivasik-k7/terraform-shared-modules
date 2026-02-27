# ─────────────────────────────────────────────────────────────────────────────
# data.tf
# All AWS data sources are declared here — one canonical location.
# Centralising prevents "duplicate data source" errors when the module grows.
# ─────────────────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
