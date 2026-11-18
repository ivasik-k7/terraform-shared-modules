# Addresses of the unversioned modules/ecs (commit bbbc35c). Kept forever, so
# a workspace can move from any earlier version. docs/UPGRADE-3.0.md lists
# the moves only the caller can write (autoscaled services, scaling targets).

moved {
  from = aws_ecs_cluster.this
  to   = aws_ecs_cluster.this[0]
}

moved {
  from = aws_ecs_cluster_capacity_providers.this
  to   = aws_ecs_cluster_capacity_providers.this[0]
}

moved {
  from = aws_ecs_capacity_provider.this
  to   = aws_ecs_capacity_provider.ec2
}

# The static service was aws_ecs_service.static in the release that split the
# service four ways (static, static_ignored, autoscaled, autoscaled_ignored).
moved {
  from = aws_ecs_service.static
  to   = aws_ecs_service.this
}

# The infrastructure role's policy attachment on main before 3.0.0 was tagged,
# when it had only the volumes policy.
moved {
  from = aws_iam_role_policy_attachment.infrastructure[0]
  to   = aws_iam_role_policy_attachment.infrastructure["volumes"]
}
