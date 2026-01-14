terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  name_prefix = "archon-hub-dev"

  base_tags = {
    Project     = "archon-hub"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

module "sqs" {
  source = "../../modules/sqs"

  name = "${local.name_prefix}-main-queue"

  create_dlq                    = true
  message_retention_seconds     = 1209600
  dlq_message_retention_seconds = 1209600

  max_receive_count         = 5
  receive_wait_time_seconds = 20
  fifo_queue                = false

  sqs_managed_sse_enabled = true
  kms_master_key_id       = null

  tags = merge(
    local.base_tags,
    {
      Service     = "sqs"
      Application = "message-queue"
    }
  )
}

output "queue_url" {
  value = module.sqs.queue_url
}

output "queue_arn" {
  value = module.sqs.queue_arn
}

output "dlq_url" {
  value = module.sqs.dlq_url
}