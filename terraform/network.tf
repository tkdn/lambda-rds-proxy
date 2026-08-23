data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.project_name
  }
}

# LambdaとAurora/Proxyは同一のプライベートサブネットに配置する。
# 検証用途で外部からの到達性は不要なため、パブリックサブネットやNAT Gatewayは作らない。
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-${var.availability_zones[count.index]}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-private"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-lambda"
  description = "For handler/migrator Lambda functions. Egress only."
  vpc_id      = aws_vpc.this.id

  egress {
    description = "Allow all outbound (RDS Proxy/Aurora 5432, CloudWatch Logs, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-lambda"
  }
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db"
  description = "For Aurora/RDS Proxy. Allows 5432 only from the Lambda security group."
  vpc_id      = aws_vpc.this.id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db"
  }
}

resource "aws_security_group_rule" "db_ingress_from_lambda" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.lambda.id
  description              = "Allow 5432 from Lambda to Aurora/RDS Proxy"
}

# RDS ProxyとAuroraは同じSGを共用しているが、Ingressルールは送信元が
# 同じSGに属しているというだけでは自動的に許可されない(AWSデフォルトSGの
# ような自己参照ルールはカスタムSGには存在しない)。RDS ProxyからAurora
# バックエンドへの5432通信を許可する自己参照ルールを明示的に追加する。
resource "aws_security_group_rule" "db_ingress_self" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.db.id
  description              = "Allow 5432 within the db security group (RDS Proxy to Aurora)"
}
