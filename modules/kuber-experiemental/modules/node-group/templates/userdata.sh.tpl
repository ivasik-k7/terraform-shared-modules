#!/bin/bash
set -euo pipefail

# ── Pre-bootstrap hook ────────────────────────────────────────────────────────
# Injected via var.pre_bootstrap_user_data
%{ if pre_bootstrap_user_data != "" ~}
# --- BEGIN pre-bootstrap ---
${pre_bootstrap_user_data}
# --- END pre-bootstrap ---
%{ endif ~}

# ── EKS bootstrap ─────────────────────────────────────────────────────────────
/etc/eks/bootstrap.sh '${cluster_name}' ${bootstrap_extra_args}

# ── Post-bootstrap hook ───────────────────────────────────────────────────────
# Injected via var.post_bootstrap_user_data
%{ if post_bootstrap_user_data != "" ~}
# --- BEGIN post-bootstrap ---
${post_bootstrap_user_data}
# --- END post-bootstrap ---
%{ endif ~}
