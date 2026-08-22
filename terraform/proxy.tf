resource "aws_db_proxy" "this" {
  name                   = var.project_name
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_subnet_ids         = aws_subnet.private[*].id
  vpc_security_group_ids = [aws_security_group.db.id]
  require_tls            = true

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db_master.arn
  }

  # session_pinning_filters (EXCLUDE_VARIABLE_SETS等) はMySQLエンジンファミリー専用機能であり、
  # PostgreSQLエンジンファミリーでは無視されるため設定しない。
  # https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy-pinning.html
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    max_connections_percent = 100
  }
}

resource "aws_db_proxy_target" "this" {
  db_proxy_name         = aws_db_proxy.this.name
  target_group_name     = aws_db_proxy_default_target_group.this.name
  db_cluster_identifier = aws_rds_cluster.this.cluster_identifier
}
