variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "リソース名のプレフィックスとして使う識別子"
  type        = string
  default     = "lambda-rds-proxy"
}

variable "vpc_cidr" {
  description = "検証用VPCのCIDRブロック"
  type        = string
  default     = "10.42.0.0/16"
}

variable "availability_zones" {
  description = "Aurora/RDS Proxyのサブネットグループに使う2つのAZ"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "db_name" {
  description = "Auroraクラスターに作成する初期データベース名"
  type        = string
  default     = "pinningtest"
}

variable "db_master_username" {
  description = "Auroraクラスターのマスターユーザー名"
  type        = string
  default     = "pinningtest_admin"
}

variable "db_instance_class" {
  description = "Aurora PostgreSQLの検証用最小インスタンスクラス"
  type        = string
  default     = "db.t4g.medium"
}

variable "db_engine_version" {
  description = "Aurora PostgreSQLのエンジンバージョン。nullの場合はAWSのデフォルト（aws_rds_engine_versionデータソースが返す最新の推奨版）を使う"
  type        = string
  default     = null
}

variable "max_conn_lifetime_after2" {
  description = "After-2パターン（pinning-after-2関数）のMAX_CONN_LIFETIME"
  type        = string
  default     = "30s"
}

variable "lambda_architecture" {
  description = "Lambda関数のCPUアーキテクチャ"
  type        = string
  default     = "arm64"
}

variable "log_retention_days" {
  description = "CloudWatch LogsのLambdaロググループ保持日数"
  type        = number
  default     = 14
}
