# ecs-capacity

EC2 capacity for an ECS cluster: any current 2-8 vCPU, 4-32 GiB Intel or AMD
instance type (attribute-based selection, the widest Spot diversification),
one on-demand instance and the rest Spot, protected from scale-in so the ECS
capacity provider decides which instance goes and drains it first.

Hand `autoscaling_group_arn` to `modules/ecs` as
`ec2_capacity_providers[*].auto_scaling_group_arn` with
`managed_termination_protection = "ENABLED"`.

The AMI is the ECS-optimized image from its public SSM parameter, so
`ami_is_pinned` is acknowledged: a new image moves the launch template at the
next apply and instance refresh rolls the fleet. The user data blocks task
access to instance metadata (`ECS_AWSVPC_BLOCK_IMDS`).
