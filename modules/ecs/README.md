# AWS ECS Terraform Module

Production-grade Amazon Elastic Container Service (ECS) module for deploying containerized applications with Fargate, EC2, or hybrid capacity providers. Includes auto-scaling, service discovery, load balancing and monitoring.

## Features

### Core Capabilities

- **Multiple Launch Types**: Fargate, Fargate Spot, EC2, or hybrid capacity provider strategies
- **Auto Scaling**: Target tracking, step scaling, and scheduled scaling policies
- **Service Discovery**: AWS Cloud Map integration for service-to-service communication
- **Load Balancing**: ALB/NLB integration with health checks
- **EFS Integration**: Persistent storage with EFS volume mounts
- **ECS Exec**: Interactive debugging with exec command support
- **Container Insights**: CloudWatch Container Insights for monitoring
- **Deployment Controls**: Circuit breaker, rolling updates, blue/green deployments

### Advanced Features

- **Capacity Providers**: Managed scaling for EC2 instances with ASG integration
- **Task Placement**: Constraints and strategies for optimal task distribution
- **Secrets Management**: Integration with Secrets Manager and Parameter Store
- **IAM Roles**: Separate task execution and task roles with least privilege
- **CloudWatch Logs**: Automatic log group creation with configurable retention
- **Multi-Container Tasks**: Support for sidecar patterns and service meshes

## Quick Start

### Basic Fargate Service

```hcl
module "ecs" {
  source = "./modules/ecs"

  cluster_name             = "my-app-cluster"
  enable_container_insights = true

  services = {
    web = {
      task_definition_family = "web-app"
      task_cpu               = "256"
      task_memory            = "512"
      desired_count          = 2

      container_definitions = [{
        name  = "nginx"
        image = "nginx:latest"

        port_mappings = [{
          container_port = 80
          protocol       = "tcp"
        }]

        environment = [
          { name = "ENV", value = "production" }
        ]
      }]

      network_configuration = {
        subnets          = ["subnet-xxx", "subnet-yyy"]
        security_groups  = ["sg-xxx"]
        assign_public_ip = false
      }
    }
  }

  tags = {
    Environment = "production"
    Project     = "my-app"
  }
}
```

### Fargate with ALB and Auto Scaling

```hcl
module "ecs" {
  source = "./modules/ecs"

  cluster_name = "api-cluster"

  services = {
    api = {
      task_definition_family = "api-service"
      task_cpu               = "512"
      task_memory            = "1024"
      desired_count          = 2

      container_definitions = [{
        name  = "api"
        image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/api:latest"

        port_mappings = [{
          container_port = 8080
        }]

        health_check = {
          command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
          interval    = 30
          timeout     = 5
          retries     = 3
          start_period = 60
        }
      }]

      network_configuration = {
        subnets         = ["subnet-xxx", "subnet-yyy"]
        security_groups = ["sg-xxx"]
      }

      load_balancers = [{
        target_group_arn = "arn:aws:elasticloadbalancing:..."
        container_name   = "api"
        container_port   = 8080
      }]

      health_check_grace_period_seconds = 60

      deployment_configuration = {
        deployment_circuit_breaker = {
          enable   = true
          rollback = true
        }
        maximum_percent         = 200
        minimum_healthy_percent = 100
      }
    }
  }

  auto_scaling_policies = {
    api = {
      service_name = "api"
      min_capacity = 2
      max_capacity = 10

      target_tracking_policies = [{
        name                   = "cpu-scaling"
        target_value           = 70
        predefined_metric_type = "ECSServiceAverageCPUUtilization"
        scale_in_cooldown      = 300
        scale_out_cooldown     = 60
      }]
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### EC2 Capacity Provider with Managed Scaling

```hcl
module "ecs" {
  source = "./modules/ecs"

  cluster_name = "ec2-cluster"

  capacity_providers = {
    ec2 = {
      type                   = "EC2"
      auto_scaling_group_arn = "arn:aws:autoscaling:..."

      managed_scaling = {
        status                    = "ENABLED"
        target_capacity           = 80
        minimum_scaling_step_size = 1
        maximum_scaling_step_size = 100
        instance_warmup_period    = 300
      }

      managed_termination_protection = "ENABLED"
      weight                         = 1
      base                           = 2
    }
  }

  services = {
    worker = {
      task_definition_family = "worker"
      network_mode           = "bridge"
      task_cpu               = "512"
      task_memory            = "1024"
      desired_count          = 5

      requires_compatibilities = ["EC2"]

      capacity_provider_strategy = [{
        capacity_provider = "ec2"
        weight            = 1
        base              = 2
      }]

      container_definitions = [{
        name  = "worker"
        image = "worker:latest"
        cpu   = 512
        memory = 1024
      }]

      network_configuration = {
        subnets = ["subnet-xxx"]
      }

      ordered_placement_strategy = [
        {
          type  = "spread"
          field = "attribute:ecs.availability-zone"
        },
        {
          type  = "binpack"
          field = "memory"
        }
      ]
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### Multi-Container Task with EFS

```hcl
module "ecs" {
  source = "./modules/ecs"

  cluster_name = "app-cluster"

  services = {
    app = {
      task_definition_family = "app-with-sidecar"
      task_cpu               = "512"
      task_memory            = "1024"
      desired_count          = 2

      container_definitions = [
        {
          name  = "app"
          image = "app:latest"

          port_mappings = [{
            container_port = 8080
          }]

          mount_points = [{
            source_volume  = "efs-storage"
            container_path = "/data"
            read_only      = false
          }]

          depends_on = [{
            container_name = "log-router"
            condition      = "START"
          }]
        },
        {
          name      = "log-router"
          image     = "fluent/fluent-bit:latest"
          essential = false
        }
      ]

      volumes = [{
        name = "efs-storage"

        efs_volume_configuration = {
          file_system_id     = "fs-xxx"
          root_directory     = "/app-data"
          transit_encryption = "ENABLED"

          authorization_config = {
            access_point_id = "fsap-xxx"
            iam             = "ENABLED"
          }
        }
      }]

      network_configuration = {
        subnets         = ["subnet-xxx", "subnet-yyy"]
        security_groups = ["sg-xxx"]
      }
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### Service Discovery with Cloud Map

```hcl
module "ecs" {
  source = "./modules/ecs"

  cluster_name = "microservices-cluster"

  services = {
    backend = {
      task_definition_family = "backend"
      task_cpu               = "256"
      task_memory            = "512"
      desired_count          = 3

      container_definitions = [{
        name  = "backend"
        image = "backend:latest"

        port_mappings = [{
          container_port = 8080
        }]
      }]

      network_configuration = {
        subnets         = ["subnet-xxx", "subnet-yyy"]
        security_groups = ["sg-xxx"]
      }

      service_registries = [{
        registry_arn   = "arn:aws:servicediscovery:..."
        container_name = "backend"
        container_port = 8080
      }]
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### Fargate Spot with Cost Optimization

```hcl
module "ecs" {
  source = "./modules/ecs"

  cluster_name = "batch-cluster"

  capacity_providers = {
    FARGATE = {
      type   = "FARGATE"
      weight = 1
      base   = 0
    }
    FARGATE_SPOT = {
      type   = "FARGATE_SPOT"
      weight = 4
      base   = 0
    }
  }

  services = {
    batch = {
      task_definition_family = "batch-processor"
      task_cpu               = "1024"
      task_memory            = "2048"
      desired_count          = 10

      capacity_provider_strategy = [
        {
          capacity_provider = "FARGATE_SPOT"
          weight            = 4
          base              = 0
        },
        {
          capacity_provider = "FARGATE"
          weight            = 1
          base              = 2
        }
      ]

      container_definitions = [{
        name  = "processor"
        image = "batch-processor:latest"
      }]

      network_configuration = {
        subnets = ["subnet-xxx", "subnet-yyy"]
      }
    }
  }

  tags = {
    Environment = "production"
    CostCenter  = "batch-processing"
  }
}
```

### Secrets and Environment Variables

```hcl
module "ecs" {
  source = "./modules/ecs"

  cluster_name = "secure-app-cluster"

  services = {
    app = {
      task_definition_family = "secure-app"
      task_cpu               = "256"
      task_memory            = "512"
      desired_count          = 2

      container_definitions = [{
        name  = "app"
        image = "app:latest"

        environment = [
          { name = "APP_ENV", value = "production" },
          { name = "LOG_LEVEL", value = "info" }
        ]

        secrets = [
          {
            name      = "DB_PASSWORD"
            valueFrom = "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-password"
          },
          {
            name      = "API_KEY"
            valueFrom = "arn:aws:ssm:us-east-1:123456789012:parameter/api-key"
          }
        ]
      }]

      network_configuration = {
        subnets         = ["subnet-xxx"]
        security_groups = ["sg-xxx"]
      }
    }
  }

  task_execution_role_policies = [
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  ]

  tags = {
    Environment = "production"
  }
}
```

## Inputs

| Name                         | Description                                | Type              | Default              | Required |
| ---------------------------- | ------------------------------------------ | ----------------- | -------------------- | -------- |
| cluster_name                 | Name of the ECS cluster                    | string            | -                    | yes      |
| enable_container_insights    | Enable CloudWatch Container Insights       | bool              | true                 | no       |
| cluster_configuration        | Execute command configuration              | object            | null                 | no       |
| capacity_providers           | Map of capacity provider configurations    | map(object)       | Fargate/Fargate Spot | no       |
| services                     | Map of ECS service configurations          | map(object)       | {}                   | no       |
| auto_scaling_policies        | Map of auto scaling policies               | map(object)       | {}                   | no       |
| task_execution_role_arn      | ARN of task execution role                 | string            | null                 | no       |
| create_task_execution_role   | Create default task execution role         | bool              | true                 | no       |
| task_execution_role_policies | Additional IAM policies for task execution | list(string)      | []                   | no       |
| task_role_policies           | IAM policies for task roles                | map(list(string)) | {}                   | no       |
| create_cloudwatch_log_groups | Create CloudWatch log groups               | bool              | true                 | no       |
| log_retention_in_days        | Log retention in days                      | number            | 7                    | no       |
| log_kms_key_id               | KMS key for log encryption                 | string            | null                 | no       |
| tags                         | Common tags for all resources              | map(string)       | {}                   | no       |

## Outputs

| Name                    | Description                       |
| ----------------------- | --------------------------------- |
| cluster_id              | ID of the ECS cluster             |
| cluster_arn             | ARN of the ECS cluster            |
| cluster_name            | Name of the ECS cluster           |
| service_ids             | Map of ECS service IDs            |
| service_arns            | Map of ECS service ARNs           |
| task_definition_arns    | Map of task definition ARNs       |
| task_execution_role_arn | ARN of task execution role        |
| task_role_arns          | Map of task role ARNs             |
| log_group_names         | Map of CloudWatch log group names |
| autoscaling_target_ids  | Map of auto scaling target IDs    |
| summary                 | Summary of cluster and services   |

## Best Practices

### Performance

- Use Fargate Spot for fault-tolerant workloads (up to 70% cost savings)
- Enable Container Insights for detailed metrics
- Configure appropriate CPU and memory reservations
- Use task placement strategies for optimal resource utilization
- Implement health checks with appropriate grace periods

### Security

- Never hardcode secrets in container definitions
- Use Secrets Manager or Parameter Store for sensitive data
- Enable encryption in transit for EFS volumes
- Use separate IAM roles for task execution and task runtime
- Deploy services in private subnets
- Enable ECS Exec only when needed for debugging

### Cost Optimization

- Use Fargate Spot for non-critical workloads
- Configure auto-scaling to match demand
- Set appropriate log retention periods
- Use capacity provider strategies to balance cost and availability
- Monitor and right-size task CPU/memory allocations

### Monitoring

- Enable Container Insights for cluster-level metrics
- Configure CloudWatch alarms for service health
- Use structured logging with JSON format
- Implement distributed tracing with X-Ray
- Monitor task placement and resource utilization

### Deployment

- Enable deployment circuit breaker with rollback
- Use blue/green deployments for zero-downtime updates
- Configure appropriate health check grace periods
- Test deployments in staging environment first
- Use task definition revisions for rollback capability

## Free Tier Limits

AWS Free Tier for ECS (12 months):

- **Fargate**: No free tier (pay per vCPU-hour and GB-hour)
- **EC2 Launch Type**: Free (pay only for EC2 instances)
- **CloudWatch Logs**: 5 GB ingestion, 5 GB storage per month
- **CloudWatch Metrics**: 10 custom metrics, 10 alarms

### Free Tier Optimized Configuration

```hcl
module "ecs" {
  source = "./modules/ecs"

  cluster_name              = "free-tier-cluster"
  enable_container_insights = false  # Reduces CloudWatch costs

  services = {
    app = {
      task_definition_family = "app"
      task_cpu               = "256"   # Minimum Fargate size
      task_memory            = "512"   # Minimum Fargate size
      desired_count          = 1       # Single task

      requires_compatibilities = ["EC2"]  # Use EC2 free tier instances
      launch_type              = "EC2"

      container_definitions = [{
        name  = "app"
        image = "app:latest"
      }]

      network_configuration = {
        subnets = ["subnet-xxx"]
      }
    }
  }

  create_cloudwatch_log_groups = true
  log_retention_in_days        = 1  # Minimum retention

  tags = {
    Environment = "dev"
  }
}
```

## Pricing

### Fargate Pricing (us-east-1)

- **vCPU**: $0.04048 per vCPU per hour
- **Memory**: $0.004445 per GB per hour

**Example**: 1 task (0.25 vCPU, 0.5 GB) running 24/7:

- vCPU: 0.25 × $0.04048 × 730 hours = $7.39/month
- Memory: 0.5 × $0.004445 × 730 hours = $1.62/month
- **Total**: ~$9/month per task

### Fargate Spot Pricing

- **70% discount** compared to Fargate on-demand
- Same example: ~$2.70/month per task

### EC2 Launch Type

- Pay only for EC2 instances (t3.micro eligible for free tier)
- No additional ECS charges

## IAM Permissions

### Terraform Deployment

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:*",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "elasticloadbalancing:DescribeTargetGroups",
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:PassRole",
        "logs:CreateLogGroup",
        "logs:PutRetentionPolicy",
        "application-autoscaling:*",
        "cloudwatch:PutMetricAlarm"
      ],
      "Resource": "*"
    }
  ]
}
```

### Task Execution Role (Managed by Module)

- `AmazonECSTaskExecutionRolePolicy` (default)
- Pull images from ECR
- Write logs to CloudWatch
- Access Secrets Manager/Parameter Store

### Task Role (Application-Specific)

Configure via `task_role_policies` variable for application needs:

- S3 access
- DynamoDB access
- SQS/SNS access
- Custom permissions

## Troubleshooting

### Service Won't Start

**Symptoms**: Tasks fail to start or immediately stop

**Solutions**:

- Check CloudWatch logs for container errors
- Verify IAM role permissions for ECR, Secrets Manager
- Ensure security groups allow required traffic
- Verify subnet has internet access (for Fargate)
- Check task CPU/memory limits

### Tasks Failing Health Checks

**Symptoms**: Tasks start but fail ALB health checks

**Solutions**:

- Increase `health_check_grace_period_seconds`
- Verify security group allows ALB → ECS traffic
- Check application health endpoint
- Review container health check configuration
- Ensure application starts within grace period

### Auto Scaling Not Working

**Symptoms**: Service doesn't scale despite high CPU/memory

**Solutions**:

- Verify CloudWatch metrics are being published
- Check auto scaling policy configuration
- Ensure service has capacity to scale (max_capacity)
- Review scale-in/scale-out cooldown periods
- Check IAM permissions for Application Auto Scaling

### ECS Exec Not Working

**Symptoms**: Cannot execute commands in running tasks

**Solutions**:

- Enable `enable_execute_command` on service
- Verify task role has `ssmmessages` permissions
- Ensure SSM Session Manager plugin is installed locally
- Check security group allows outbound HTTPS (443)

### High Costs

**Symptoms**: Unexpected ECS charges

**Solutions**:

- Use Fargate Spot for fault-tolerant workloads
- Right-size task CPU and memory allocations
- Configure auto-scaling to scale down during low traffic
- Reduce log retention periods
- Disable Container Insights in non-production
- Use EC2 launch type with Reserved Instances

## Requirements

- Terraform >= 1.3.0
- AWS Provider >= 5.0
- VPC with subnets configured
- Security groups for ECS tasks
- ECR repository or public container images

## Related AWS Services

- **ECR**: Container image registry
- **ALB/NLB**: Load balancing
- **Cloud Map**: Service discovery
- **EFS**: Persistent storage
- **Secrets Manager**: Secrets management
- **CloudWatch**: Monitoring and logging
- **X-Ray**: Distributed tracing

## Examples

See the [examples](../../examples/ecs/) directory for complete working examples:

- Basic Fargate service
- Fargate with ALB and auto-scaling
- EC2 capacity provider
- Multi-container tasks with EFS
- Service discovery
- Fargate Spot cost optimization

## License

This module is provided as-is under the MIT License.
