# A change to the containers, size, roles or volumes registers a new revision.
# create_before_destroy registers it before the service moves to it.
resource "aws_ecs_task_definition" "this" {
  for_each = local.services

  family                   = "${var.name}-${each.key}"
  container_definitions    = local.container_definitions[each.key]
  cpu                      = tostring(each.value.cpu)
  memory                   = tostring(each.value.memory)
  network_mode             = each.value.network_mode
  requires_compatibilities = [each.value.launch]
  execution_role_arn       = each.value.execution_role.create ? aws_iam_role.execution[each.key].arn : each.value.execution_role.arn
  task_role_arn            = each.value.task_role.create ? aws_iam_role.task[each.key].arn : each.value.task_role.arn
  pid_mode                 = each.value.pid_mode != "" ? each.value.pid_mode : null
  ipc_mode                 = each.value.ipc_mode != "" ? each.value.ipc_mode : null
  skip_destroy             = var.task_definition_skip_destroy

  runtime_platform {
    cpu_architecture        = each.value.cpu_architecture
    operating_system_family = each.value.operating_system_family
  }

  dynamic "ephemeral_storage" {
    for_each = each.value.ephemeral_storage_gib > 0 ? [each.value.ephemeral_storage_gib] : []
    content {
      size_in_gib = ephemeral_storage.value
    }
  }

  dynamic "volume" {
    for_each = each.value.volumes
    content {
      name                = volume.key
      host_path           = volume.value.host_path != "" ? volume.value.host_path : null
      configure_at_launch = volume.value.configure_at_launch ? true : null

      dynamic "efs_volume_configuration" {
        for_each = volume.value.efs != null ? [volume.value.efs] : []
        content {
          file_system_id     = efs_volume_configuration.value.file_system_id
          root_directory     = efs_volume_configuration.value.access_point_id == "" && efs_volume_configuration.value.root_directory != "" ? efs_volume_configuration.value.root_directory : null
          transit_encryption = efs_volume_configuration.value.transit_encryption ? "ENABLED" : "DISABLED"

          dynamic "authorization_config" {
            for_each = efs_volume_configuration.value.access_point_id != "" || efs_volume_configuration.value.iam_authorization ? [efs_volume_configuration.value] : []
            content {
              access_point_id = authorization_config.value.access_point_id != "" ? authorization_config.value.access_point_id : null
              iam             = authorization_config.value.iam_authorization ? "ENABLED" : "DISABLED"
            }
          }
        }
      }

      dynamic "docker_volume_configuration" {
        for_each = volume.value.docker != null ? [volume.value.docker] : []
        content {
          scope         = docker_volume_configuration.value.scope
          autoprovision = docker_volume_configuration.value.scope == "shared" ? docker_volume_configuration.value.autoprovision : null
          driver        = docker_volume_configuration.value.driver != "" ? docker_volume_configuration.value.driver : null
          driver_opts   = length(docker_volume_configuration.value.driver_opts) > 0 ? docker_volume_configuration.value.driver_opts : null
          labels        = length(docker_volume_configuration.value.labels) > 0 ? docker_volume_configuration.value.labels : null
        }
      }
    }
  }

  tags = local.workload_tags[each.key]

  lifecycle {
    create_before_destroy = true
  }
}
