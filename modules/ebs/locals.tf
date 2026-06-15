locals {
  # Resolve the KMS key each volume should use:
  #   created key  ->  existing kms_key_id  ->  default AWS-managed key (null)
  resolved_kms_key_id = var.create_kms_key ? aws_kms_key.ebs[0].arn : var.kms_key_id

  # Normalise the volumes map so downstream resources can rely on resolved values.
  volumes = {
    for k, v in var.volumes : k => merge(v, {
      # try(...) avoids a cryptic coalesce error when no AZ is set anywhere;
      # the aws_ebs_volume precondition surfaces a clear message instead.
      availability_zone = try(coalesce(v.availability_zone, var.availability_zone), null)
      encrypted         = coalesce(v.encrypted, var.encrypted)
      # When encrypted, use a CMK if one is provided/created; otherwise leave
      # null so AWS applies the default aws/ebs managed key. kms_key_id must be
      # a key ARN/ID — never an alias name.
      kms_key_id = coalesce(v.encrypted, var.encrypted) ? try(coalesce(v.kms_key_id, local.resolved_kms_key_id), null) : null
    })
  }

  # Combine the ergonomic single-instance shortcut with any explicit multi-attach
  # targets into one normalised attachment list per volume.
  _volume_attachments = {
    for k, v in local.volumes : k => concat(
      v.instance_id != null ? [{
        instance_id                    = v.instance_id
        device_name                    = v.device_name
        stop_instance_before_detaching = v.stop_instance_before_detaching
        force_detach                   = v.force_detach
        skip_destroy                   = v.skip_destroy
      }] : [],
      v.attachments
    )
  }

  # Flatten to a map keyed by "<volume>.<index>". The index is used (not
  # instance_id) so for_each keys stay known at plan time even when instance_id
  # is a computed value (e.g. aws_instance.x.id created in the same apply).
  # Trade-off: appending attachments is safe; removing/reordering earlier list
  # entries shifts indices and will detach/reattach the later volumes.
  attachments = merge([
    for vk, atts in local._volume_attachments : {
      for idx, a in atts : "${vk}.${idx}" => merge(a, { volume_key = vk })
    }
  ]...)

  dlm_target_tag_key   = "EbsModuleDlmGroup"
  dlm_target_tag_value = var.name

  lifecycle_policy_description = coalesce(
    var.lifecycle_policy_description,
    "Automated EBS snapshot lifecycle for ${var.name}"
  )

  # gp2/st1/sc1 volumes expose the BurstBalance metric; gp3/io1/io2 do not.
  burst_balance_volumes = {
    for k, v in local.volumes : k => v
    if contains(["gp2", "st1", "sc1"], v.type)
  }
}
