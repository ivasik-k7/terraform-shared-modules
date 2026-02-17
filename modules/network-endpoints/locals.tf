locals {
  # ---------------------------------------------------------------------------
  # AWS Managed Service → endpoint type lookup table.
  # Keys are the short aliases users pass in var.endpoints[*].service.
  # Values describe the endpoint type and the com.amazonaws.<region>.<svc> suffix.
  # ---------------------------------------------------------------------------
  service_catalog = {
    # ── Compute ──────────────────────────────────────────────────────────────
    ec2             = { type = "Interface", suffix = "ec2" }
    ec2messages     = { type = "Interface", suffix = "ec2messages" }
    ec2_autoscaling = { type = "Interface", suffix = "autoscaling" }
    ebs             = { type = "Interface", suffix = "ebs" }
    ecs             = { type = "Interface", suffix = "ecs" }
    ecs_agent       = { type = "Interface", suffix = "ecs-agent" }
    ecs_telemetry   = { type = "Interface", suffix = "ecs-telemetry" }
    eks             = { type = "Interface", suffix = "eks" }
    eks_auth        = { type = "Interface", suffix = "eks-auth" }
    lambda          = { type = "Interface", suffix = "lambda" }
    batch           = { type = "Interface", suffix = "batch" }
    app_runner      = { type = "Interface", suffix = "apprunner" }

    # ── Storage ───────────────────────────────────────────────────────────────
    s3           = { type = "Gateway", suffix = "s3" }
    s3_interface = { type = "Interface", suffix = "s3" }
    dynamodb     = { type = "Gateway", suffix = "dynamodb" }
    efs          = { type = "Interface", suffix = "elasticfilesystem" }
    fsx          = { type = "Interface", suffix = "fsx" }
    backup       = { type = "Interface", suffix = "backup" }
    glacier      = { type = "Interface", suffix = "glacier" }

    # ── Networking ────────────────────────────────────────────────────────────
    ssm             = { type = "Interface", suffix = "ssm" }
    ssmmessages     = { type = "Interface", suffix = "ssmmessages" }
    route53         = { type = "Interface", suffix = "route53" }
    route53resolver = { type = "Interface", suffix = "route53resolver" }
    vpc_lattice     = { type = "Interface", suffix = "vpc-lattice" }
    privatelink     = { type = "Interface", suffix = "aws-marketplace" }
    transitgateway  = { type = "Interface", suffix = "ec2" }

    # ── Security & Identity ───────────────────────────────────────────────────
    sts             = { type = "Interface", suffix = "sts" }
    iam             = { type = "Interface", suffix = "iam" }
    secretsmanager  = { type = "Interface", suffix = "secretsmanager" }
    kms             = { type = "Interface", suffix = "kms" }
    acm             = { type = "Interface", suffix = "acm" }
    acm_pca         = { type = "Interface", suffix = "acm-pca" }
    inspector       = { type = "Interface", suffix = "inspector2" }
    inspector_scan  = { type = "Interface", suffix = "inspector-scan" }
    guardduty       = { type = "Interface", suffix = "guardduty-data" }
    macie           = { type = "Interface", suffix = "macie2" }
    config          = { type = "Interface", suffix = "config" }
    access_analyzer = { type = "Interface", suffix = "access-analyzer" }

    # ── Messaging & Streaming ─────────────────────────────────────────────────
    sqs              = { type = "Interface", suffix = "sqs" }
    sns              = { type = "Interface", suffix = "sns" }
    kinesis_streams  = { type = "Interface", suffix = "kinesis-streams" }
    kinesis_firehose = { type = "Interface", suffix = "kinesis-firehose" }
    kafka            = { type = "Interface", suffix = "kafka" }
    kafka_bootstrap  = { type = "Interface", suffix = "kafka-bootstrap" }
    eventbridge      = { type = "Interface", suffix = "events" }
    sqs_fips         = { type = "Interface", suffix = "sqs-fips" }

    # ── Databases ─────────────────────────────────────────────────────────────
    rds              = { type = "Interface", suffix = "rds" }
    rds_data         = { type = "Interface", suffix = "rds-data" }
    redshift         = { type = "Interface", suffix = "redshift" }
    redshift_data    = { type = "Interface", suffix = "redshift-data" }
    elasticache      = { type = "Interface", suffix = "elasticache" }
    memorydb         = { type = "Interface", suffix = "memory-db" }
    timestream       = { type = "Interface", suffix = "timestream-influxdb" }
    timestream_query = { type = "Interface", suffix = "timestream-query" }
    timestream_write = { type = "Interface", suffix = "timestream-write" }

    # ── CI/CD & Developer Tools ───────────────────────────────────────────────
    codecommit        = { type = "Interface", suffix = "codecommit" }
    codecommit_git    = { type = "Interface", suffix = "git-codecommit" }
    codebuild         = { type = "Interface", suffix = "codebuild" }
    codedeploy        = { type = "Interface", suffix = "codedeploy" }
    codedeploy_cmds   = { type = "Interface", suffix = "codedeploy-commands-secure" }
    codepipeline      = { type = "Interface", suffix = "codepipeline" }
    codeartifact_api  = { type = "Interface", suffix = "codeartifact.api" }
    codeartifact_repo = { type = "Interface", suffix = "codeartifact.repositories" }
    ecr_api           = { type = "Interface", suffix = "ecr.api" }
    ecr_dkr           = { type = "Interface", suffix = "ecr.dkr" }

    # ── Management & Monitoring ───────────────────────────────────────────────
    cloudwatch        = { type = "Interface", suffix = "monitoring" }
    cloudwatch_logs   = { type = "Interface", suffix = "logs" }
    cloudwatch_events = { type = "Interface", suffix = "events" }
    cloudtrail        = { type = "Interface", suffix = "cloudtrail" }
    xray              = { type = "Interface", suffix = "xray" }
    cloudformation    = { type = "Interface", suffix = "cloudformation" }
    systems_manager   = { type = "Interface", suffix = "ssm" }

    # ── ML / AI ───────────────────────────────────────────────────────────────
    sagemaker_api          = { type = "Interface", suffix = "sagemaker.api" }
    sagemaker_runtime      = { type = "Interface", suffix = "sagemaker.runtime" }
    sagemaker_featurestore = { type = "Interface", suffix = "sagemaker.featurestore-runtime" }
    bedrock                = { type = "Interface", suffix = "bedrock" }
    bedrock_runtime        = { type = "Interface", suffix = "bedrock-runtime" }
    bedrock_agent          = { type = "Interface", suffix = "bedrock-agent" }
    bedrock_agent_runtime  = { type = "Interface", suffix = "bedrock-agent-runtime" }
    rekognition            = { type = "Interface", suffix = "rekognition" }
    textract               = { type = "Interface", suffix = "textract" }
    comprehend             = { type = "Interface", suffix = "comprehend" }
    transcribe             = { type = "Interface", suffix = "transcribe" }
    translate              = { type = "Interface", suffix = "translate" }
    polly                  = { type = "Interface", suffix = "polly" }

    # ── Analytics ─────────────────────────────────────────────────────────────
    athena        = { type = "Interface", suffix = "athena" }
    glue          = { type = "Interface", suffix = "glue" }
    emr           = { type = "Interface", suffix = "elasticmapreduce" }
    lakeformation = { type = "Interface", suffix = "lakeformation" }
    dataexchange  = { type = "Interface", suffix = "dataexchange" }
    quicksight    = { type = "Interface", suffix = "quicksight" }

    # ── Application Services ───────────────────────────────────────────────────
    apigw   = { type = "Interface", suffix = "execute-api" }
    appsync = { type = "Interface", suffix = "appsync-api" }
    elb     = { type = "Interface", suffix = "elasticloadbalancing" }
    ses     = { type = "Interface", suffix = "email-smtp" }
    sfn     = { type = "Interface", suffix = "states" }
    swf     = { type = "Interface", suffix = "swf" }
    iot     = { type = "Interface", suffix = "iot.data" }
    iotcore = { type = "Interface", suffix = "iot.credentials" }

    # ── Migration & Transfer ───────────────────────────────────────────────────
    dms      = { type = "Interface", suffix = "dms" }
    transfer = { type = "Interface", suffix = "transfer" }
    datasync = { type = "Interface", suffix = "datasync" }
    snowball = { type = "Interface", suffix = "snowball" }

    # ── Media ─────────────────────────────────────────────────────────────────
    mediaconnect = { type = "Interface", suffix = "mediaconnect" }
    medialive    = { type = "Interface", suffix = "medialive" }
    mediapackage = { type = "Interface", suffix = "mediapackage" }
    mediatailor  = { type = "Interface", suffix = "mediatailor" }

    # ── End-User Computing ─────────────────────────────────────────────────────
    workspaces = { type = "Interface", suffix = "workspaces" }
    appstream  = { type = "Interface", suffix = "appstream.api" }
  }

  # ---------------------------------------------------------------------------
  # Resolve each endpoint configuration
  # ---------------------------------------------------------------------------
  resolved_endpoints = {
    for key, cfg in var.endpoints : key => merge(
      can(local.service_catalog[cfg.service]) ? {
        endpoint_type = local.service_catalog[cfg.service].type
        service_name  = "com.amazonaws.${var.region}.${local.service_catalog[cfg.service].suffix}"
        } : {
        endpoint_type = try(cfg.type, "Interface")
        service_name  = cfg.service
      },
      {
        key                 = key
        enabled             = try(cfg.enabled, true)
        private_dns_enabled = try(cfg.private_dns_enabled, true)
        auto_accept         = try(cfg.auto_accept, false)
        ip_address_type     = try(cfg.ip_address_type, null)
        policy              = try(cfg.policy, null)
        subnet_ids          = try(cfg.subnet_ids, var.default_subnet_ids)
        security_group_ids  = try(cfg.security_group_ids, null)
        route_table_ids     = try(cfg.route_table_ids, var.default_route_table_ids)
        tags                = merge(var.tags, try(cfg.tags, {}))
        timeouts            = try(cfg.timeouts, {})
        notification_arns   = try(cfg.notification_arns, [])
      }
    )
    if try(cfg.enabled, true)
  }

  interface_endpoints = {
    for k, v in local.resolved_endpoints : k => v
    if v.endpoint_type == "Interface"
  }

  gateway_endpoints = {
    for k, v in local.resolved_endpoints : k => v
    if v.endpoint_type == "Gateway"
  }

  gwlb_endpoints = {
    for k, v in local.resolved_endpoints : k => v
    if v.endpoint_type == "GatewayLoadBalancer"
  }

  create_default_sg = var.create_default_security_group && length(local.interface_endpoints) > 0

  effective_sg_ids = {
    for k, v in local.interface_endpoints : k => compact(concat(
      local.create_default_sg ? [aws_security_group.default[0].id] : [],
      coalesce(v.security_group_ids, []),
    ))
  }
}
