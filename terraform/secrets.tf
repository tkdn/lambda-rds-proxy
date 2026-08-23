resource "random_password" "db_master" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db_master" {
  name = "${var.project_name}/db-master"

  # デフォルト(30日)だとterraform destroy後もシークレットが復旧待機状態で残り、
  # 同名での再作成時に衝突する。検証用途のため即時削除にする。
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_master" {
  secret_id = aws_secretsmanager_secret.db_master.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.db_master.result
  })
}
