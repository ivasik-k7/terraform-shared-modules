################################################################################
# Development Environment Example
################################################################################

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"

}

# terraform {
#   required_version = ">= 1.6.0"

#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = ">= 5.0"
#     }
#   }
# }

# provider "aws" {
#   region = var.region
# }

################################################################################
# Data Sources
################################################################################

# data "aws_vpc" "default" {
#   default = true
# }

# data "aws_subnets" "default" {
#   filter {
#     name   = "vpc-id"
#     values = [data.aws_vpc.default.id]
#   }
# }

################################################################################
# Project Configuration - archon-hub
################################################################################

locals {
  project_name     = "archon-hub"
  environment      = "dev"
  tfe_organization = "citadel-hub"

  name_prefix = "${local.project_name}-${local.environment}"

  ecr_repository_name = "${local.name_prefix}-master-application"

  lifecycle_rules = [
    {
      rule_priority    = 1
      description      = "Keep last 10 production images"
      tag_status       = "tagged"
      tag_prefix_list  = ["prod-", "production-"]
      tag_pattern_list = []
      count_type       = "imageCountMoreThan"
      count_number     = 10
      action_type      = "expire"
    },
    {
      rule_priority    = 2
      description      = "Expire dev images older than 7 days"
      tag_status       = "tagged"
      tag_prefix_list  = ["dev-", "test-"]
      tag_pattern_list = []
      count_type       = "sinceImagePushed"
      count_number     = 7
      count_unit       = "days"
      action_type      = "expire"
    },
    {
      rule_priority    = 3
      description      = "Expire untagged images older than 14 days"
      tag_status       = "untagged"
      tag_prefix_list  = []
      tag_pattern_list = []
      count_type       = "sinceImagePushed"
      count_number     = 14
      count_unit       = "days"
      action_type      = "expire"
    },
    {
      rule_priority    = 4
      description      = "Keep last 30 images (catch-all)"
      tag_status       = "any"
      tag_prefix_list  = []
      tag_pattern_list = []
      count_type       = "imageCountMoreThan"
      count_number     = 30
      action_type      = "expire"
    }
  ]

  base_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
    CreatedDate = "2026-01-08"
    CostCenter  = "engineering"
  }

  ecr_tags = merge(
    local.base_tags,
    {
      Service     = "ecr"
      Application = "container-registry"
      Team        = "platform"
      Owner       = "devops-team"
    }
  )

  enable_image_scanning = true      # FREE: 1 basic scan per push
  enable_logging        = false     # COST: Avoid CloudWatch charges
  enable_replication    = false     # COST: Avoid data transfer charges
  encryption_type       = "AES256"  # FREE: AWS-managed encryption
  image_tag_mutability  = "MUTABLE" # FREE: Reuse tags, save storage
  force_delete          = true      # DEV: Allow easy cleanup
}

################################################################################
# ECR Module - archon-hub Container Registry
################################################################################

# module "ecr" {
#   count  = 0
#   source = "./modules/ecr"

#   repository_name      = local.ecr_repository_name
#   image_tag_mutability = local.image_tag_mutability
#   force_delete         = local.force_delete

#   scan_on_push = local.enable_image_scanning

#   encryption_type = local.encryption_type
#   kms_key_arn     = null

#   enable_lifecycle_policy = true
#   lifecycle_rules         = local.lifecycle_rules

#   create_repository_policy     = true
#   repository_policy_statements = [] # Use default account access
#   allowed_principals           = [] # No cross-account = no data transfer costs
#   allowed_pull_principals      = []

#   enable_replication = local.enable_replication
#   replication_rules  = []

#   enable_logging                = local.enable_logging
#   cloudwatch_log_group_name     = null
#   cloudwatch_log_retention_days = 7
#   cloudwatch_kms_key_id         = null

#   enable_registry_scanning = false
#   registry_scan_type       = "BASIC"
#   registry_scanning_rules  = []

#   pull_through_cache_rules = {}

#   enable_registry_policy = false
#   registry_policy_json   = null

#   tags        = local.ecr_tags
#   common_tags = local.base_tags
# }

# ################################################################################
# # Aurora Module - archon-hub Database Cluster
# ################################################################################

# module "aurora" {
#   count              = 0
#   source             = "./modules/aurora"
#   cluster_identifier = "${local.name_prefix}-db-cluster"
#   engine             = "aurora-postgresql"
#   engine_version     = "14.6"

#   instances = {
#     "writer" = {
#       instance_class      = "db.t3.medium"
#       promotion_tier      = 0
#       publicly_accessible = false
#     }
#   }

#   master_username = "archonadmin"
#   master_password = "ChangeMe12345!"

#   storage_encrypted       = true
#   backup_retention_period = 1
#   skip_final_snapshot     = true
#   deletion_protection     = false

#   monitoring_interval             = 0
#   performance_insights_enabled    = false
#   enabled_cloudwatch_logs_exports = []

#   create_security_group = true
#   allowed_cidr_blocks   = ["10.0.0.0/16"]

#   vpc_id     = data.aws_vpc.default.id
#   subnet_ids = data.aws_subnets.default.ids

#   tags = local.base_tags
# }

# ################################################################################
# # EFS
# ################################################################################

# module "efs" {
#   count  = 0
#   source = "./modules/efs"

#   name             = "${local.name_prefix}-file-system"
#   encrypted        = true
#   throughput_mode  = "bursting"
#   performance_mode = "generalPurpose"

#   vpc_id             = data.aws_vpc.default.id
#   subnet_ids         = data.aws_subnets.default.ids
#   security_group_ids = []

#   create_security_group = true
#   allowed_cidr_blocks   = ["10.0.0.0/16"]

#   enable_backup_policy = true

#   lifecycle_policy_transition_to_ia                    = "AFTER_30_DAYS"
#   lifecycle_policy_transition_to_primary_storage_class = "AFTER_1_ACCESS"

#   tags = merge(
#     local.base_tags,
#     {
#       Service     = "efs"
#       Application = "file-storage"
#       Team        = "platform"
#       Owner       = "devops-team"
#     }
#   )

# }

# ################################################################################
# # SQS
# ################################################################################

# module "sqs" {
#   count  = 0
#   source = "./modules/sqs"

#   name = "${local.name_prefix}-main-queue"

#   create_dlq                    = true
#   message_retention_seconds     = 1209600
#   dlq_message_retention_seconds = 1209600

#   max_receive_count         = 5
#   receive_wait_time_seconds = 20
#   fifo_queue                = false

#   sqs_managed_sse_enabled = true
#   kms_master_key_id       = null

#   tags = merge(
#     local.base_tags,
#     {
#       Service     = "sqs"
#       Application = "message-queue"
#       Team        = "platform"
#       Owner       = "devops-team"
#     }
#   )
# }

# ################################################################################
# # SNS
# ################################################################################

# module "sns" {
#   count  = 0
#   source = "./modules/sns"

#   name         = "${local.name_prefix}-notifications"
#   display_name = "Archon Hub Notifications"

#   subscriptions = [
#     {
#       protocol = "email"
#       endpoint = "kovtun.ivan@proton.me"
#     }
#   ]

#   message_templates = {
#     welcome = {
#       subject         = "🚀 Welcome to the Archon Platform!"
#       message         = "<!DOCTYPE html><html><head><meta charset='utf-8'><style>body{font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;margin:0;padding:0;background:#0a0a0a;color:#e0e0e0}.container{max-width:600px;margin:0 auto;background:linear-gradient(135deg,#1a1a2e 0%,#16213e 100%);border-radius:12px;overflow:hidden;box-shadow:0 20px 40px rgba(0,0,0,0.3)}.header{background:linear-gradient(90deg,#0f3460 0%,#e94560 100%);padding:40px 30px;text-align:center}.logo{font-size:32px;font-weight:bold;color:#fff;margin-bottom:10px;text-shadow:2px 2px 4px rgba(0,0,0,0.5)}.tagline{color:#b8c6db;font-size:16px;opacity:0.9}.content{padding:40px 30px}.welcome-text{font-size:24px;color:#fff;margin-bottom:20px;text-align:center}.message{font-size:16px;line-height:1.6;color:#b8c6db;margin-bottom:30px}.features{background:#1e1e2e;border-radius:8px;padding:25px;margin:20px 0}.feature-item{display:flex;align-items:center;margin:15px 0;color:#e0e0e0}.feature-icon{width:20px;height:20px;margin-right:15px;color:#e94560}.cta{text-align:center;margin:30px 0}.cta-button{display:inline-block;background:linear-gradient(90deg,#e94560 0%,#0f3460 100%);color:#fff;padding:15px 30px;text-decoration:none;border-radius:25px;font-weight:bold;font-size:16px;transition:transform 0.3s ease;box-shadow:0 4px 15px rgba(233,69,96,0.3)}.cta-button:hover{transform:translateY(-2px)}.footer{background:#0f0f0f;padding:20px 30px;text-align:center;border-top:1px solid #333}.footer-text{color:#666;font-size:14px}</style></head><body><div class='container'><div class='header'><div class='logo'>⚡ ARCHON</div><div class='tagline'>Next-Generation Cloud Platform</div></div><div class='content'><div class='welcome-text'>Welcome to the Future! 🎯</div><div class='message'>You've successfully joined the <strong>Archon Platform</strong> – where cutting-edge technology meets seamless cloud infrastructure. Get ready to experience the next level of development and deployment.</div><div class='features'><div class='feature-item'><span class='feature-icon'>🚀</span><span>Lightning-fast deployments with zero downtime</span></div><div class='feature-item'><span class='feature-icon'>🔒</span><span>Enterprise-grade security and encryption</span></div><div class='feature-item'><span class='feature-icon'>📊</span><span>Real-time monitoring and analytics</span></div><div class='feature-item'><span class='feature-icon'>⚡</span><span>Auto-scaling infrastructure that adapts to your needs</span></div></div><div class='cta'><a href='#' class='cta-button'>Explore Your Dashboard</a></div><div class='message'>Your journey into the future of cloud computing starts now. We're excited to have you aboard!</div></div><div class='footer'><div class='footer-text'>© 2026 Archon Platform | Powered by Advanced Infrastructure</div></div></div></body></html>"
#       default_message = "🚀 Welcome to the Archon Platform! You've successfully joined our next-generation cloud platform. Get ready to experience lightning-fast deployments, enterprise-grade security, and auto-scaling infrastructure. Your journey into the future starts now!"
#     }
#     alert = {
#       subject         = "Archon Hub Alert"
#       message         = "<h2>System Alert</h2><p>{{message}}</p><p>Time: {{timestamp}}</p>"
#       default_message = "System Alert: {{message}}"
#     }
#   }

#   tags = merge(
#     local.base_tags,
#     {
#       Service     = "sns"
#       Application = "notifications"
#       Team        = "platform"
#       Owner       = "devops-team"
#     }
#   )
# }

# ################################################################################
# # Network-Hub Module - archon-hub VPC and Networking
# ################################################################################


# module "network-hub" {
#   count  = 0
#   source = "./modules/network-hub"

#   name        = local.project_name
#   environment = local.environment

#   vpc_id = data.aws_vpc.default.id

#   public_subnet_ids = data.aws_subnets.default.ids

#   create_internet_gateway = false

#   security_groups = {
#     web_tier = {
#       description = "Web tier security group"
#       ingress_rules = [
#         {
#           description = "HTTP from anywhere"
#           from_port   = 80
#           to_port     = 80
#           protocol    = "tcp"
#           cidr_blocks = ["0.0.0.0/0"]
#         },
#         {
#           description = "HTTPS from anywhere"
#           from_port   = 443
#           to_port     = 443
#           protocol    = "tcp"
#           cidr_blocks = ["0.0.0.0/0"]
#         }
#       ]
#     }
#   }

#   vpc_endpoints = {
#     s3 = {
#       service_name      = "com.amazonaws.${var.region}.s3"
#       vpc_endpoint_type = "Gateway"
#       route_table_ids   = [data.aws_vpc.default.main_route_table_id]
#     }
#   }
# }


# =========================================
# TFE-HUB MODULE RESOURCES
# =========================================

variable "TFE_TOKEN" {
  sensitive = true
}

provider "tfe" {
  hostname = "app.terraform.io"
}

terraform {
  cloud {

    organization = "citadel-hub"

    workspaces {
      name = "foundation-cli"
    }
  }
}

module "tfe_config" {
  source = "./modules/tfe-hub"

  organization_name = local.tfe_organization

  # ------------------------------------------
  # PROJECTS
  # ------------------------------------------
  projects = {
    citadel-forgery = {
      name        = "Citadel-Forgery"
      description = "Project for managing the Citadel-Forgery application infrastructure"
    }
  }

  # ------------------------------------------
  # WORKSPACES
  # ------------------------------------------
  workspaces = {
    archon_rabbit_dev_networking = {
      name        = "archon-rabbit-dev-networking"
      description = "Development networking workspace for Archon-Rabbit - manages VPC, subnets, route tables, security groups"
      project_key = "citadel-forgery"

      execution_mode      = "remote"
      auto_apply          = false
      allow_destroy_plan  = true
      speculative_enabled = true
      terraform_version   = "~> 1.6"
      assessments_enabled = false

      # VCS configuration
      # vcs_repo = {
      #   identifier     = "your-organization/archon-rabbit-infrastructure"
      #   branch         = "main"
      #   oauth_token_id = "ot-xxxxxxxxxxxxx" # Replace with your OAuth token ID

      #   # File triggers for networking directory only
      #   tags_regex                 = null
      #   github_app_installation_id = null
      # }

      file_triggers_enabled = true
      trigger_prefixes      = ["networking/", "common/"]
      trigger_patterns      = ["*.tf", "*.tfvars"]

      working_directory = "networking"

      tags = ["archon-rabbit", "development", "networking", "aws", "platform-team"]

      global_remote_state       = true
      remote_state_consumer_ids = [] # Can add workspace IDs that need to consume this state

      variables = {
        environment = {
          key         = "environment"
          value       = "dev"
          category    = "terraform"
          description = "Deployment environment"
          sensitive   = false
          hcl         = false
        }
        aws_region = {
          key         = "aws_region"
          value       = "us-east-1"
          category    = "terraform"
          description = "AWS region for deployment"
          sensitive   = false
          hcl         = false
        }
        vpc_cidr = {
          key         = "vpc_cidr"
          value       = "10.0.0.0/16"
          category    = "terraform"
          description = "VPC CIDR block"
          sensitive   = false
          hcl         = false
        }
        private_subnet_count = {
          key         = "private_subnet_count"
          value       = "3"
          category    = "terraform"
          description = "Number of private subnets"
          sensitive   = false
          hcl         = false
        }
      }

      # notifications = {
      #   networking_failures = {
      #     name             = "Networking Workspace Failures"
      #     destination_type = "slack"
      #     enabled          = true
      #     url              = "xyu"
      #     triggers         = ["run:errored", "run:needs_attention"]
      #   }
      #   networking_applied = {
      #     name             = "Networking Workspace Applied"
      #     destination_type = "slack"
      #     enabled          = true
      #     url              = "xyu"
      #     triggers         = ["run:applied"]
      #   }
      # }

      run_triggers = {
        trigger_compute = "archon_rabbit_dev_compute"
      }

      # variable_set_keys = ["archon_rabbit_global", "archon_rabbit_aws_creds", "archon_rabbit_dev_env"]
    }

    archon_rabbit_dev_compute = {
      name        = "archon-rabbit-dev-compute"
      description = "Development compute workspace for Archon-Rabbit - manages EC2 instances, ECS clusters, auto-scaling"
      project_key = "citadel-forgery"

      execution_mode         = "remote"
      auto_apply             = true
      auto_apply_run_trigger = true
      terraform_version      = "~> 1.6"
      assessments_enabled    = false

      # vcs_repo = {
      #   identifier     = "your-organization/archon-rabbit-infrastructure"
      #   branch         = "develop" # Different branch for compute
      #   oauth_token_id = "ot-xxxxxxxxxxxxx"
      # }

      file_triggers_enabled = true
      trigger_prefixes      = ["compute/", "common/"]

      working_directory = "compute"

      tags = ["archon-rabbit", "development", "compute", "ec2", "ecs", "auto-scaling"]

      # Variables for compute workspace
      variables = {
        instance_type = {
          key         = "instance_type"
          value       = "t3.medium"
          category    = "terraform"
          description = "EC2 instance type"
          sensitive   = false
        }
        min_size = {
          key         = "min_size"
          value       = "2"
          category    = "terraform"
          description = "Minimum number of instances"
          sensitive   = false
        }
        max_size = {
          key         = "max_size"
          value       = "5"
          category    = "terraform"
          description = "Maximum number of instances"
          sensitive   = false
        }
        ssh_key_name = {
          key         = "ssh_key_name"
          value       = "archon-rabbit-dev-key"
          category    = "terraform"
          description = "SSH key pair name"
          sensitive   = false
        }
      }

      # variable_set_keys = ["archon_rabbit_global", "archon_rabbit_aws_creds", "archon_rabbit_dev_env", "archon_rabbit_compute_config"]

      # notifications = {
      #   compute_alerts = {
      #     name             = "Compute Workspace Alerts"
      #     destination_type = "microsoft-teams"
      #     enabled          = true
      #     url              = "https://outlook.office.com/webhook/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX@XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX/IncomingWebhook/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
      #     triggers         = ["run:errored", "run:needs_attention", "run:applied"]
      #   }
      # }
    }

    archon_rabbit_dev_databases = {
      name        = "archon-rabbit-dev-databases"
      description = "Development databases workspace for Archon-Rabbit - manages RDS, ElastiCache, DynamoDB"
      project_key = "citadel-forgery"

      execution_mode         = "remote"
      auto_apply             = true
      auto_apply_run_trigger = true
      terraform_version      = "~> 1.6"
      assessments_enabled    = false

      # vcs_repo = {
      #   identifier     = "your-organization/archon-rabbit-infrastructure"
      #   branch         = "main"
      #   oauth_token_id = "ot-xxxxxxxxxxxxx"
      # }

      file_triggers_enabled = false # Manual triggers only for databases

      working_directory = "databases"

      tags = ["archon-rabbit", "development", "databases", "rds", "redis", "dynamodb", "sensitive"]

      variables = {
        db_instance_class = {
          key         = "db_instance_class"
          value       = "db.t3.small"
          category    = "terraform"
          description = "RDS instance class"
          sensitive   = false
        }
        db_allocated_storage = {
          key         = "db_allocated_storage"
          value       = "20"
          category    = "terraform"
          description = "RDS allocated storage in GB"
          sensitive   = false
        }
        db_master_password = {
          key         = "db_master_password"
          value       = "changeme123" # In production, this should be a sensitive variable
          category    = "terraform"
          description = "RDS master password"
          sensitive   = true
        }
        redis_node_type = {
          key         = "redis_node_type"
          value       = "cache.t3.micro"
          category    = "terraform"
          description = "ElastiCache node type"
          sensitive   = false
        }
      }

      structured_run_output_enabled = true

      # variable_set_keys = ["archon_rabbit_global", "archon_rabbit_aws_creds", "archon_rabbit_dev_env", "archon_rabbit_db_config"]

      # Notifications
      # notifications = {
      #   db_changes = {
      #     name             = "Database Changes"
      #     destination_type = "email"
      #     enabled          = true
      #     triggers         = ["run:planned_and_finished", "run:applied", "run:errored"]
      #     email_user_ids   = ["user-xxxxxxxxxxxxx", "user-yyyyyyyyyyyyy"] # Replace with actual user IDs
      #   }
      # }
    }
  }


  # teams = {
  #   archon_rabbit_admins = {
  #     name        = "archon-rabbit-admins"
  #     description = "Administrators for Archon-Rabbit project"
  #     visibility  = "organization"

  #     organization_access = {
  #       manage_policies         = true
  #       manage_policy_overrides = true
  #       manage_workspaces       = true
  #       manage_vcs_settings     = true
  #       manage_providers        = true
  #       manage_modules          = true
  #       manage_run_tasks        = true
  #       manage_projects         = true
  #       manage_membership       = false # Only org admins manage membership
  #       read_workspaces         = true
  #       read_projects           = true
  #     }

  #     sso_team_id = null # Set if using SSO team synchronization
  #   }

  #   archon_rabbit_developers = {
  #     name        = "archon-rabbit-developers"
  #     description = "Development team for Archon-Rabbit"
  #     visibility  = "organization"

  #     organization_access = {
  #       manage_policies         = false
  #       manage_policy_overrides = false
  #       manage_workspaces       = false
  #       manage_vcs_settings     = false
  #       manage_providers        = false
  #       manage_modules          = false
  #       manage_run_tasks        = false
  #       manage_projects         = false
  #       manage_membership       = false
  #       read_workspaces         = true
  #       read_projects           = true
  #     }

  #     sso_team_id = null # Example SSO team ID
  #   }

  #   archon_rabbit_network_team = {
  #     name        = "archon-rabbit-network-team"
  #     description = "Network specialists for Archon-Rabbit"
  #     visibility  = "secret" # Only visible to organization owners and team maintainers

  #     organization_access = {
  #       manage_policies         = false
  #       manage_policy_overrides = false
  #       manage_workspaces       = false
  #       manage_vcs_settings     = false
  #       manage_providers        = false
  #       manage_modules          = false
  #       manage_run_tasks        = false
  #       manage_projects         = false
  #       manage_membership       = false
  #       read_workspaces         = true
  #       read_projects           = true
  #     }
  #   }

  #   archon_rabbit_dba = {
  #     name        = "archon-rabbit-dba"
  #     description = "Database administrators for Archon-Rabbit"
  #     visibility  = "secret"

  #     organization_access = {
  #       manage_policies         = false
  #       manage_policy_overrides = false
  #       manage_workspaces       = false
  #       manage_vcs_settings     = false
  #       manage_providers        = false
  #       manage_modules          = false
  #       manage_run_tasks        = false
  #       manage_projects         = false
  #       manage_membership       = false
  #       read_workspaces         = true
  #       read_projects           = true
  #     }
  #   }

  #   archon_rabbit_qa = {
  #     name        = "archon-rabbit-qa"
  #     description = "Quality assurance team for Archon-Rabbit"
  #     visibility  = "organization"

  #     organization_access = {
  #       manage_policies         = false
  #       manage_policy_overrides = false
  #       manage_workspaces       = false
  #       manage_vcs_settings     = false
  #       manage_providers        = false
  #       manage_modules          = false
  #       manage_run_tasks        = false
  #       manage_projects         = false
  #       manage_membership       = false
  #       read_workspaces         = true
  #       read_projects           = true
  #     }
  #   }

  #   archon_rabbit_viewers = {
  #     name        = "archon-rabbit-viewers"
  #     description = "Read-only access for stakeholders"
  #     visibility  = "organization"

  #     organization_access = {
  #       manage_policies         = false
  #       manage_policy_overrides = false
  #       manage_workspaces       = false
  #       manage_vcs_settings     = false
  #       manage_providers        = false
  #       manage_modules          = false
  #       manage_run_tasks        = false
  #       manage_projects         = false
  #       manage_membership       = false
  #       read_workspaces         = true
  #       read_projects           = true
  #     }
  #   }
  # }


  # variable_sets = {
  #   archon_rabbit_global = {
  #     name        = "archon-rabbit-global"
  #     description = "Global variables for all Archon-Rabbit workspaces"
  #     global      = false # Not global, applied to specific workspaces
  #     priority    = true  # High priority - overrides workspace variables

  #     variables = {
  #       company_name = {
  #         key         = "company_name"
  #         value       = "Archon-Rabbit Inc."
  #         category    = "terraform"
  #         description = "Company name for resource tagging"
  #         sensitive   = false
  #         hcl         = false
  #       }

  #       cost_center = {
  #         key         = "cost_center"
  #         value       = "AR-1234"
  #         category    = "terraform"
  #         description = "Cost center for billing"
  #         sensitive   = false
  #       }

  #       owner_email = {
  #         key         = "owner_email"
  #         value       = "platform-team@archon-rabbit.com"
  #         category    = "terraform"
  #         description = "Owner contact email"
  #         sensitive   = false
  #       }
  #     }
  #   }

  #   archon_rabbit_aws_creds = {
  #     name        = "archon-rabbit-aws-credentials"
  #     description = "AWS credentials for Archon-Rabbit development"
  #     global      = false
  #     priority    = true

  #     variables = {
  #       aws_access_key_id = {
  #         key         = "AWS_ACCESS_KEY_ID"
  #         value       = "AKIAIOSFODNN7EXAMPLE" # Replace with actual or use TFE variable
  #         category    = "env"
  #         description = "AWS Access Key ID"
  #         sensitive   = true
  #       }

  #       aws_secret_access_key = {
  #         key         = "AWS_SECRET_ACCESS_KEY"
  #         value       = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" # Replace with actual
  #         category    = "env"
  #         description = "AWS Secret Access Key"
  #         sensitive   = true
  #       }

  #       aws_default_region = {
  #         key         = "AWS_DEFAULT_REGION"
  #         value       = "us-east-1"
  #         category    = "env"
  #         description = "Default AWS region"
  #         sensitive   = false
  #       }
  #     }
  #   }

  #   archon_rabbit_dev_env = {
  #     name        = "archon-rabbit-dev-environment"
  #     description = "Development environment specific variables"
  #     global      = false
  #     priority    = false

  #     variables = {
  #       environment = {
  #         key         = "environment"
  #         value       = "development"
  #         category    = "terraform"
  #         description = "Environment name"
  #         sensitive   = false
  #       }

  #       env_prefix = {
  #         key         = "env_prefix"
  #         value       = "dev"
  #         category    = "terraform"
  #         description = "Environment prefix for resource names"
  #         sensitive   = false
  #       }

  #       common_tags = {
  #         key = "common_tags"
  #         value = jsonencode({
  #           Environment = "development"
  #           Project     = "Archon-Rabbit"
  #           ManagedBy   = "Terraform"
  #           Department  = "Platform"
  #         })
  #         category    = "terraform"
  #         description = "Common tags for all resources"
  #         sensitive   = false
  #         hcl         = true
  #       }
  #     }
  #   }

  #   archon_rabbit_compute_config = {
  #     name        = "archon-rabbit-compute-configuration"
  #     description = "Compute-specific configuration"
  #     global      = false
  #     priority    = false

  #     variables = {
  #       ami_id = {
  #         key         = "ami_id"
  #         value       = "ami-0c55b159cbfafe1f0" # Example AMI ID
  #         category    = "terraform"
  #         description = "Default AMI ID for compute instances"
  #         sensitive   = false
  #       }

  #       instance_root_volume_size = {
  #         key         = "instance_root_volume_size"
  #         value       = "50"
  #         category    = "terraform"
  #         description = "Root volume size in GB"
  #         sensitive   = false
  #       }

  #       enable_monitoring = {
  #         key         = "enable_monitoring"
  #         value       = "true"
  #         category    = "terraform"
  #         description = "Enable CloudWatch monitoring"
  #         sensitive   = false
  #       }
  #     }
  #   }

  #   archon_rabbit_db_config = {
  #     name        = "archon-rabbit-database-configuration"
  #     description = "Database-specific configuration with sensitive data"
  #     global      = false
  #     priority    = false

  #     variables = {
  #       db_backup_retention_period = {
  #         key         = "db_backup_retention_period"
  #         value       = "7"
  #         category    = "terraform"
  #         description = "RDS backup retention period in days"
  #         sensitive   = false
  #       }

  #       db_backup_window = {
  #         key         = "db_backup_window"
  #         value       = "03:00-04:00"
  #         category    = "terraform"
  #         description = "RDS backup window"
  #         sensitive   = false
  #       }

  #       db_maintenance_window = {
  #         key         = "db_maintenance_window"
  #         value       = "sun:04:00-sun:05:00"
  #         category    = "terraform"
  #         description = "RDS maintenance window"
  #         sensitive   = false
  #       }

  #       redis_parameter_group_family = {
  #         key         = "redis_parameter_group_family"
  #         value       = "redis6.x"
  #         category    = "terraform"
  #         description = "ElastiCache parameter group family"
  #         sensitive   = false
  #       }
  #     }
  #   }
  # }
}
