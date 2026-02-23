output "security_group_ids" {
  description = <<-EOT
    Map of Security Group key → ID.

    Usage:
      vpc_security_group_ids = [module.sg.security_group_ids["eks-nodes"]]
      vpc_security_group_ids = values(module.sg.security_group_ids)
  EOT
  value       = { for k, v in aws_security_group.this : k => v.id }
}

output "security_group_arns" {
  description = "Map of Security Group key → ARN."
  value       = { for k, v in aws_security_group.this : k => v.arn }
}

output "security_groups" {
  description = "Full Security Group objects. Shape: { key => { id, arn, name, description } }."
  value = {
    for k, v in aws_security_group.this : k => {
      id          = v.id
      arn         = v.arn
      name        = v.name
      description = v.description
    }
  }
}
