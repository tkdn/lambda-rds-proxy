# RDS Proxy接続失敗（tls error: EOF）のトラブルシューティング振り返り

## 事象

`terraform apply`でインフラを構築し、migrator Lambda（Auroraクラスターエンドポイントへ直接接続）でのDDL適用は成功した。続けてhandler Lambda（RDS Proxy経由）を実行したところ、以下のエラーで失敗した。

```
begin transaction: failed to connect to `user=app_admin database=pinningtest`:
	10.42.0.31:5432 (...proxy-....rds.amazonaws.com): tls error: EOF
	10.42.1.254:5432 (...proxy-....rds.amazonaws.com): tls error: EOF
```

`FunctionError: "Unhandled"`としてLambdaが失敗していた。

## 根本原因

`db`セキュリティグループのIngressルールが「Lambda SGからの5432」のみで、**RDS Proxy自身（同じ`db`SGに属する）からAuroraバックエンドへの5432通信を許可するルールが存在しなかった**。

これはRDS Proxy固有の事象ではなく、AWSセキュリティグループ全般に共通する仕様（Amazon VPC User Guideの[Security group referencing](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html#security-group-referencing)）。EC2/RDS/Lambda等のリソース種別を問わず、同じSGに複数のENIが属しているという事実だけでは相互通信は許可されない。許可するには、IngressルールのSource（送信元）としてセキュリティグループIDを明示的に指定する必要がある——それが自分自身のSG IDであれば結果的に自己参照になるが、AWSに「self-referencing」という専用のUIラベルやオプションがあるわけではなく、通常のSecurity group referencing機能の一利用形態に過ぎない。この参照は自動では付かず、ユーザーが作成するカスタムセキュリティグループでは常に明示的なルール追加が必要になる。

この結果、RDS Proxyはヘルスチェックのためにバックエンド（Aurora）へ接続しようとして失敗し続け、`aws rds describe-db-proxy-targets`で確認すると`TargetHealth.State: "UNAVAILABLE"`（`Description: "DBProxy Target unavailable due to an internal error"`）という状態になっていた。クライアント（Lambda）からRDS Proxyへの接続自体は確立できるが、プロキシがバックエンドへ橋渡しできないため、TLSハンドシェイクの途中で接続が切断され、クライアント側には`tls error: EOF`として現れていた。

## 修正

`terraform/network.tf`に自己参照Ingressルールを追加した。

```hcl
resource "aws_security_group_rule" "db_ingress_self" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.db.id
  description               = "Allow 5432 within the db security group (RDS Proxy to Aurora)"
}
```

`apply`後、ターゲットヘルスは`AVAILABLE`に回復し、handler×4関数すべてでINSERT/SELECTが成功した。

## 診断の過程で外れた仮説

エラーメッセージの文言（`tls error: EOF`）から、最初に「TLS/SSLハンドシェイクの問題」だと推測し、以下を検証した。

1. pgxのデフォルト`sslmode=prefer`ではRDS Proxy（`require_tls = true`）とのTLSネゴシエーションが失敗するのではないか → `sslmode=require`を明示指定したが、同じ`tls error: EOF`が発生し否定された
2. PostgreSQL 17で追加された「direct SSL negotiation」をpgxが使い、RDS Proxy（`RDS Proxy doesn't support direct SSL negotiation mode`と公式ドキュメントに明記）が拒否しているのではないか → pgxのソースコードを確認し、`sslnegotiation=direct`を明示指定しない限りデフォルトの`postgres`方式（間接ネゴシエーション）が使われることを確認し、否定された
3. Aurora PostgreSQL 18とRDS Proxyのバージョン非互換ではないか → AWS公式ドキュメント（Markdown版）で東京リージョンのRDS ProxyがPostgreSQL 18を含め全バージョン対応していることを確認し、否定された
4. migratorが実はTLS接続に失敗し平文にフォールバックして「たまたま」成功しているだけではないか → `cluster_database_url`にも`sslmode=require`を付けて再検証し、Aurora直結は`sslmode=require`でも成功することを確認し、否定された

## 学び

- **カスタムセキュリティグループは自己参照ルールを持たない、というAWSの基本仕様を見落としていた。** 同じSGに複数のリソース（RDS ProxyとAurora）を割り当てる設計にする場合、そのSG内での通信を許可する自己参照ルールが必要かどうかを設計時点で検討すべきだった
- **RDS Proxyを同じSGでDBと共有する構成は、AWS公式ドキュメントが明示的に想定している一般的な選択肢だった。** [Amazon Aurora ユーザーガイドのプロキシ作成手順](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/AuroraUserGuide/rds-proxy-creating.html)には次の注記がある。「セキュリティグループは、プロキシの接続先のデータベースへのアクセスを許可する必要があります。同じセキュリティグループが、アプリケーションからプロキシへのイングレスと、プロキシからデータベースへのエグレスに使用されます。例えば、データベースとプロキシに同じセキュリティグループを使用するとします。この場合は必ず、そのセキュリティグループ内のリソースが同じセキュリティグループ内の他のリソースと通信できるように指定してください。」つまり「同じSGにすべきでない」のではなく、「同じSGにする場合はこの注意点（自己参照の明示）を踏まえること」が公式に明記されていた。この一文を事前に読んでいれば、今回の問題は設計段階で回避できていた
