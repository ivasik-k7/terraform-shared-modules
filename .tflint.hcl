# Root config for `scripts/tf-modules.sh check` and `make lint`; a module's own
# .tflint.hcl wins over it. CI's validate matrix runs tflint from the module
# directory, so it sees this file only when a module copies it.
#
# Plugin versions are pinned and Dependabot does not update them: bump them
# deliberately, with the provider range.

config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
  version = "0.15.0"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Descriptions are enforced repo-wide by scripts/check_governance.py (G007/G008)
# against a ratcheted baseline, which tflint cannot express.
rule "terraform_documented_variables" {
  enabled = false
}

rule "terraform_documented_outputs" {
  enabled = false
}
