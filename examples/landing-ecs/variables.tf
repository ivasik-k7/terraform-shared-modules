variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "staging"
}

variable "project" {
  description = "Project name — used in resource names and the Project tag."
  type        = string
  default     = "acme-platform"
}

variable "team" {
  description = "Owning team — applied as the Team tag."
  type        = string
  default     = "platform"
}

variable "cost_center" {
  description = "Finance cost center — applied as the CostCenter tag."
  type        = string
  default     = "ENG-001"
}

variable "vpc_name" {
  description = "Name tag of the VPC to deploy into."
  type        = string
  default     = "main"
}

variable "app_version" {
  description = "Docker image tag to deploy."
  type        = string
  default     = "latest"
}

variable "github_org" {
  description = "GitHub organization — used in the GitRepo tag."
  type        = string
  default     = "my-org"
}
