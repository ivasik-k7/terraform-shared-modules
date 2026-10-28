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

run "basic_plans" {
  command = plan

  module {
    source = "./examples/basic"
  }

  assert {
    condition     = module.bucket.governance.versioning
    error_message = "the basic bucket is versioned."
  }
}

run "log_bucket_plans" {
  command = plan

  module {
    source = "./examples/log-bucket"
  }

  variables {
    source_bucket_arns = ["arn:aws:s3:::app-assets-111122223333-eu-west-2"]
  }

  assert {
    condition     = !module.logs.governance.customer_key
    error_message = "a log bucket uses SSE-S3."
  }
}

run "data_lake_plans" {
  command = plan

  module {
    source = "./examples/data-lake"
  }

  variables {
    kms_key_arn        = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
    dr_bucket_arn      = "arn:aws:s3:::orders-lake-dr-111122223333-eu-west-1"
    dr_kms_key_arn     = "arn:aws:kms:eu-west-1:111122223333:key/22222222-2222-3333-4444-555555555555"
    log_bucket         = "access-logs-111122223333-eu-west-2"
    analytics_role_arn = "arn:aws:iam::444455556666:role/analytics"
    organization_id    = "o-a1b2c3d4e5"
  }

  assert {
    condition     = module.lake.governance.organization_only
    error_message = "the lake is restricted to the organization."
  }
}

run "cloudfront_origin_plans" {
  command = plan

  module {
    source = "./examples/cloudfront-origin"
  }

  variables {
    distribution_arn = "arn:aws:cloudfront::111122223333:distribution/E2EXAMPLE1"
    log_bucket       = "access-logs-111122223333-eu-west-2"
  }

  assert {
    condition     = module.site.governance.cloudfront == 1
    error_message = "one distribution reads the bucket."
  }
}
