# The "hostingprovider-count-cf" compliance ACL, recreated with the wafv2
# module. Reproduces the raw vanilla config:
#   - block requests in an EXTERNAL threat-intelligence IP set
#   - Common + AdminProtection + KnownBadInputs + AnonymousIpList + IpReputation
#     managed groups, with AnonymousIpList's HostingProviderIPList sub-rule in
#     Count (observe hosting-provider IPs without blocking)
# plus the requested proxy case: block anything NOT in the proxy allowlist set.
#
# Both IP sets are managed elsewhere (another team/stack) and referenced by ARN.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0, < 6.0.0"
    }
  }
}

# CLOUDFRONT-scope WAF + IP sets live in us-east-1
provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}

# externally-managed IP sets, looked up by name (REPLACE the names to match yours)
data "aws_wafv2_ip_set" "threat_list" {
  provider = aws.use1
  name     = "NGThreatIntelligenceIPList"
  scope    = "CLOUDFRONT"
}

data "aws_wafv2_ip_set" "proxy" {
  provider = aws.use1
  name     = "ProxyIPSet"
  scope    = "CLOUDFRONT"
}

module "waf" {
  source    = "../../modules/wafv2"
  providers = { aws = aws.use1 }

  name           = "hostingprovider-count-cf"
  description    = "Compliant CLOUDFRONT Web ACL with HostingProviderIPList set to Count"
  scope          = "CLOUDFRONT"
  default_action = "allow"

  # compose explicitly (no opinionated baseline) to mirror the vanilla ACL
  enable_baseline = false

  # external IP-set rules (evaluated first, in list order)
  ip_reference_rules = [
    # block anything in the threat-intelligence feed
    { name = "Block-Threat-Intelligence-IP-Set", arn = data.aws_wafv2_ip_set.threat_list.arn, action = "block" },
    # block anything NOT in the proxy allowlist (matched on the CloudFront viewer IP)
    {
      name         = "Block-Not-Proxy"
      arn          = data.aws_wafv2_ip_set.proxy.arn
      action       = "block"
      negate       = true
      forwarded_ip = { header_name = "X-Forwarded-For", position = "FIRST" }
    },
  ]

  # the managed baseline, with the HostingProviderIPList sub-rule in Count
  managed_rule_groups = [
    { name = "AWSManagedRulesCommonRuleSet" },
    { name = "AWSManagedRulesAdminProtectionRuleSet" },
    { name = "AWSManagedRulesKnownBadInputsRuleSet" },
    {
      name                  = "AWSManagedRulesAnonymousIpList"
      rule_action_overrides = { HostingProviderIPList = "count" }
    },
    { name = "AWSManagedRulesAmazonIpReputationList" },
  ]

  tags = { Compliance = "hostingprovider-count", ManagedBy = "Terraform" }
}

output "hostingprovider_count_cf_arn" {
  value = module.waf.web_acl_arn
}

# evaluation order the module assigned, for the change record
output "rule_priorities" {
  value = module.waf.rule_priorities
}
