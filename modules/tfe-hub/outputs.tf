output "projects" {
  description = "Map of created projects with their attributes"
  value = {
    for k, v in tfe_project.this : k => {
      id          = v.id
      name        = v.name
      description = v.description
    }
  }
}

output "project_ids" {
  description = "Map of project keys to project IDs"
  value       = { for k, v in tfe_project.this : k => v.id }
}

output "workspaces" {
  description = "Map of created workspaces with their attributes"
  value = {
    for k, v in tfe_workspace.this : k => {
      id                = v.id
      name              = v.name
      project_id        = v.project_id
      terraform_version = v.terraform_version
      working_directory = v.working_directory
      tags              = v.tag_names
      html_url          = v.html_url
      resource_count    = v.resource_count

      description         = tfe_workspace_settings.this[k].description
      execution_mode      = tfe_workspace_settings.this[k].execution_mode
      auto_apply          = tfe_workspace_settings.this[k].auto_apply
      assessments_enabled = tfe_workspace_settings.this[k].assessments_enabled
    }
  }
}

output "workspace_ids" {
  description = "Map of workspace keys to workspace IDs"
  value       = { for k, v in tfe_workspace.this : k => v.id }
}

output "workspace_names" {
  description = "Map of workspace keys to workspace names"
  value       = { for k, v in tfe_workspace.this : k => v.name }
}

output "teams" {
  description = "Map of created teams with their attributes"
  value = {
    for k, v in tfe_team.this : k => {
      id         = v.id
      name       = v.name
      visibility = v.visibility
    }
  }
}

output "team_ids" {
  description = "Map of team keys to team IDs"
  value       = { for k, v in tfe_team.this : k => v.id }
}


output "variable_sets" {
  description = "Map of created variable sets with their attributes"
  value = {
    for k, v in tfe_variable_set.this : k => {
      id          = v.id
      name        = v.name
      description = v.description
      global      = v.global
    }
  }
}

output "variable_set_ids" {
  description = "Map of variable set keys to variable set IDs"
  value       = { for k, v in tfe_variable_set.this : k => v.id }
}

output "notification_configurations" {
  description = "Map of created notification configurations"
  value = {
    for k, v in tfe_notification_configuration.this : k => {
      id               = v.id
      name             = v.name
      destination_type = v.destination_type
      enabled          = v.enabled
    }
  }
}

output "summary" {
  description = "Summary of all created resources"
  value = {
    projects_count      = length(tfe_project.this)
    workspaces_count    = length(tfe_workspace.this)
    teams_count         = length(tfe_team.this)
    variable_sets_count = length(tfe_variable_set.this)
    organization        = var.organization_name
  }
}
