resource "aws_iam_role" "endpoint_secret" {
  for_each = local.create ? local.endpoints_with_secret : {}

  name        = "${var.name}-${each.key}-secret"
  description = "DMS reads the ${each.key} endpoint credential from Secrets Manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      # DMS documents its regional service principal for the role that reads a secret.
      # https://docs.aws.amazon.com/dms/latest/userguide/security_iam_secretsmanager.html
      Principal = { Service = "dms.${local.region}.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike = {
          "aws:SourceArn" = "arn:${local.partition}:dms:${local.region}:${local.account_id}:*"
        }
      }
    }]
  })

  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  tags                 = local.common_tags
}

resource "aws_iam_role_policy" "endpoint_secret" {
  for_each = local.create ? local.endpoints_with_secret : {}

  name = "read-secret"
  role = aws_iam_role.endpoint_secret[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "ReadThisSecretOnly"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = [each.value.secret_arn]
        },
      ],
      each.value.secret_kms_key_arn != "" ? [
        {
          Sid      = "DecryptSecretWithCmk"
          Effect   = "Allow"
          Action   = ["kms:Decrypt"]
          Resource = [each.value.secret_kms_key_arn]
          Condition = {
            StringEquals = { "kms:ViaService" = "secretsmanager.${local.region}.amazonaws.com" }
          }
        },
      ] : [],
    )
  })
}

resource "aws_iam_role" "s3_target" {
  for_each = local.create ? local.s3_targets_needing_role : {}

  name        = "${var.name}-${each.key}-s3"
  description = "DMS writes migrated data to the ${each.value.bucket_name} bucket"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = ["dms.amazonaws.com", "dms.${local.region}.amazonaws.com"] }
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike = {
          "aws:SourceArn" = "arn:${local.partition}:dms:${local.region}:${local.account_id}:*"
        }
      }
    }]
  })

  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  tags                 = local.common_tags
}

resource "aws_iam_role_policy" "s3_target" {
  for_each = local.create ? local.s3_targets_needing_role : {}

  name = "write-target-bucket"
  role = aws_iam_role.s3_target[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "WriteMigratedObjects"
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:DeleteObject",
            "s3:PutObjectTagging",
          ]
          Resource = [
            each.value.bucket_folder != ""
            ? "arn:${local.partition}:s3:::${each.value.bucket_name}/${trimsuffix(each.value.bucket_folder, "/")}/*"
            : "arn:${local.partition}:s3:::${each.value.bucket_name}/*"
          ]
        },
        {
          Sid      = "ListTargetBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
          Resource = ["arn:${local.partition}:s3:::${each.value.bucket_name}"]
        },
      ],
      # The DMS S3 target guide grants GlueCatalogGeneration s3:GetObject on the whole bucket.
      # https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Target.S3.html
      each.value.glue_catalog_generation ? [
        {
          Sid    = "ReadForGlueCatalog"
          Effect = "Allow"
          Action = ["s3:GetObject", "s3:ListBucketMultipartUploads", "s3:ListMultipartUploadParts", "s3:AbortMultipartUpload"]
          Resource = [
            "arn:${local.partition}:s3:::${each.value.bucket_name}",
            "arn:${local.partition}:s3:::${each.value.bucket_name}/*",
          ]
        },
        {
          Sid    = "GenerateGlueCatalog"
          Effect = "Allow"
          Action = [
            "glue:CreateDatabase", "glue:GetDatabase", "glue:CreateTable", "glue:DeleteTable", "glue:UpdateTable", "glue:GetTable",
            "glue:BatchCreatePartition", "glue:CreatePartition", "glue:UpdatePartition", "glue:GetPartition", "glue:GetPartitions", "glue:BatchGetPartition",
          ]
          Resource = [
            "arn:${local.partition}:glue:${local.region}:${local.account_id}:catalog",
            "arn:${local.partition}:glue:${local.region}:${local.account_id}:database/*",
            "arn:${local.partition}:glue:${local.region}:${local.account_id}:table/*",
          ]
        },
        {
          Sid      = "QueryForGlueCatalog"
          Effect   = "Allow"
          Action   = ["athena:StartQueryExecution", "athena:GetQueryExecution", "athena:CreateWorkGroup"]
          Resource = ["arn:${local.partition}:athena:${local.region}:${local.account_id}:workgroup/glue_catalog_generation_for_task_*"]
        },
      ] : [],
      each.value.encryption_mode == "SSE_KMS" && each.value.kms_key_arn != "" ? [
        {
          Sid      = "EncryptWithTargetKey"
          Effect   = "Allow"
          Action   = ["kms:GenerateDataKey", "kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
          Resource = [each.value.kms_key_arn]
        },
      ] : [],
    )
  })
}

resource "aws_iam_role" "dms_vpc" {
  count = local.create && var.create_account_service_roles ? 1 : 0

  name        = "dms-vpc-role"
  description = "Account-wide role DMS uses to manage ENIs in your VPC"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "dms.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "dms_vpc" {
  count = local.create && var.create_account_service_roles ? 1 : 0

  role       = aws_iam_role.dms_vpc[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

resource "aws_iam_role" "dms_cloudwatch_logs" {
  count = local.create && var.create_account_service_roles ? 1 : 0

  name        = "dms-cloudwatch-logs-role"
  description = "Account-wide role DMS uses to publish task logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "dms.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch_logs" {
  count = local.create && var.create_account_service_roles ? 1 : 0

  role       = aws_iam_role.dms_cloudwatch_logs[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

resource "aws_iam_role" "assessment" {
  count = local.create_assessment_role ? 1 : 0

  name        = "${var.name}-assessment"
  description = "DMS writes premigration assessment reports for the ${var.name} migration"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "dms.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })

  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  tags                 = local.common_tags
}

resource "aws_iam_role_policy" "assessment" {
  count = local.create_assessment_role ? 1 : 0

  name = "write-assessment-reports"
  role = aws_iam_role.assessment[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "WriteAssessmentReports"
          Effect   = "Allow"
          Action   = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject", "s3:PutObjectTagging"]
          Resource = ["arn:${local.partition}:s3:::${var.premigration_assessment.bucket_name}/${var.premigration_assessment.bucket_folder}/*"]
        },
        {
          Sid      = "LocateAssessmentBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
          Resource = ["arn:${local.partition}:s3:::${var.premigration_assessment.bucket_name}"]
        },
      ],
      var.premigration_assessment.kms_key_arn == "" ? [] : [{
        Sid      = "EncryptAssessmentReports"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = [var.premigration_assessment.kms_key_arn]
        Condition = {
          StringEquals = { "kms:ViaService" = "s3.${local.region}.amazonaws.com" }
        }
      }],
    )
  })
}

resource "aws_iam_role" "dms_access_for_endpoint" {
  count = local.create && var.create_account_service_roles && local.has_redshift_target ? 1 : 0

  name        = "dms-access-for-endpoint"
  description = "Account-wide role DMS uses to stage Redshift loads through S3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = ["dms.amazonaws.com", "redshift-serverless.amazonaws.com"] }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "dms_access_for_endpoint" {
  count = length(aws_iam_role.dms_access_for_endpoint)

  role       = aws_iam_role.dms_access_for_endpoint[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonDMSRedshiftS3Role"
}
