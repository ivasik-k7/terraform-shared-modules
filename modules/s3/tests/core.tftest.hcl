# mock_provider reports no replacement and evaluates no bucket policy: the policy is asserted as data.
mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { endpoint = "ec2.eu-west-2.amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
}

variables {
  name           = "orders-data"
  kms_key_arn    = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
  access_logging = { target_bucket = "central-logs-111122223333-eu-west-2" }
  tags           = { CostCentre = "cc-1234" }

  every_check = [
    "versioning_is_on", "old_versions_expire", "access_is_logged", "data_uses_a_customer_key",
    "the_bucket_survives_a_destroy", "acls_are_disabled", "replication_is_monitored",
  ]
}

run "the_name_carries_the_account_and_region" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket.this[0].bucket == "orders-data-111122223333-eu-west-2",
      aws_s3_bucket.this[0].force_destroy == false,
    ])
    error_message = "the name ends in -<account>-<region>, and a destroy keeps a non-empty bucket."
  }
}

run "a_name_without_suffix_is_used_as_given" {
  command = plan

  variables {
    name_suffix = "none"
  }

  assert {
    condition     = aws_s3_bucket.this[0].bucket == "orders-data"
    error_message = "name_suffix none uses the name as given."
  }
}

run "a_name_too_long_for_the_suffix_is_refused" {
  command = plan

  variables {
    name = "orders-data-for-the-ledger-reconciliation-team"
  }

  expect_failures = [aws_s3_bucket.this]
}

run "a_name_with_dots_or_a_reserved_affix_is_rejected" {
  command = plan

  variables {
    name = "xn--orders"
  }

  expect_failures = [var.name]
}

run "a_name_ending_in_the_reserved_namespace_suffix_is_rejected" {
  command = plan

  variables {
    name = "orders-an"
  }

  expect_failures = [var.name]
}

run "a_customer_key_encrypts_with_a_bucket_key" {
  command = plan

  assert {
    condition = alltrue([
      one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms",
      one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).apply_server_side_encryption_by_default[0].kms_master_key_id == "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555",
      one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).bucket_key_enabled == true,
    ])
    error_message = "SSE-KMS with the key and an S3 Bucket Key."
  }
}

run "without_a_key_it_is_sse_s3_and_warns" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "no key means SSE-S3."
  }

  expect_failures = [check.data_uses_a_customer_key]
}

run "dsse_drops_the_bucket_key" {
  command = plan

  variables {
    encryption = { dsse = true }
  }

  assert {
    condition = alltrue([
      one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms:dsse",
      one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).bucket_key_enabled == false,
    ])
    error_message = "DSSE-KMS, without a bucket key (S3 Bucket Keys do not apply to it)."
  }
}

run "dsse_without_a_key_is_refused" {
  command = plan

  variables {
    kms_key_arn         = ""
    encryption          = { dsse = true }
    acknowledged_checks = var.every_check
  }

  expect_failures = [aws_s3_bucket.this]
}

run "a_key_in_another_region_is_refused" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-1:111122223333:key/11111111-2222-3333-4444-555555555555"
  }

  expect_failures = [aws_s3_bucket.this]
}

run "public_access_is_blocked_and_acls_disabled" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this[0].block_public_acls,
      aws_s3_bucket_public_access_block.this[0].block_public_policy,
      aws_s3_bucket_public_access_block.this[0].ignore_public_acls,
      aws_s3_bucket_public_access_block.this[0].restrict_public_buckets,
      aws_s3_bucket_ownership_controls.this[0].rule[0].object_ownership == "BucketOwnerEnforced",
    ])
    error_message = "all four Block Public Access settings, set explicitly, and ACLs disabled."
  }
}

run "relaxing_public_access_needs_an_acknowledgement" {
  command = plan

  variables {
    public_access_block = { block_public_policy = false }
  }

  expect_failures = [aws_s3_bucket.this]
}

run "the_policy_denies_plaintext_and_old_tls_but_not_aws_services" {
  command = plan

  assert {
    condition = alltrue([
      for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
      !contains(["DenyInsecureTransport", "DenyOldTls"], st.Sid) ? true : (
        st.Effect != "Deny" ? false : (
          st.Principal != "*" ? false : st.Condition.BoolIfExists["aws:PrincipalIsAWSService"] == ["false"]
        )
      )
    ])
    error_message = "both network denies apply to everyone except AWS services acting for the account, whose requests carry no TLS context."
  }

  assert {
    condition = anytrue([
      for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
      st.Sid == "DenyInsecureTransport" ? st.Condition.Bool["aws:SecureTransport"] == ["false"] : false
    ])
    error_message = "plain HTTP is denied."
  }

  assert {
    condition = anytrue([
      for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
      st.Sid == "DenyOldTls" ? st.Condition.NumericLessThan["s3:TlsVersion"] == ["1.2"] : false
    ])
    error_message = "TLS older than 1.2 is denied."
  }
}

run "only_explicitly_other_encryption_is_denied" {
  command = plan

  assert {
    condition = anytrue([
      for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
      st.Sid != "DenyOtherKmsKeys" ? false : (
        st.Condition.Null["s3:x-amz-server-side-encryption-aws-kms-key-id"] != ["false"] ? false :
        st.Condition.StringNotEquals["s3:x-amz-server-side-encryption-aws-kms-key-id"] == ["arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"]
      )
    ])
    error_message = "a PutObject naming another key is denied; one naming none is not."
  }

  assert {
    condition = anytrue([
      for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
      st.Sid != "DenyOtherEncryption" ? false : (
        st.Condition.Null["s3:x-amz-server-side-encryption"] != ["false"] ? false :
        st.Condition.StringNotEquals["s3:x-amz-server-side-encryption"] == ["aws:kms"]
      )
    ])
    error_message = "a PutObject naming another algorithm is denied; one naming aws:kms is not."
  }

  assert {
    condition = anytrue([
      for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
      st.Sid != "DenyAwsManagedKey" ? false : (
        st.Condition.StringEquals["s3:x-amz-server-side-encryption"] != ["aws:kms"] ? false :
        st.Condition.Null["s3:x-amz-server-side-encryption-aws-kms-key-id"] == ["true"]
      )
    ])
    error_message = "a PutObject asking for aws:kms without naming the key is denied: S3 would use aws/s3."
  }
}

run "a_cross_account_grant_is_scoped_to_its_prefixes" {
  command = plan

  variables {
    grants = {
      analytics = { principals = ["arn:aws:iam::444455556666:role/analytics"], access = "read", prefixes = ["exports/"] }
    }
  }

  assert {
    condition = alltrue([
      anytrue([for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
        st.Sid != "analyticsObjects" ? false : (
          jsonencode(st.Resource) != jsonencode(["arn:aws:s3:::orders-data-111122223333-eu-west-2/exports/*"]) ? false : !contains(st.Action, "s3:PutObject")
        )
      ]),
      anytrue([for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
        st.Sid != "analyticsList" ? false : st.Condition.StringLike["s3:prefix"] == ["exports/*"]
      ]),
      anytrue([for r in output.kms_key_policy_requirements : r.sid == "Grantanalytics" ? jsonencode(r.actions) == jsonencode(["kms:Decrypt"]) : false]),
    ])
    error_message = "a read grant reads only under its prefix, lists only that prefix, and its principal is in the key contract with Decrypt only."
  }
}

run "a_public_policy_statement_is_rejected" {
  command = plan

  variables {
    policy_statements = [{ sid = "Everyone", principals = { AWS = ["*"] }, actions = ["s3:GetObject"], resources = ["OBJECTS_ARN"] }]
  }

  expect_failures = [var.policy_statements]
}

run "caller_statements_resolve_the_placeholders" {
  command = plan

  variables {
    policy_statements = [{
      sid        = "DenyDeletesOfAudit"
      effect     = "Deny"
      principals = { AWS = ["*"] }
      actions    = ["s3:DeleteObject"]
      resources  = ["OBJECTS_ARN"]
    }]
  }

  assert {
    condition = anytrue([for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
      st.Sid == "DenyDeletesOfAudit" ? jsonencode(st.Resource) == jsonencode(["arn:aws:s3:::orders-data-111122223333-eu-west-2/*"]) : false
    ])
    error_message = "OBJECTS_ARN becomes the bucket's object ARN."
  }
}

run "cloudfront_reads_through_origin_access_control" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["arn:aws:cloudfront::111122223333:distribution/E2EXAMPLE1"]
  }

  assert {
    condition = anytrue([for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
      st.Sid != "CloudFrontOriginAccessControl" ? false : (
        st.Principal.Service != ["cloudfront.amazonaws.com"] ? false : st.Condition.StringEquals["AWS:SourceArn"] == ["arn:aws:cloudfront::111122223333:distribution/E2EXAMPLE1"]
      )
    ])
    error_message = "CloudFront may GetObject for that distribution only."
  }

  assert {
    condition     = anytrue([for r in output.kms_key_policy_requirements : r.sid == "CloudFrontOriginAccessControl"])
    error_message = "CloudFront is in the key contract."
  }
}

run "the_vpc_endpoint_perimeter_covers_object_data_only" {
  command = plan

  variables {
    vpc_endpoint_ids = ["vpce-0123456789abcdef0"]
  }

  assert {
    condition = anytrue([for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
      st.Sid != "DenyObjectAccessOutsideVpcEndpoints" ? false : (
        contains(st.Action, "s3:PutBucketPolicy") || contains(st.Action, "s3:*") ? false : st.Condition.StringNotEqualsIfExists["aws:SourceVpce"] == ["vpce-0123456789abcdef0"]
      )
    ])
    error_message = "the perimeter denies object reads and writes outside the endpoint, never bucket configuration - the module cannot lock out its deployer."
  }

  assert {
    condition = anytrue([for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
      st.Sid == "DenyObjectAccessOutsideVpcEndpoints" ? st.Condition.BoolIfExists["aws:ViaAWSService"] == ["false"] : false
    ])
    error_message = "requests a service makes for the caller (forward access sessions) are exempt from the endpoint perimeter."
  }
}

run "cloudfront_with_acls_still_required_is_allowed" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["arn:aws:cloudfront::111122223333:distribution/E2EXAMPLE1"]
    object_ownership             = "BucketOwnerPreferred"
    acknowledged_checks          = ["acls_are_disabled"]
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this[0].rule[0].object_ownership == "BucketOwnerPreferred"
    error_message = "BucketOwnerPreferred is accepted with CloudFront."
  }
}

run "cloudfront_with_object_writer_is_refused" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["arn:aws:cloudfront::111122223333:distribution/E2EXAMPLE1"]
    object_ownership             = "ObjectWriter"
    acknowledged_checks          = ["acls_are_disabled"]
  }

  expect_failures = [aws_s3_bucket.this]
}

run "a_policy_statement_without_principals_is_rejected" {
  command = plan

  variables {
    policy_statements = [{ sid = "NoOne", actions = ["s3:GetObject"], resources = ["OBJECTS_ARN"] }]
  }

  expect_failures = [var.policy_statements]
}

run "the_organization_perimeter_exempts_this_account_and_services" {
  command = plan

  variables {
    organization_id = "o-a1b2c3d4e5"
  }

  assert {
    condition = anytrue([for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
      st.Sid != "DenyObjectAccessOutsideOrganization" ? false : (
        st.Condition.StringNotEquals["aws:PrincipalAccount"] != ["111122223333"] ? false : st.Condition.BoolIfExists["aws:PrincipalIsAWSService"] == ["false"]
      )
    ])
    error_message = "principals outside the organization are denied object access; this account and AWS services are not."
  }
}

run "object_lock_is_enabled_in_place_not_by_replacement" {
  command = plan

  variables {
    object_lock = { enabled = true, mode = "COMPLIANCE", years = 7 }
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_object_lock_configuration.this[0].object_lock_enabled == "Enabled",
      aws_s3_bucket_object_lock_configuration.this[0].rule[0].default_retention[0].mode == "COMPLIANCE",
      aws_s3_bucket_object_lock_configuration.this[0].rule[0].default_retention[0].years == 7,
    ])
    error_message = "Object Lock comes from the configuration resource (an in-place change), never from the bucket's object_lock_enabled, which forces a replacement."
  }
}

run "object_lock_without_versioning_is_refused" {
  command = plan

  variables {
    versioning          = false
    object_lock         = { enabled = true, days = 30 }
    acknowledged_checks = var.every_check
  }

  expect_failures = [aws_s3_bucket.this]
}

run "versioning_off_suspends_and_warns" {
  command = plan

  variables {
    versioning = false
  }

  assert {
    condition     = aws_s3_bucket_versioning.this[0].versioning_configuration[0].status == "Suspended"
    error_message = "turning versioning off suspends it."
  }

  expect_failures = [check.versioning_is_on]
}

run "force_destroy_warns" {
  command = plan

  variables {
    force_destroy = true
  }

  expect_failures = [check.the_bucket_survives_a_destroy]
}

run "acls_enabled_warn" {
  command = plan

  variables {
    object_ownership = "BucketOwnerPreferred"
  }

  expect_failures = [check.acls_are_disabled]
}

run "create_false_plans_nothing" {
  command = plan

  variables {
    create      = false
    replication = { rules = { dr = { destination_bucket_arn = "arn:aws:s3:::dr-bucket", replica_kms_key_arn = "arn:aws:kms:eu-west-1:111122223333:key/22222222-2222-3333-4444-555555555555" } } }
  }

  assert {
    condition = alltrue([
      length(aws_s3_bucket.this) == 0, length(aws_s3_bucket_policy.this) == 0,
      length(aws_iam_role.replication) == 0, length(aws_s3_bucket_lifecycle_configuration.this) == 0,
    ])
    error_message = "create = false plans no resource."
  }

  assert {
    condition = alltrue([
      output.bucket == null, output.arn == null, output.read_policy_json == null, output.write_policy_json == null,
      output.kms_key_policy_requirements == null, output.governance == null, output.verify_commands == null,
      output.replication_destination_requirements == null, output.replication_role_arn == null,
    ])
    error_message = "create = false leaves every output null."
  }
}

run "the_consumer_policies_carry_the_key" {
  command = plan

  assert {
    condition = alltrue([
      anytrue([for st in jsondecode(output.read_policy_json).Statement : st.Sid == "DecryptObjects" ? st.Condition.StringEquals["kms:ViaService"] == "s3.eu-west-2.amazonaws.com" : false]),
      anytrue([for st in jsondecode(output.write_policy_json).Statement : st.Sid == "EncryptObjects" ? contains(st.Action, "kms:GenerateDataKey") : false]),
      !anytrue([for st in jsondecode(output.read_policy_json).Statement : contains(st.Action, "s3:PutObject")]),
    ])
    error_message = "readers decrypt through S3 and cannot write; writers can encrypt."
  }
}
