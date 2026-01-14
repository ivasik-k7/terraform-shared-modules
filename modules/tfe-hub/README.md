# Terraform Module: TFE Managed Infrastructure

This module manages Terraform Cloud/Enterprise (TFC/E) resources, including Projects, Workspaces, Teams, and Variable Sets, using a configuration-driven approach via maps.

## Features

- **Hierarchical Management**: Organizes workspaces within projects.
- **RBAC**: Configures team-level access for both projects and individual workspaces.
- **Variables**: Manages workspace-specific variables and reusable Variable Sets.
- **VCS Integration**: Supports VCS-backed workspaces with GitHub App or OAuth.
- **Automation**: Configures run triggers and notification configurations (Slack, Teams, Email, Generic Webhooks).

---

## Requirements

| Name      | Version   |
| --------- | --------- |
| terraform | >= 1.3.0  |
| tfe       | >= 0.40.0 |

---

## Inputs

### Required Variables

| Name                | Description                                              | Type     |
| ------------------- | -------------------------------------------------------- | -------- |
| `organization_name` | The name of the Terraform Cloud/Enterprise organization. | `string` |

### Optional Variables

| Name            | Description                                                              | Type          | Default |
| --------------- | ------------------------------------------------------------------------ | ------------- | ------- |
| `projects`      | Map of projects and their associated team access policies.               | `map(object)` | `{}`    |
| `workspaces`    | Map of workspaces including VCS, variables, notifications, and triggers. | `map(object)` | `{}`    |
| `teams`         | Map of teams and organization-level permissions.                         | `map(object)` | `{}`    |
| `variable_sets` | Map of global or scoped variable sets and their variables.               | `map(object)` | `{}`    |

---

## Resource Schema Details

### Projects (`projects`)

| Attribute     | Type     | Description                                    |
| ------------- | -------- | ---------------------------------------------- |
| `name`        | `string` | Display name of the project.                   |
| `description` | `string` | Optional project description.                  |
| `team_access` | `map`    | Access control for teams on the project level. |

### Workspaces (`workspaces`)

| Attribute           | Type     | Description                                                                 |
| ------------------- | -------- | --------------------------------------------------------------------------- |
| `name`              | `string` | Workspace name.                                                             |
| `project_key`       | `string` | The key of the project (from the `projects` map) this workspace belongs to. |
| `execution_mode`    | `string` | `remote`, `local`, or `agent`. Default: `remote`.                           |
| `vcs_repo`          | `object` | Connection block for VCS (requires `identifier`).                           |
| `variables`         | `map`    | Key-value pairs assigned to the workspace.                                  |
| `team_access`       | `map`    | Fine-grained permissions for specific teams.                                |
| `run_triggers`      | `map`    | List of workspace keys that trigger a run in this workspace.                |
| `variable_set_keys` | `list`   | List of keys from the `variable_sets` map to link.                          |

### Teams (`teams`)

| Attribute             | Type     | Description                                                        |
| --------------------- | -------- | ------------------------------------------------------------------ |
| `name`                | `string` | Team name.                                                         |
| `organization_access` | `object` | Boolean flags for org-level permissions (e.g., `manage_projects`). |
| `sso_team_id`         | `string` | External ID for SAML/SSO mapping.                                  |

---

## Usage Example

```hcl
module "tfc_infrastructure" {
  source            = "./modules/tfe-managed-infra"
  organization_name = "my-org"

  projects = {
    platform = {
      name        = "Platform-Core"
      description = "Core infrastructure projects"
      team_access = {
        admins = { access = "admin" }
      }
    }
  }

  teams = {
    admins = {
      name = "organization-admins"
      organization_access = {
        manage_projects = true
      }
    }
  }

  workspaces = {
    vpc_prod = {
      name        = "networking-prod"
      project_key = "platform"
      vcs_repo = {
        identifier = "org/repo-name"
        branch     = "main"
      }
      variables = {
        region = {
          key   = "aws_region"
          value = "us-east-1"
        }
      }
    }
  }
}

```

---

## Managed Resources

- `tfe_project.this`
- `tfe_workspace.this`
- `tfe_workspace_settings.this`
- `tfe_variable.workspace_variables`
- `tfe_variable.variable_set_variables`
- `tfe_team.this`
- `tfe_team_access.workspace_access`
- `tfe_team_project_access.project_access`
- `tfe_notification_configuration.this`
- `tfe_run_trigger.this`
- `tfe_variable_set.this`
- `tfe_workspace_variable_set.this`

---
