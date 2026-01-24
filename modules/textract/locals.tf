locals {
  region_codes = {
    "us-east-1"      = "use1"
    "us-east-2"      = "use2"
    "us-west-1"      = "usw1"
    "us-west-2"      = "usw2"
    "eu-west-1"      = "euw1"
    "eu-west-2"      = "euw2"
    "eu-west-3"      = "euw3"
    "eu-central-1"   = "euc1"
    "eu-north-1"     = "eun1"
    "ap-south-1"     = "aps1"
    "ap-northeast-1" = "apne1"
    "ap-northeast-2" = "apne2"
    "ap-northeast-3" = "apne3"
    "ap-southeast-1" = "apse1"
    "ap-southeast-2" = "apse2"
    "ca-central-1"   = "cac1"
    "sa-east-1"      = "sae1"
  }

  region_code = lookup(local.region_codes, data.aws_region.current.name, data.aws_region.current.name)

  account_id_short = substr(data.aws_caller_identity.current.account_id, -4, 4)

  input_bucket_name  = split(":", var.input_bucket_arn)[5]
  output_bucket_name = var.output_bucket_arn != null ? split(":", var.output_bucket_arn)[5] : null

  # Format: {project}-{env}-{region}-{account_suffix}
  name_prefix = "${var.project_name}-${var.environment}-${local.region_code}-${local.account_id_short}"

  name_prefix_short = "${var.project_name}-${var.environment}-${local.region_code}"

  common_tags = merge(
    var.tags,
    {
      Module      = "textract"
      Environment = var.environment
      Region      = data.aws_region.current.name
      RegionCode  = local.region_code
      AccountId   = data.aws_caller_identity.current.account_id
      ManagedBy   = "Terraform"
      DeployedAt  = timestamp()
      Project     = var.project_name
    }
  )

  sns_topics = var.enable_async_processing ? {
    completion = "${local.name_prefix}-textract-job-completion-topic"
    failure    = "${local.name_prefix}-textract-job-failure-topic"
  } : {}

  resource_names = {
    iam_role               = "${local.name_prefix}-textract-service-role"
    iam_policy             = "${local.name_prefix}-textract-access-policy"
    log_group              = "/aws/textract/${var.project_name}/${var.environment}/${local.region_code}"
    alarm_error            = "${local.name_prefix}-textract-error-rate-alarm"
    alarm_throttle         = "${local.name_prefix}-textract-throttle-alarm"
    sns_completion_display = "Textract Job Completion - ${var.project_name} ${upper(var.environment)} [${upper(local.region_code)}]"
    sns_failure_display    = "Textract Job Failure - ${var.project_name} ${upper(var.environment)} [${upper(local.region_code)}]"
  }

  deployment_metadata = {
    deployed_by       = "Terraform"
    deployment_time   = timestamp()
    terraform_version = ">=1.0"
    region            = data.aws_region.current.name
    region_code       = local.region_code
    account_id        = data.aws_caller_identity.current.account_id
    partition         = data.aws_partition.current.partition
  }

  s3_resources = {
    input_bucket   = var.input_bucket_arn
    input_objects  = "${var.input_bucket_arn}/${trimprefix(var.input_bucket_prefix, "/")}*"
    output_bucket  = var.output_bucket_arn
    output_objects = var.output_bucket_arn != null ? "${var.output_bucket_arn}/${trimprefix(var.output_bucket_prefix, "/")}*" : null
  }
}
