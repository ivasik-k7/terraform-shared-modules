resource "aws_kms_key" "dms" {
  description = "orders migration"
}

resource "aws_secretsmanager_secret" "source" {
  name       = "orders/dms/source"
  kms_key_id = aws_kms_key.dms.arn
}

resource "aws_secretsmanager_secret" "target" {
  name       = "orders/dms/target"
  kms_key_id = aws_kms_key.dms.arn
}

resource "aws_sns_topic" "alerts" {
  name = "orders-migration"
}

resource "aws_iam_role" "dms_secrets" {
  name               = "orders-dms-secrets"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "dms.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}

resource "aws_iam_role" "dms_lake" {
  name               = "orders-dms-lake"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "dms.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}

module "dms" {
  source = "../../.."

  name               = "orders"
  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  security_group_ids = ["sg-0123456789abcdef0"]
  engine_version     = "3.5.3"
  kms_key_arn        = aws_kms_key.dms.arn
  sns_topic_arn      = aws_sns_topic.alerts.arn

  certificates = {
    rds-ca = { pem = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----" }
  }

  endpoints = {
    source-db = {
      role               = "source"
      engine             = "postgres"
      server_name        = "src.example.com"
      port               = 5432
      database_name      = "app"
      secret_arn         = aws_secretsmanager_secret.source.arn
      secret_kms_key_arn = aws_kms_key.dms.arn
      ssl_mode           = "verify-full"
      certificate_key    = "rds-ca"
    }
    target-db = {
      role                   = "target"
      engine                 = "aurora-postgresql"
      server_name            = "tgt.example.com"
      port                   = 5432
      database_name          = "app"
      secret_arn             = aws_secretsmanager_secret.target.arn
      create_secret_role     = false
      secret_access_role_arn = aws_iam_role.dms_secrets.arn
      secret_kms_key_arn     = aws_kms_key.dms.arn
      ssl_mode               = "verify-full"
      certificate_key        = "rds-ca"
      postgres               = { after_connect_script = "SET session_replication_role = replica;" }
    }
  }

  s3_targets = {
    lake = {
      bucket_name = "orders-lake-111122223333-eu-west-1"
      kms_key_arn = aws_kms_key.dms.arn
    }
    archive = {
      bucket_name             = "orders-archive-111122223333-eu-west-1"
      kms_key_arn             = aws_kms_key.dms.arn
      create_role             = false
      service_access_role_arn = aws_iam_role.dms_lake.arn
    }
  }

  tasks = {
    app = {
      source_endpoint = "source-db"
      target_endpoint = "target-db"
      migration_type  = "full-load-and-cdc"
      table_mappings  = "{\"rules\":[{\"rule-type\":\"selection\",\"rule-id\":\"1\",\"rule-name\":\"all\",\"object-locator\":{\"schema-name\":\"app\",\"table-name\":\"%\"},\"rule-action\":\"include\"}]}"
    }
  }

  alarm_free_storage_bytes = 8589934592
}
