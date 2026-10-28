terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 5.73.0 fixes persistent validation errors when malformed aws_kms_key policy content reaches state.
      # https://github.com/hashicorp/terraform-provider-aws/blob/v5.73.0/CHANGELOG.md
      version = ">= 5.73.0, < 7.0.0"
    }
  }
}
