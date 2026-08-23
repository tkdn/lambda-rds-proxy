# Aurora PostgreSQL + RDS Proxy セッションピン留め検証環境

## Context

Lambdaの同時実行数そのものは検証の関心事にせず、Aurora PostgreSQL + RDS Proxy + Go Lambdaという構成で、Prepared Statementほか一般的なSQL実行がRDS Proxyのセッションピン留め(session pinning)を引き起こすかどうかを実証する。単なる発生確認に留めず、ピン留めを回避しうる実装パターンとのBefore/After比較を行い、Go実装側でどのような制御が有効かを検証結果として残すことが目的。

grillingセッションでの調査により、以下の事実が判明している。

- pgx v5の[`QueryExecMode`](https://pkg.go.dev/github.com/jackc/pgx/v5#QueryExecMode)がPrepared Statement発行の唯一の制御点であり、sqlc（`sql_package: pgx/v5`）はこの設定に関与しない
- `QueryExecModeCacheStatement`（デフォルト）のみがnamed prepared statementをサーバー側にキャッシュして再利用する。他のモード（`CacheDescribe`, `DescribeExec`, `Exec`）はunnamed prepared statementを使う。`SimpleProtocol`はExtended Query Protocol自体を使わない
- AWS公式ドキュメント（[Avoiding pinning an RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy-pinning.html)）のPostgreSQLセクションは「`PREPARE`/`DISCARD`/`DEALLOCATE`/`EXECUTE`コマンドの使用」がピン留めトリガーになるとするが、named/unnamedの区別は明記していない。したがって`DescribeExec`等がピン留めを回避できるかは実測でしか判定できない未確定事項
- `session_pinning_filters`はMySQLエンジンファミリー専用機能であり、PostgreSQLでは無視される

補足: PostgreSQLの[Frontend/Backend Protocol](https://www.postgresql.org/docs/current/protocol.html)（ワイヤプロトコル）では、Prepared Statementの発行は`Parse`メッセージで行う。このとき付与するstatement名が空文字列なら「unnamed」、非空文字列なら「named」と呼び分ける。`QueryExecModeCacheStatement`はSQL文のハッシュ値から生成した非空の名前で`Parse`しサーバー側にキャッシュ・再利用する（named）。他のExtended Query Protocolモード（`CacheDescribe`, `DescribeExec`, `Exec`）は`Parse`をstatement名なしで都度送る（unnamed）。`SimpleProtocol`は`Parse`自体を送らずSimple Query Protocol（`Query`メッセージのみ）を使う。

## リポジトリ構成

```
lambda-rds-proxy/
├── go.mod                              # 単一モジュール
├── go.sum
├── Makefile                            # build-handler / build-loadgen / build-migrator
├── README.md                           # 検証手順・判定基準
│
├── cmd/
│   ├── handler/main.go                 # Lambdaハンドラーのエントリポイント
│   ├── migrator/main.go                # 踏み台Lambda: DDL適用専用
│   └── loadgen/main.go                 # 負荷生成CLI
│
├── config/config.go                    # 環境変数パース（EXEC_MODE, DATABASE_URL, MAX_CONN_LIFETIME）
├── dbconn/pool.go                      # pgxpool.Config生成（4パターンの分岐はここに集約）
├── handler/handler.go                  # INSERT→SELECT処理本体
├── loadgen/
│   ├── invoker.go                      # WaitGroup+チャネルによる並列Invoke
│   └── result.go                       # JSON Lines出力用結果構造体
│
├── db/
│   ├── migrations/0001_create_access_logs.sql
│   ├── queries/access_log.sql          # sqlcアノテーション付きSQL
│   └── sqlc/                           # 生成コード（コミット対象）
│
├── sqlc.yaml
│
│   ※ `cmd/loadgen/main.go`（エントリポイント）とルート直下`loadgen/`（並列Invoke実装）は別パッケージ
│
└── terraform/
    ├── main.tf                         # provider, backend
    ├── variables.tf
    ├── outputs.tf                      # Lambda関数名一覧、Auroraエンドポイント等
    ├── network.tf                      # VPC, Subnet ×2 AZ, SG
    ├── aurora.tf                       # aws_rds_cluster, aws_rds_cluster_instance, subnet group
    ├── proxy.tf                        # aws_db_proxy, target group, target
    ├── secrets.tf                      # Secrets Manager（DBマスター認証情報）
    ├── iam.tf                          # Lambda実行ロール, RDS Proxy用ロール
    ├── lambda.tf                       # aws_lambda_function ×4（handler）+ ×1（migrator）
    └── terraform.tfvars.example
```

## 4パターンの実現方式

単一Lambdaハンドラーバイナリ（`cmd/handler`）を4つの独立したLambda関数としてデプロイし、環境変数`EXEC_MODE`で挙動を分岐する。ビジネスロジック（INSERT→SELECT）は共通、差分は`dbconn/pool.go`の1箇所に閉じ込める。

| Lambda関数名 | EXEC_MODE | MAX_CONN_LIFETIME | 狙い |
|---|---|---|---|
| `pinning-before` | `cache_statement` | 未設定 | named prepared statement発行、ピン留め発生を予想 |
| `pinning-after-1a` | `simple_protocol` | 未設定 | Parse自体を送らない、回避を期待（確度高） |
| `pinning-after-1b` | `describe_exec` | 未設定 | unnamed prepared statementのみ、回避可否は未確定・実測対象 |
| `pinning-after-2` | `cache_statement` | `30s`（デフォルトの`1h`から短縮） | ピン留め発生を許容しつつ早期リサイクルで緩和 |

Terraformは`for_each`でループさせず4リソースを明示的に列挙する（検証用途で将来的にパターンごとの個別設定変更がありうるため、可読性優先）。

`dbconn/pool.go`の分岐:

```go
func BuildPoolConfig(cfg config.Config) (*pgxpool.Config, error) {
    poolCfg, err := pgxpool.ParseConfig(cfg.DatabaseURL)
    if err != nil {
        return nil, err
    }
    switch cfg.ExecMode {
    case "cache_statement":
        poolCfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeCacheStatement
    case "simple_protocol":
        poolCfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
    case "describe_exec":
        poolCfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeDescribeExec
    default:
        return nil, fmt.Errorf("unknown EXEC_MODE: %s", cfg.ExecMode)
    }
    // pgxpool.ParseConfig経由のためデフォルトは defaultMaxConnLifetime = time.Hour (pgxpool/pool.go:20)。
    // After-2パターンのみ環境変数 MAX_CONN_LIFETIME=30s で上書きする。
    if cfg.MaxConnLifetime > 0 {
        poolCfg.MaxConnLifetime = cfg.MaxConnLifetime
    }
    return poolCfg, nil
}
```

## Lambdaハンドラーのコード構造

`cmd/handler/main.go`は`init()`でpgxpool.Poolをパッケージグローバル変数として1回だけ生成する。Lambda実行環境（コンテナ）のウォーム状態での再利用が、RDS Proxy越しの接続確立パターンを安定させる前提条件になるため、ハンドラー呼び出しごとにPoolを作り直さない。

`handler/handler.go`は`sqlc.New(pool)`で生成したクエリオブジェクトを使い、1回の呼び出しでINSERT（`InsertAccessLog`）→SELECT（`GetLatestAccessLog`）を実行する。生のSQL文字列を組み立てるコードパスは持たせず、SET文・一時テーブル・動的SQL生成は実装しない（スコープ外）。

ログ出力は標準ライブラリ`log/slog`を使い、`slog.NewJSONHandler`でJSON形式に統一する。TerraformのLambda側`logging_config.log_format = "JSON"`（terraform/lambda.tf）と対応させ、CloudWatch Logs Insightsで`EXEC_MODE`ごとにフィルタ・分析できるようにする。少なくとも次の情報を構造化フィールドとして出力する。

- `exec_mode`（環境変数`EXEC_MODE`の値。4パターンのどれで実行されたか）
- リクエストごとの識別子（`invocation_id`等、loadgen CLI側の出力と突き合わせるため）
- INSERT/SELECTそれぞれの実行結果・エラー有無

## DDL適用: 踏み台Lambda方式

AuroraはVPC内リソースであり、ローカル端末から`psql`で直接到達できないため、DDL適用専用の踏み台Lambda（`cmd/migrator`）を用意する。

- `cmd/migrator/main.go`は`db/migrations/0001_create_access_logs.sql`の内容を埋め込み（`//go:embed`）、起動時にAuroraクラスターエンドポイントへ直接接続（RDS Proxyは経由しない）してDDLを実行し、結果をレスポンスとして返すだけのシンプルなLambda
- Terraformで`aws_lambda_function.migrator`として1つだけデプロイし、VPC内・Aurora/ProxyのセキュリティグループからのアクセスをSGルールで許可する
- 実行は`aws lambda invoke`で手動で1回叩く（検証手順の一部としてREADMEに明記）。冪等性のため`CREATE TABLE IF NOT EXISTS`とする
- 恒常運用のマイグレーションツール（golang-migrate等）は導入しない。テーブルは1つのみでスキーマ変更の見込みが薄いため過剰と判断

## Terraformリソース（モジュール化せずファイル分割のみ）

- **network.tf**: VPC、Subnet×2 AZ、Internet Gateway、Route Table、Security Group（Lambda用・Aurora/Proxy用の2種、Proxy用はLambda SGからの5432許可のみ）
- **aurora.tf**: `aws_rds_cluster`（`engine = "aurora-postgresql"`）、`aws_rds_cluster_instance`×1（最小インスタンスクラス）、`aws_db_subnet_group`
- **proxy.tf**: `aws_db_proxy`（`session_pinning_filters`は設定せず、コメントで「PostgreSQLエンジンファミリーでは無視されるため未設定」と明記）、`aws_db_proxy_default_target_group`、`aws_db_proxy_target`
- **secrets.tf**: `aws_secretsmanager_secret` + `aws_secretsmanager_secret_version`（DBマスター認証情報、Proxy認証に使用）
- **iam.tf**: Lambda実行ロール（VPCアクセス権限）、RDS Proxy用IAMロール（Secrets Manager読み取り、`rds.amazonaws.com`へのAssumeRole許可）
- **lambda.tf**: `aws_lambda_function`×4（handler、環境変数のみ差分）+ ×1（migrator）

NAT Gateway/VPCエンドポイントは作成しない（LambdaはAurora/Proxyへの到達のみ必要、CloudWatch LogsはVPC内Lambdaでもデフォルトで到達可能なため）。

## ビルド・デプロイ

`provided.al2023`カスタムランタイム + `bootstrap`バイナリのzip化を採用（コンテナイメージ化はしない、反復ビルドサイクルを優先）。アーキテクチャは`arm64`。

```makefile
build-handler:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o bootstrap ./cmd/handler
	zip handler.zip bootstrap && rm bootstrap

build-migrator:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o bootstrap ./cmd/migrator
	zip migrator.zip bootstrap && rm bootstrap

build-loadgen:
	go build -o bin/loadgen ./cmd/loadgen
```

Terraformの`aws_lambda_function`はビルド済みzipを`filename`+`source_code_hash = filebase64sha256(...)`で参照するだけとし、Goビルド自体はTerraformの管轄に含めない。

## go.mod / sqlc

単一モジュール（`module github.com/tkdn/lambda-rds-proxy`）。`cmd/handler`、`cmd/migrator`、`cmd/loadgen`（エントリポイント）と`config`、`dbconn`、`handler`、`loadgen`、`db/sqlc`（ライブラリパッケージ）は同一モジュール内で共存する。

主要依存: `github.com/aws/aws-lambda-go`、`github.com/aws/aws-sdk-go-v2/service/lambda`、`github.com/jackc/pgx/v5`、`github.com/google/uuid`

`sqlc.yaml`:
```yaml
version: "2"
sql:
  - engine: "postgresql"
    queries: "db/queries"
    schema: "db/migrations"
    gen:
      go:
        package: "sqlc"
        out: "db/sqlc"
        sql_package: "pgx/v5"
        emit_json_tags: true
```

`db/queries/access_log.sql`:
```sql
-- name: InsertAccessLog :one
INSERT INTO access_logs (payload) VALUES ($1) RETURNING *;

-- name: GetLatestAccessLog :one
SELECT * FROM access_logs ORDER BY created_at DESC LIMIT 1;
```

## 負荷生成CLI（`cmd/loadgen`）

`aws-sdk-go-v2/service/lambda`の`Client.Invoke`を使い、対象Lambda関数を並列に複数回呼び出す。並列化は`sync.WaitGroup`＋バッファ付きチャネルで実装し、`errgroup`は使わない（1件のエラーで全体をキャンセルせず、全リクエストの成否を独立に記録する必要があるため）。

フラグ: `-function`（対象Lambda関数名）、`-n`（総リクエスト数）、`-c`（並列数）、`-out`（JSON Lines出力先）

各呼び出しの結果（`invocation_id`, `start_time`, `end_time`, `status`, レスポンスメタデータ）をJSON Linesで出力し、後からCloudWatchログと突き合わせられるようにする。

## 検証の実行手順

1. `terraform -chdir=terraform init && terraform -chdir=terraform apply`でVPC/Aurora/Proxy/Secrets Manager/IAM/Lambda一式を構築（初回はダミーzipでも可）
2. `make build-migrator && terraform -chdir=terraform apply`でmigrator Lambdaのコードを反映
3. `aws lambda invoke --function-name <migrator> /dev/stdout`でDDLを1回適用
4. `sqlc generate`で`db/sqlc/`にコード生成
5. `make build-handler && terraform -chdir=terraform apply`で4つのhandler Lambdaにコードを反映
6. `make build-loadgen`
7. 4パターンそれぞれに対して`./bin/loadgen -function pinning-before -n 500 -c 20 -out results-before.jsonl`のように実行
8. CloudWatchメトリクス`DatabaseConnectionsCurrentlySessionPinned`（名前空間`AWS/RDS`）をパターンごとの実行時間帯で比較
9. RDS ProxyのログをCloudWatch Logsで確認し、ピン留め発生時のトリガー操作を4パターンで突き合わせ
10. `results-*.jsonl`とCloudWatchの結果を合わせてBefore/After比較としてまとめる

## スコープ外（明示）

- SQLテキスト16KB超過によるピン留め（回避不可のハード制限のため比較の余地がない）
- SET文・一時テーブル起因のピン留め（Go実装で明示的に書かない限り踏まない経路）
- `session_pinning_filters`によるインフラ側回避（PostgreSQLでは無効）
- マイグレーションツールの導入、複数テーブル・JOINを伴うSELECT
