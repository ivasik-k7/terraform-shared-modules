# The engine side of IAM database authentication. output.iam_database_auth
# tells the DBA what SQL to run; with create_iam_database_users the module
# runs it, so a user in iam_database_users exists in the engine after the
# apply that declared it, and leaves it the way its on_remove says.
#
# How: a module-owned Lambda function calls the RDS Data API. Terraform never
# opens a connection to the database and never holds a password - Data API
# reads the admin secret itself - and the function needs no VPC, because Data
# API is an HTTPS endpoint. The price is that enable_data_api has to be on.
#
# aws_lambda_invocation with lifecycle_scope = "CRUD" invokes the function on
# create with the users, on every change to the input with the previous input
# alongside (so a user that left the map is handled), and on destroy. The SQL
# is idempotent: an invocation that finds everything in place changes nothing.
#
# Proxy users (connect_via = "proxy") are not created here: they are password
# users whose secret the caller owns, and output.iam_database_auth says so.

locals {
  create_iam_db_users = local.create && var.create_iam_database_users

  # The secret Data API logs in with. The RDS-managed master secret unless the
  # caller brings one (a global primary, which cannot have the managed secret,
  # or a least-privilege CREATEROLE user).
  iam_db_admin_secret_arn         = var.iam_database_users_admin_secret.arn != "" ? var.iam_database_users_admin_secret.arn : local.managed_secret_arn
  iam_db_admin_secret_kms_key_arn = var.iam_database_users_admin_secret.arn != "" ? var.iam_database_users_admin_secret.kms_key_arn : local.master_secret_kms_key_arn

  iam_db_users_function_name = "${var.name}-dbusers"
  iam_db_users_log_group     = "/aws/lambda/${local.iam_db_users_function_name}"

  # The invocation's input. Cluster users only; the secret ARN is known after
  # the cluster exists, which is also when the invocation can run.
  iam_db_users_input = {
    cluster_arn = local.cluster_arn
    secret_arn  = local.iam_db_admin_secret_arn
    engine      = local.is_postgres ? "postgres" : "mysql"
    database    = local.is_postgres ? coalesce(one(aws_rds_cluster.this[*].database_name), "postgres") : ""
    users       = { for u, c in var.iam_database_users : u => { on_remove = c.on_remove } if c.connect_via == "cluster" }
  }

  # What the last invocation reported, per user; null until applied, and
  # under a mocked provider.
  iam_db_users_result = try(jsondecode(one(aws_lambda_invocation.iam_database_users[*].result)).users, null)
}

data "archive_file" "iam_database_users" {
  count = local.create_iam_db_users ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/lambda/iam_database_users/index.py"
  output_path = "${path.module}/lambda/iam_database_users.zip"
}

resource "aws_iam_role" "iam_database_users" {
  count = local.create_iam_db_users ? 1 : 0

  name                 = "${var.name}-${local.region}-dbusers"
  path                 = var.iam_role_path
  description          = "Creates the IAM database users of Aurora cluster ${var.name} through the RDS Data API"
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null

  # The trust policy AWS documents for a Lambda execution role. No
  # SourceAccount condition: the Lambda documentation does not list one for
  # the execution role, and a condition on a key the service does not send is
  # a function that never starts.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "LambdaExecution"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

# Exactly what one invocation does: one Data API action on this cluster, one
# secret, its key through Secrets Manager, and its own log group.
resource "aws_iam_role_policy" "iam_database_users" {
  count = local.create_iam_db_users ? 1 : 0

  name = "create-database-users"
  role = aws_iam_role.iam_database_users[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "ExecuteOnThisCluster"
          Effect   = "Allow"
          Action   = ["rds-data:ExecuteStatement"]
          Resource = [local.cluster_arn]
        },
        {
          Sid      = "ReadAdminSecret"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = [local.iam_db_admin_secret_arn]
        },
        {
          Sid      = "WriteOwnLogs"
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.iam_db_users_log_group}:*"]
        },
      ],
      # An AWS-managed secret key grants this through its own key policy. A
      # customer key has to be named here, and in its policy - see
      # output.kms_key_policy_requirements (MasterSecretReaders).
      local.iam_db_admin_secret_kms_key_arn == "" ? [] : [{
        Sid      = "DecryptAdminSecret"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [local.iam_db_admin_secret_kms_key_arn]
        Condition = {
          StringEquals = { "kms:ViaService" = "secretsmanager.${local.region}.amazonaws.com" }
        }
      }],
    )
  })
}

resource "aws_cloudwatch_log_group" "iam_database_users" {
  count = local.create_iam_db_users ? 1 : 0

  name              = local.iam_db_users_log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = local.logs_kms_key_arn != "" ? local.logs_kms_key_arn : null
  log_group_class   = var.log_group_class
  skip_destroy      = var.log_group_skip_destroy

  tags = local.common_tags
}

resource "aws_lambda_function" "iam_database_users" {
  count = local.create_iam_db_users ? 1 : 0

  function_name    = local.iam_db_users_function_name
  description      = "Creates the IAM database users of Aurora cluster ${var.name} through the RDS Data API"
  role             = aws_iam_role.iam_database_users[0].arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = "index.handler"
  filename         = data.archive_file.iam_database_users[0].output_path
  source_code_hash = data.archive_file.iam_database_users[0].output_base64sha256
  # Long enough to wait out a paused Serverless v2 instance resuming.
  timeout     = 300
  memory_size = 128

  tags = local.common_tags

  # The group first, with retention and key, so the first log line does not
  # create an unbounded group under the AWS-managed key.
  depends_on = [aws_cloudwatch_log_group.iam_database_users]
}

resource "aws_lambda_invocation" "iam_database_users" {
  count = local.create_iam_db_users ? 1 : 0

  function_name   = aws_lambda_function.iam_database_users[0].function_name
  lifecycle_scope = "CRUD"
  input           = jsonencode(local.iam_db_users_input)

  # Data API needs a writer instance, and the policy must exist before the
  # first call, not merely before the function.
  depends_on = [aws_rds_cluster_instance.this, aws_iam_role_policy.iam_database_users]
}
