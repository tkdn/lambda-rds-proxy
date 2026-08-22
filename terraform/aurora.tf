# engine_versionを未指定にした場合、AWSプロバイダ側で利用可能な
# 最新のAurora PostgreSQLバージョンをAWSのデフォルト解決に委ねる。
data "aws_rds_engine_version" "postgresql" {
  count = var.db_engine_version == null ? 1 : 0

  engine             = "aurora-postgresql"
  preferred_versions = null
  default_only       = true
}

locals {
  db_engine_version = var.db_engine_version != null ? var.db_engine_version : data.aws_rds_engine_version.postgresql[0].version
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-db"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db"
  }
}

resource "aws_rds_cluster" "this" {
  cluster_identifier     = var.project_name
  engine                 = "aurora-postgresql"
  engine_version         = local.db_engine_version
  database_name          = var.db_name
  master_username        = var.db_master_username
  master_password        = random_password.db_master.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  # 検証用途のためスキップ。本番運用ではfalseにしfinal_snapshot_identifierを指定する
  skip_final_snapshot = true
}

resource "aws_rds_cluster_instance" "this" {
  cluster_identifier = aws_rds_cluster.this.id
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
  instance_class     = var.db_instance_class
}
