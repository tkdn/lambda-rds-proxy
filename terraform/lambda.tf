locals {
  # DATABASE_URLはRDS Proxyのエンドポイントを指す（クラスターエンドポイントではない）。
  # migratorのみAuroraクラスターエンドポイントへ直接接続する（proxy.tf参照）。
  proxy_database_url   = "postgres://${var.db_master_username}:${random_password.db_master.result}@${aws_db_proxy.this.endpoint}:5432/${var.db_name}"
  cluster_database_url = "postgres://${var.db_master_username}:${random_password.db_master.result}@${aws_rds_cluster.this.endpoint}:5432/${var.db_name}"
}

# Lambdaが初回実行時に自動作成するロググループ(/aws/lambda/<function_name>)は
# Terraformの管理外になり、terraform destroyでは削除されずに残る。
# ここで明示的にリソース化し、各aws_lambda_functionのlogging_config.log_groupで
# 参照することで、命名規則の一致だけに頼らず依存関係を明示する。
resource "aws_cloudwatch_log_group" "pinning_before" {
  name              = "/aws/lambda/${var.project_name}-pinning-before"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "pinning_after_1a" {
  name              = "/aws/lambda/${var.project_name}-pinning-after-1a"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "pinning_after_1b" {
  name              = "/aws/lambda/${var.project_name}-pinning-after-1b"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "pinning_after_2" {
  name              = "/aws/lambda/${var.project_name}-pinning-after-2"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "migrator" {
  name              = "/aws/lambda/${var.project_name}-migrator"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "pinning_before" {
  function_name = "${var.project_name}-pinning-before"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  architectures = [var.lambda_architecture]

  filename         = "${path.module}/../handler.zip"
  source_code_hash = filebase64sha256("${path.module}/../handler.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DATABASE_URL = local.proxy_database_url
      EXEC_MODE    = "cache_statement"
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.pinning_before.name
  }
}

resource "aws_lambda_function" "pinning_after_1a" {
  function_name = "${var.project_name}-pinning-after-1a"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  architectures = [var.lambda_architecture]

  filename         = "${path.module}/../handler.zip"
  source_code_hash = filebase64sha256("${path.module}/../handler.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DATABASE_URL = local.proxy_database_url
      EXEC_MODE    = "simple_protocol"
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.pinning_after_1a.name
  }
}

resource "aws_lambda_function" "pinning_after_1b" {
  function_name = "${var.project_name}-pinning-after-1b"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  architectures = [var.lambda_architecture]

  filename         = "${path.module}/../handler.zip"
  source_code_hash = filebase64sha256("${path.module}/../handler.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DATABASE_URL = local.proxy_database_url
      EXEC_MODE    = "describe_exec"
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.pinning_after_1b.name
  }
}

resource "aws_lambda_function" "pinning_after_2" {
  function_name = "${var.project_name}-pinning-after-2"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  architectures = [var.lambda_architecture]

  filename         = "${path.module}/../handler.zip"
  source_code_hash = filebase64sha256("${path.module}/../handler.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DATABASE_URL      = local.proxy_database_url
      EXEC_MODE         = "cache_statement"
      MAX_CONN_LIFETIME = var.max_conn_lifetime_after2
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.pinning_after_2.name
  }
}

resource "aws_lambda_function" "migrator" {
  function_name = "${var.project_name}-migrator"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  architectures = [var.lambda_architecture]

  filename         = "${path.module}/../migrator.zip"
  source_code_hash = filebase64sha256("${path.module}/../migrator.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      # RDS Proxyを経由せずAuroraクラスターエンドポイントへ直接接続してDDLを適用する
      DATABASE_URL = local.cluster_database_url
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.migrator.name
  }
}
