# ==========================================
# PROJECTS
# ==========================================
resource "tfe_project" "this" {
  for_each = var.projects

  organization = var.organization_name
  name         = each.value.name
  description  = try(each.value.description, null)
}

# ==========================================
# WORKSPACES & SETTINGS
# ==========================================
resource "tfe_workspace" "this" {
  for_each = var.workspaces

  organization      = var.organization_name
  name              = each.value.name
  project_id        = try(tfe_project.this[each.value.project_key].id, null)
  terraform_version = try(each.value.terraform_version, null)
  working_directory = try(each.value.working_directory, null)

  dynamic "vcs_repo" {
    for_each = try(each.value.vcs_repo, null) != null ? [each.value.vcs_repo] : []
    content {
      identifier                 = vcs_repo.value.identifier
      branch                     = try(vcs_repo.value.branch, null)
      oauth_token_id             = try(vcs_repo.value.oauth_token_id, null)
      tags_regex                 = try(vcs_repo.value.tags_regex, null)
      github_app_installation_id = try(vcs_repo.value.github_app_installation_id, null)
    }
  }

  ssh_key_id = try(each.value.ssh_key_id, null)
  tag_names  = try(each.value.tags, [])
}

resource "tfe_workspace_settings" "this" {
  for_each = var.workspaces

  workspace_id = tfe_workspace.this[each.key].id

  execution_mode      = try(each.value.execution_mode, "remote")
  agent_pool_id       = try(each.value.agent_pool_id, null)
  description         = try(each.value.description, null)
  auto_apply          = try(each.value.auto_apply, false)
  assessments_enabled = try(each.value.assessments_enabled, false)

  global_remote_state       = try(each.value.global_remote_state, false)
  remote_state_consumer_ids = try(each.value.remote_state_consumer_ids, [])
}

# ==========================================
# VARIABLES (Workspace Level)
# ==========================================
resource "tfe_variable" "workspace_variables" {
  for_each = merge([
    for ws_key, ws in var.workspaces : {
      for var_key, variable in(ws.variables != null ? ws.variables : {}) :
      "${ws_key}-${var_key}" => merge(variable, {
        workspace_id = tfe_workspace.this[ws_key].id
      })
    }
  ]...)

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = try(each.value.category, "terraform")
  description  = try(each.value.description, null)
  sensitive    = try(each.value.sensitive, false)
  hcl          = try(each.value.hcl, false)
}

# ==========================================
# TEAMS & ACCESS
# ==========================================
resource "tfe_team" "this" {
  for_each = var.teams

  organization = var.organization_name
  name         = each.value.name
  visibility   = try(each.value.visibility, "organization")

  dynamic "organization_access" {
    for_each = try(each.value.organization_access, null) != null ? [each.value.organization_access] : []
    content {
      manage_policies         = try(organization_access.value.manage_policies, false)
      manage_policy_overrides = try(organization_access.value.manage_policy_overrides, false)
      manage_workspaces       = try(organization_access.value.manage_workspaces, false)
      manage_vcs_settings     = try(organization_access.value.manage_vcs_settings, false)
      manage_providers        = try(organization_access.value.manage_providers, false)
      manage_modules          = try(organization_access.value.manage_modules, false)
      manage_run_tasks        = try(organization_access.value.manage_run_tasks, false)
      manage_projects         = try(organization_access.value.manage_projects, false)
      manage_membership       = try(organization_access.value.manage_membership, false)
      read_workspaces         = try(organization_access.value.read_workspaces, false)
      read_projects           = try(organization_access.value.read_projects, false)
    }
  }

  sso_team_id = try(each.value.sso_team_id, null)
}

resource "tfe_team_access" "workspace_access" {
  for_each = merge([
    for ws_key, ws in var.workspaces : {
      for team_key, access in(ws.team_access != null ? ws.team_access : {}) :
      "${ws_key}-${team_key}" => merge(access, {
        workspace_id = tfe_workspace.this[ws_key].id
        team_id      = tfe_team.this[team_key].id
      })
    }
  ]...)

  workspace_id = each.value.workspace_id
  team_id      = each.value.team_id
  access       = try(each.value.permissions, null) == null ? try(each.value.access, null) : null

  dynamic "permissions" {
    for_each = try(each.value.permissions, null) != null ? [each.value.permissions] : []
    content {
      runs              = permissions.value.runs
      variables         = permissions.value.variables
      state_versions    = permissions.value.state_versions
      sentinel_mocks    = try(permissions.value.sentinel_mocks, "none")
      workspace_locking = try(permissions.value.workspace_locking, false)
      run_tasks         = try(permissions.value.run_tasks, false)
    }
  }
}

resource "tfe_team_project_access" "project_access" {
  for_each = merge([
    for proj_key, proj in var.projects : {
      for team_key, access in(proj.team_access != null ? proj.team_access : {}) :
      "${proj_key}-${team_key}" => merge(access, {
        project_id = tfe_project.this[proj_key].id
        team_id    = tfe_team.this[team_key].id
      })
    }
  ]...)

  project_id = each.value.project_id
  team_id    = each.value.team_id
  access     = each.value.access

  dynamic "project_access" {
    for_each = try(each.value.project_access, null) != null ? [each.value.project_access] : []
    content {
      settings = try(project_access.value.settings, "read")
      teams    = try(project_access.value.teams, "read")
    }
  }

  dynamic "workspace_access" {
    for_each = try(each.value.workspace_access, null) != null ? [each.value.workspace_access] : []
    content {
      runs           = try(workspace_access.value.runs, "read")
      sentinel_mocks = try(workspace_access.value.sentinel_mocks, "none")
      state_versions = try(workspace_access.value.state_versions, "read")
      variables      = try(workspace_access.value.variables, "read")
      create         = try(workspace_access.value.create, false)
      locking        = try(workspace_access.value.locking, false)
      delete         = try(workspace_access.value.delete, false)
      move           = try(workspace_access.value.move, false)
      run_tasks      = try(workspace_access.value.run_tasks, false)
    }
  }
}

# ==========================================
# NOTIFICATIONS & TRIGGERS
# ==========================================
resource "tfe_notification_configuration" "this" {
  for_each = merge([
    for ws_key, ws in var.workspaces : {
      for notif_key, notif in(ws.notifications != null ? ws.notifications : {}) :
      "${ws_key}-${notif_key}" => merge(notif, {
        workspace_id = tfe_workspace.this[ws_key].id
      })
    }
  ]...)

  workspace_id     = each.value.workspace_id
  name             = each.value.name
  destination_type = each.value.destination_type
  enabled          = try(each.value.enabled, true)
  token            = try(each.value.token, null)
  url              = try(each.value.url, null)
  triggers         = try(each.value.triggers, ["run:created", "run:planning", "run:errored"])
  email_user_ids   = try(each.value.email_user_ids, [])
}

resource "tfe_run_trigger" "this" {
  for_each = merge([
    for ws_key, ws in var.workspaces : {
      for trigger_key, trigger in(ws.run_triggers != null ? ws.run_triggers : {}) :
      "${ws_key}-${trigger_key}" => {
        workspace_id  = tfe_workspace.this[ws_key].id
        sourceable_id = tfe_workspace.this[trigger].id
      }
    }
  ]...)

  workspace_id  = each.value.workspace_id
  sourceable_id = each.value.sourceable_id
}

# ==========================================
# VARIABLE SETS
# ==========================================
resource "tfe_variable_set" "this" {
  for_each = var.variable_sets

  organization = var.organization_name
  name         = each.value.name
  description  = try(each.value.description, null)
  global       = try(each.value.global, false)
  priority     = try(each.value.priority, false)
}

resource "tfe_variable" "variable_set_variables" {
  for_each = merge([
    for vs_key, vs in var.variable_sets : {
      for var_key, variable in(vs.variables != null ? vs.variables : {}) :
      "${vs_key}-${var_key}" => merge(variable, {
        variable_set_id = tfe_variable_set.this[vs_key].id
      })
    }
  ]...)

  variable_set_id = each.value.variable_set_id
  key             = each.value.key
  value           = each.value.value
  category        = try(each.value.category, "terraform")
  description     = try(each.value.description, null)
  sensitive       = try(each.value.sensitive, false)
  hcl             = try(each.value.hcl, false)
}

resource "tfe_workspace_variable_set" "this" {
  for_each = merge([
    for ws_key, ws in var.workspaces : {
      for vs_key in(ws.variable_set_keys != null ? ws.variable_set_keys : []) :
      "${ws_key}-${vs_key}" => {
        workspace_id    = tfe_workspace.this[ws_key].id
        variable_set_id = tfe_variable_set.this[vs_key].id
      }
    }
  ]...)

  workspace_id    = each.value.workspace_id
  variable_set_id = each.value.variable_set_id
}
