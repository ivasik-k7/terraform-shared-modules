variable "organization_name" {
  description = "The name of the Terraform Cloud/Enterprise organization"
  type        = string
}

# ------------------------------------------
# PROJECTS
# ------------------------------------------
variable "projects" {
  description = "Map of projects to create"
  type = map(object({
    name        = string
    description = optional(string)
    team_access = optional(map(object({
      access = string # read, write, maintain, admin
      project_access = optional(object({
        settings = optional(string) # read, update, delete
        teams    = optional(string) # read, manage
      }))
      workspace_access = optional(object({
        runs           = optional(string) # read, plan, apply
        sentinel_mocks = optional(string) # none, read
        state_versions = optional(string) # none, read-outputs, read, write
        variables      = optional(string) # none, read, write
        create         = optional(bool)
        locking        = optional(bool)
        delete         = optional(bool)
        move           = optional(bool)
        run_tasks      = optional(bool)
      }))
    })))
  }))
  default = {}
}

# ------------------------------------------
# WORKSPACES
# ------------------------------------------
variable "workspaces" {
  description = "Map of workspaces to create"
  type = map(object({
    name        = string
    description = optional(string)
    project_key = optional(string)

    execution_mode         = optional(string) # remote, local, agent
    agent_pool_id          = optional(string)
    allow_destroy_plan     = optional(bool)
    auto_apply             = optional(bool)
    auto_apply_run_trigger = optional(bool)

    file_triggers_enabled = optional(bool)
    trigger_prefixes      = optional(list(string))
    trigger_patterns      = optional(list(string))

    queue_all_runs      = optional(bool)
    speculative_enabled = optional(bool)
    assessments_enabled = optional(bool)

    terraform_version = optional(string)
    working_directory = optional(string)

    vcs_repo = optional(object({
      identifier                 = string
      branch                     = optional(string)
      oauth_token_id             = optional(string)
      tags_regex                 = optional(string)
      github_app_installation_id = optional(string)
    }))

    tags = optional(list(string))

    ssh_key_id = optional(string)

    global_remote_state       = optional(bool)
    remote_state_consumer_ids = optional(list(string))

    structured_run_output_enabled = optional(bool)

    variables = optional(map(object({
      key         = string
      value       = string
      category    = optional(string)
      description = optional(string)
      sensitive   = optional(bool)
      hcl         = optional(bool)
    })))

    team_access = optional(map(object({
      access = optional(string) # read, plan, write, admin, custom
      permissions = optional(object({
        runs              = string           # read, plan, apply
        variables         = string           # none, read, write
        state_versions    = string           # none, read-outputs, read, write
        sentinel_mocks    = optional(string) # none, read
        workspace_locking = optional(bool)
        run_tasks         = optional(bool)
      }))
    })))

    # Notifications
    notifications = optional(map(object({
      name             = string
      destination_type = string # email, generic, slack, microsoft-teams
      enabled          = optional(bool)
      token            = optional(string)
      url              = optional(string)
      triggers         = optional(list(string))
      email_user_ids   = optional(list(string))
    })))

    run_triggers = optional(map(string))

    variable_set_keys = optional(list(string))
  }))
  default = {}
}

# ------------------------------------------
# TEAMS
# ------------------------------------------
variable "teams" {
  description = "Map of teams to create"
  type = map(object({
    name       = string
    visibility = optional(string)
    organization_access = optional(object({
      manage_policies         = optional(bool)
      manage_policy_overrides = optional(bool)
      manage_workspaces       = optional(bool)
      manage_vcs_settings     = optional(bool)
      manage_providers        = optional(bool)
      manage_modules          = optional(bool)
      manage_run_tasks        = optional(bool)
      manage_projects         = optional(bool)
      manage_membership       = optional(bool)
      read_workspaces         = optional(bool)
      read_projects           = optional(bool)
    }))
    sso_team_id = optional(string)
  }))
  default = {}
}

# ------------------------------------------
# VARIABLE SETS
# ------------------------------------------
variable "variable_sets" {
  description = "Map of variable sets to create"
  type = map(object({
    name        = string
    description = optional(string)
    global      = optional(bool)
    priority    = optional(bool)
    variables = optional(map(object({
      key         = string
      value       = string
      category    = optional(string)
      description = optional(string)
      sensitive   = optional(bool)
      hcl         = optional(bool)
    })))
  }))
  default = {}
}
