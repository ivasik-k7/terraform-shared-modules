
variable "TFE_TOKEN" {
  sensitive = true
}

locals {
  tfe_organization = "citadel-hub"
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
  source = "../../modules/tfe-hub"

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
