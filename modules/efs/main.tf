locals {
  creation_token = var.creation_token != null ? var.creation_token : var.name
  security_groups_ids = concat(
    var.create_security_group ? [aws_security_group.efs[0].id] : [],
    var.security_group_ids
  )
}

resource "aws_efs_file_system" "this" {
  creation_token   = local.creation_token
  encrypted        = var.encrypted
  kms_key_id       = var.kms_key_id
  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode

  availability_zone_name          = var.availability_zone_name
  provisioned_throughput_in_mibps = var.throughput_mode == "provisioned" ? var.provisioned_throughput_in_mibps : null

  dynamic "lifecycle_policy" {
    for_each = var.lifecycle_policy_transition_to_ia != null ? [1] : []
    content {
      transition_to_ia = var.lifecycle_policy_transition_to_ia
    }
  }

  dynamic "lifecycle_policy" {
    for_each = var.lifecycle_policy_transition_to_primary_storage_class != null ? [1] : []
    content {
      transition_to_primary_storage_class = var.lifecycle_policy_transition_to_primary_storage_class
    }
  }

  dynamic "lifecycle_policy" {
    for_each = var.lifecycle_policy_transition_to_archive != null ? [1] : []
    content {
      transition_to_archive = var.lifecycle_policy_transition_to_archive
    }
  }

  dynamic "protection" {
    for_each = var.enable_replication_overwrite_protection ? [1] : []
    content {
      replication_overwrite = "ENABLED"
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.name
    }
  )
}

resource "aws_efs_mount_target" "this" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = local.security_groups_ids
  ip_address      = lookup(var.mount_target_ip_addresses, each.value, null)
}

resource "aws_efs_backup_policy" "this" {
  count = var.enable_backup_policy ? 1 : 0

  file_system_id = aws_efs_file_system.this.id

  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_efs_file_system_policy" "this" {
  count = var.file_system_policy != null ? 1 : 0

  file_system_id                     = aws_efs_file_system.this.id
  bypass_policy_lockout_safety_check = var.bypass_policy_lockout_safety_check
  policy                             = var.file_system_policy
}

resource "aws_efs_access_point" "this" {
  for_each = var.access_points

  file_system_id = aws_efs_file_system.this.id

  dynamic "posix_user" {
    for_each = each.value.posix_user != null ? [each.value.posix_user] : []
    content {
      gid            = posix_user.value.gid
      uid            = posix_user.value.uid
      secondary_gids = lookup(posix_user.value, "secondary_gids", null)
    }
  }

  dynamic "root_directory" {
    for_each = each.value.root_directory != null ? [each.value.root_directory] : []
    content {
      path = lookup(root_directory.value, "path", null)

      dynamic "creation_info" {
        for_each = lookup(root_directory.value, "creation_info", null) != null ? [root_directory.value.creation_info] : []
        content {
          owner_gid   = creation_info.value.owner_gid
          owner_uid   = creation_info.value.owner_uid
          permissions = creation_info.value.permissions
        }
      }
    }
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = each.key
    }
  )
}

resource "aws_efs_replication_configuration" "this" {
  count = var.replication_configuration != null ? 1 : 0

  source_file_system_id = aws_efs_file_system.this.id

  destination {
    region                 = lookup(var.replication_configuration, "region", null)
    availability_zone_name = lookup(var.replication_configuration, "availability_zone_name", null)
    kms_key_id             = lookup(var.replication_configuration, "kms_key_id", null)
    file_system_id         = lookup(var.replication_configuration, "file_system_id", null)
  }
}
