# lambda-rds-proxy

Aurora PostgreSQL + RDS Proxy + Go Lambdaという構成で、Prepared Statementほか一般的なSQL実行がRDS Proxyのセッションピン留め（session pinning）を引き起こすかどうかを検証するリポジトリ。

## 構成

- `terraform/`: 検証用インフラ一式（VPC、Aurora PostgreSQL、RDS Proxy、Secrets Manager、IAM、Lambda）
- `cmd/handler`, `handler/`: 検証対象のLambdaハンドラー。1回の呼び出しでINSERT→SELECTを実行する。`EXEC_MODE`環境変数でpgxの`QueryExecMode`を切り替え、4つの独立したLambda関数（`pinning-before`/`pinning-after-1a`/`pinning-after-1b`/`pinning-after-2`）としてデプロイする
- `cmd/migrator`: DDL適用専用の踏み台Lambda
- `cmd/loadgen`, `loadgen/`: 対象Lambda関数へ並列に負荷をかけるCLI
- `db/`: sqlcによるクエリコード生成とマイグレーションDDL

## 検証結果サマリー

各パターンに500リクエスト・並列度20の負荷をかけた結果、**4パターンいずれもピン留めは発生しなかった**（CloudWatchメトリクス`DatabaseConnectionsCurrentlySessionPinned`自体が生成されず）。多重化率は99.5%以上で、コネクションの使い回しが極めて高い効率で機能していることを確認した。

デフォルトの`QueryExecModeCacheStatement`（named prepared statement発行）でもピン留めが発生しなかった点は、事前に立てていた仮説と食い違う結果だった。詳細な分析と証跡は [docs/pinning-verification-round1-results.md](docs/pinning-verification-round1-results.md) を参照。

## ドキュメント

- [docs/plans/rds-proxy-pinning-verification.md](docs/plans/rds-proxy-pinning-verification.md): 検証計画。設計判断とその根拠
- [docs/pinning-verification-round1-results.md](docs/pinning-verification-round1-results.md): 第1回実測結果、仮説との照合、証跡
- [docs/rds-proxy-tls-eof-troubleshooting.md](docs/rds-proxy-tls-eof-troubleshooting.md): 構築時に発生したRDS Proxy接続エラー（`tls error: EOF`）のトラブルシューティング記録
- [docs/evidences/](docs/evidences/): 負荷生成結果・CloudWatchメトリクスの生データ
