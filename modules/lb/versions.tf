terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Floor set by the newest arguments used (e.g. tcp_idle_timeout_seconds,
      # target_group_health, mutual_authentication). Older 5.x lacks them.
      version = ">= 5.81.0, < 6.0.0"
    }
  }
}
