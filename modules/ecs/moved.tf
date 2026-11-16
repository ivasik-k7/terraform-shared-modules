# Addresses of the unversioned modules/ecs (commit bbbc35c). Kept forever, so
# a workspace can move from any earlier version. docs/UPGRADE-1.0.md lists
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
