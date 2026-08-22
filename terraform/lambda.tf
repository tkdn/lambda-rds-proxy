locals {
  # DATABASE_URLはRDS Proxyのエンドポイントを指す（クラスターエンドポイントではない）。
  # migratorのみAuroraクラスターエンドポイントへ直接接続する（proxy.tf参照）。
  proxy_database_url   = "postgres://${var.db_master_username}:${random_password.db_master.result}@${aws_db_proxy.this.endpoint}:5432/${var.db_name}"
  cluster_database_url = "postgres://${var.db_master_username}:${random_password.db_master.result}@${aws_rds_cluster.this.endpoint}:5432/${var.db_name}"
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
}
