output "lambda_function_names" {
  description = "loadgen CLIから-functionフラグに指定するLambda関数名"
  value = {
    before   = aws_lambda_function.pinning_before.function_name
    after_1a = aws_lambda_function.pinning_after_1a.function_name
    after_1b = aws_lambda_function.pinning_after_1b.function_name
    after_2  = aws_lambda_function.pinning_after_2.function_name
    migrator = aws_lambda_function.migrator.function_name
  }
}

output "db_proxy_endpoint" {
  description = "RDS Proxyのエンドポイント"
  value       = aws_db_proxy.this.endpoint
}

output "aurora_cluster_endpoint" {
  description = "Auroraクラスターの書き込みエンドポイント（DDL適用等、Proxyを経由しない直接接続用）"
  value       = aws_rds_cluster.this.endpoint
}

output "db_master_secret_arn" {
  description = "DBマスター認証情報を格納したSecrets ManagerのARN"
  value       = aws_secretsmanager_secret.db_master.arn
}
