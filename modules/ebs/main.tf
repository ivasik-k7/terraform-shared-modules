resource "aws_ebs_volume" "this" {
  for_each = local.volumes

  availability_zone = each.value.availability_zone
  size              = each.value.size
  type              = each.value.type
  iops              = each.value.iops
  throughput        = each.value.throughput

  encrypted  = each.value.encrypted
  kms_key_id = each.value.kms_key_id

  snapshot_id          = each.value.snapshot_id
  multi_attach_enabled = each.value.multi_attach_enabled
  outpost_arn          = each.value.outpost_arn
  final_snapshot       = each.value.final_snapshot

  tags = merge(
    var.tags,
    each.value.tags,
    {
      Name = "${var.name}-${each.key}"
    },
    each.value.managed_by_dlm ? { (local.dlm_target_tag_key) = local.dlm_target_tag_value } : {}
  )

  lifecycle {
    precondition {
      condition     = each.value.availability_zone != null
      error_message = "Volume \"${each.key}\" has no Availability Zone. Set it on the volume or via the module-level availability_zone."
    }
  }
}

resource "aws_volume_attachment" "this" {
  for_each = local.attachments

  device_name = each.value.device_name
  volume_id   = aws_ebs_volume.this[each.value.volume_key].id
  instance_id = each.value.instance_id

  stop_instance_before_detaching = each.value.stop_instance_before_detaching
  force_detach                   = each.value.force_detach
  skip_destroy                   = each.value.skip_destroy
}
