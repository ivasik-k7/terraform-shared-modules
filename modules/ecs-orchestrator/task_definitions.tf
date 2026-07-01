# one task definition per service. container JSON comes from locals; volumes
# reference EFS/FSx or are host/docker; managed EBS is wired via the service.

resource "aws_ecs_task_definition" "this" {
  for_each = local.services

  family                   = "${var.cluster_name}-${each.key}"
  requires_compatibilities = each.value.requires_compatibilities
  network_mode             = each.value.network_mode
  cpu                      = tostring(each.value.cpu)
  memory                   = each.value.memory != null ? tostring(each.value.memory) : null
  execution_role_arn       = local.service_execution_role_arn[each.key]
  task_role_arn            = local.service_task_role_arn[each.key]
  container_definitions    = local.container_definitions[each.key]
  pid_mode                 = each.value.pid_mode
  ipc_mode                 = each.value.ipc_mode

  runtime_platform {
    operating_system_family = each.value.operating_system_family
    cpu_architecture        = each.value.cpu_architecture
  }

  dynamic "ephemeral_storage" {
    for_each = each.value.ephemeral_storage_gib != null ? [1] : []
    content {
      size_in_gib = each.value.ephemeral_storage_gib
    }
  }

  dynamic "volume" {
    for_each = each.value.volumes
    content {
      name                = volume.key
      host_path           = volume.value.host_path
      configure_at_launch = volume.value.configure_at_launch

      dynamic "efs_volume_configuration" {
        for_each = volume.value.efs != null ? [volume.value.efs] : []
        content {
          file_system_id          = efs_volume_configuration.value.file_system_id
          root_directory          = efs_volume_configuration.value.access_point_id != null ? null : efs_volume_configuration.value.root_directory
          transit_encryption      = efs_volume_configuration.value.transit_encryption
          transit_encryption_port = efs_volume_configuration.value.transit_encryption_port

          dynamic "authorization_config" {
            for_each = efs_volume_configuration.value.access_point_id != null ? [1] : []
            content {
              access_point_id = efs_volume_configuration.value.access_point_id
              iam             = coalesce(efs_volume_configuration.value.iam, "ENABLED")
            }
          }
        }
      }

      dynamic "docker_volume_configuration" {
        for_each = volume.value.docker != null ? [volume.value.docker] : []
        content {
          scope         = docker_volume_configuration.value.scope
          autoprovision = docker_volume_configuration.value.autoprovision
          driver        = docker_volume_configuration.value.driver
          driver_opts   = docker_volume_configuration.value.driver_opts
          labels        = docker_volume_configuration.value.labels
        }
      }
    }
  }

  tags = merge(local.common_tags, each.value.task_tags, each.value.tags)

  lifecycle {
    create_before_destroy = true
  }
}
