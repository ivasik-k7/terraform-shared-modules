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
    CreatedDate = "2026-01-08"
    CostCenter  = "engineering"
  }
}

module "sns" {
  source = "../../modules/sns"

  name         = "${local.name_prefix}-notifications"
  display_name = "Archon Hub Notifications"

  subscriptions = [
    {
      protocol = "email"
      endpoint = "admin@example.com"
    }
  ]

  message_templates = {
    welcome = {
      subject         = "🚀 Welcome to the Archon Platform!"
      message         = "<!DOCTYPE html><html><head><meta charset='utf-8'><style>body{font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;margin:0;padding:0;background:#0a0a0a;color:#e0e0e0}.container{max-width:600px;margin:0 auto;background:linear-gradient(135deg,#1a1a2e 0%,#16213e 100%);border-radius:12px;overflow:hidden;box-shadow:0 20px 40px rgba(0,0,0,0.3)}.header{background:linear-gradient(90deg,#0f3460 0%,#e94560 100%);padding:40px 30px;text-align:center}.logo{font-size:32px;font-weight:bold;color:#fff;margin-bottom:10px;text-shadow:2px 2px 4px rgba(0,0,0,0.5)}.tagline{color:#b8c6db;font-size:16px;opacity:0.9}.content{padding:40px 30px}.welcome-text{font-size:24px;color:#fff;margin-bottom:20px;text-align:center}.message{font-size:16px;line-height:1.6;color:#b8c6db;margin-bottom:30px}.features{background:#1e1e2e;border-radius:8px;padding:25px;margin:20px 0}.feature-item{display:flex;align-items:center;margin:15px 0;color:#e0e0e0}.feature-icon{width:20px;height:20px;margin-right:15px;color:#e94560}.cta{text-align:center;margin:30px 0}.cta-button{display:inline-block;background:linear-gradient(90deg,#e94560 0%,#0f3460 100%);color:#fff;padding:15px 30px;text-decoration:none;border-radius:25px;font-weight:bold;font-size:16px;transition:transform 0.3s ease;box-shadow:0 4px 15px rgba(233,69,96,0.3)}.cta-button:hover{transform:translateY(-2px)}.footer{background:#0f0f0f;padding:20px 30px;text-align:center;border-top:1px solid #333}.footer-text{color:#666;font-size:14px}</style></head><body><div class='container'><div class='header'><div class='logo'>⚡ ARCHON</div><div class='tagline'>Next-Generation Cloud Platform</div></div><div class='content'><div class='welcome-text'>Welcome to the Future! 🎯</div><div class='message'>You've successfully joined the <strong>Archon Platform</strong> – where cutting-edge technology meets seamless cloud infrastructure. Get ready to experience the next level of development and deployment.</div><div class='features'><div class='feature-item'><span class='feature-icon'>🚀</span><span>Lightning-fast deployments with zero downtime</span></div><div class='feature-item'><span class='feature-icon'>🔒</span><span>Enterprise-grade security and encryption</span></div><div class='feature-item'><span class='feature-icon'>📊</span><span>Real-time monitoring and analytics</span></div><div class='feature-item'><span class='feature-icon'>⚡</span><span>Auto-scaling infrastructure that adapts to your needs</span></div></div><div class='cta'><a href='#' class='cta-button'>Explore Your Dashboard</a></div><div class='message'>Your journey into the future of cloud computing starts now. We're excited to have you aboard!</div></div><div class='footer'><div class='footer-text'>© 2026 Archon Platform | Powered by Advanced Infrastructure</div></div></div></body></html>"
      default_message = "🚀 Welcome to the Archon Platform! You've successfully joined our next-generation cloud platform. Get ready to experience lightning-fast deployments, enterprise-grade security, and auto-scaling infrastructure. Your journey into the future starts now!"
    }
    alert = {
      subject         = "Archon Hub Alert"
      message         = "<h2>System Alert</h2><p>{{message}}</p><p>Time: {{timestamp}}</p>"
      default_message = "System Alert: {{message}}"
    }
  }

  tags = merge(
    local.base_tags,
    {
      Service     = "sns"
      Application = "notifications"
      Team        = "platform"
      Owner       = "devops-team"
    }
  )
}

output "topic_arn" {
  description = "SNS topic ARN"
  value       = module.sns.topic_arn
}

output "topic_name" {
  description = "SNS topic name"
  value       = module.sns.topic_name
}

output "subscription_arns" {
  description = "SNS subscription ARNs"
  value       = module.sns.subscription_arns
}
