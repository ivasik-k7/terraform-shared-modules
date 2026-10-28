# release-please rewrites every "v<major>.<minor>.<patch>" string in this file
# on release: write versions here without a leading v.
terraform {
  # The floor decides the language: 1.9 allows validations that read other
  # variables, and evaluates both sides of || and && (see CONTRIBUTING.md).
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Both majors. CI tests the v5 end pinned and the newest v6.
      version = ">= 5.90.0, < 7.0.0"
    }
  }
}
