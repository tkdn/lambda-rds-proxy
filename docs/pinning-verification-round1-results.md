# ピン留め検証 第1回実測結果

## やったこと

`docs/plans/rds-proxy-pinning-verification.md`で計画した4パターン（`pinning-before`, `pinning-after-1a`, `pinning-after-1b`, `pinning-after-2`）に対して、負荷生成CLI（`cmd/loadgen`）で各500リクエスト・並列数20の負荷をかけた。4パターンは間隔を空けず連続実行した。

| パターン | EXEC_MODE | MAX_CONN_LIFETIME | 成功/総数 |
|---|---|---|---|
| `pinning-before` | `cache_statement` | 未設定 | 500/500 |
| `pinning-after-1a` | `simple_protocol` | 未設定 | 500/500 |
| `pinning-after-1b` | `describe_exec` | 未設定 | 497/500 |
| `pinning-after-2` | `cache_statement` | `30s` | 498/500 |

失敗した5件はいずれも`TooManyRequestsException: Rate Exceeded`（Lambda側の同時実行数スロットリング）で、DB接続やピン留めとは無関係なノイズと判断し除外した。

実行後、CloudWatchメトリクス（名前空間`AWS/RDS`、ディメンション`ProxyName=lambda-rds-proxy`）を確認した。

## わかったこと

### `DatabaseConnectionsCurrentlySessionPinned`メトリクスが一度も生成されなかった

`aws cloudwatch list-metrics`でこのメトリクス自体がリストに現れなかった。CloudWatchメトリクスは値がPutされて初めて`list-metrics`に現れる仕様のため、これは「4パターンいずれの負荷生成でも、ピン留めが一度も発生しなかった」ことを強く示唆する。

### 多重化（マルチプレクシング）が極めて高い効率で機能していた

負荷生成期間中（22:30〜22:37 JST）の`DatabaseConnections`（同時接続数、Maximum）は最大**6**、`DatabaseConnectionsSetupSucceeded`（新規接続確立数、Sum）は期間合計で**9件**だった。4パターン合計1995件の成功呼び出しに対し、新規に確立されたバックエンド接続は9件のみ——多重化率99.5%以上という結果になる。

### 4パターンは同一のコネクションプールを共有している

AWS公式ドキュメント（[RDS Proxy concepts and terminology](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.howitworks.html)）に次の記述がある。

> Each proxy performs connection pooling separately for the writer and reader instance of its associated RDS database.
> The connections that a proxy keeps open and available for your database applications to use make up the connection pool.

コネクションプールは「クライアントアプリケーション（Lambda関数）単位」ではなく「プロキシ単位」で管理される。今回の4つのLambda関数は同じRDS Proxy・同じターゲットグループ・同じDBユーザー（`app_admin`、Secrets Manager経由）を使っているため、Lambda関数が別プロセスであっても、RDS Proxy側からは「同じバックエンドコネクションプールへの接続要求」として扱われ、プールを共有する。これが新規接続確立数が9件という少なさで説明がつく理由でもある。

## 仮説との照合

grillingセッション（`docs/plans/rds-proxy-pinning-verification.md`のContext）で立てた仮説は以下の通りだった。

- `QueryExecModeCacheStatement`（デフォルト、`pinning-before`と`pinning-after-2`が該当）はnamed prepared statementをサーバー側にキャッシュして再利用し、ピン留めを引き起こすと予想
- `QueryExecModeSimpleProtocol`（`pinning-after-1a`）はExtended Query Protocol自体を使わないため、ピン留めを回避できると予想（確度高）
- `QueryExecModeDescribeExec`（`pinning-after-1b`）はunnamed prepared statementのみを使うが、AWS公式ドキュメントはnamed/unnamedの区別を明記しておらず、回避できるかは未確定としていた

今回の実測結果は、この仮説と次の点で食い違う。

- **`pinning-before`（`CacheStatement`、named prepared statement発行）でもピン留めが発生しなかった。** 仮説では発生を予想していたパターンで発生しなかった、という点が最大の食い違い

この食い違いの解釈として、以下の2つの可能性が考えられ、現時点では切り分けられていない。

1. **named prepared statementの発行自体はピン留めを引き起こさない**という可能性。AWS公式ドキュメントが挙げる「`PREPARE`/`DISCARD`/`DEALLOCATE`/`EXECUTE`コマンドの使用」は、SQL文としてクライアントが明示的に書く`PREPARE`コマンドを指している。

   ```sql
   PREPARE fooplan (int, text, bool, numeric) AS
       INSERT INTO foo VALUES($1, $2, $3, $4);
   EXECUTE fooplan(1, 'Hunter Valley', 't', 200.00);
   ```

   これに対しpgxの`QueryExecModeCacheStatement`は、Goコード上に`PREPARE`という文字列を一切書かなくても、ワイヤプロトコル（[Frontend/Backend Protocol](https://www.postgresql.org/docs/current/protocol.html)）の`Parse`メッセージに非空のstatement名（`stmtcache_<SQLのハッシュ値>`）を付与して送信することで、サーバー側にプリペアドステートメントを登録・再利用する。これが「named prepared statement」——SQL構文としての`PREPARE`コマンドとは別の経路で、同じ「サーバー側にプリペアドステートメントが名前付きで存在する」状態を作る。AWS公式ドキュメントの文言がSQL構文としての`PREPARE`コマンドのみを指しているなら、pgxが内部的に発行するこの`Parse`メッセージはピン留めのトリガー一覧に含まれていない可能性がある
2. **4パターンが同一のコネクションプールを共有しているため、`pinning-before`の呼び出しが、後続パターン（あるいは先行するmigrator実行やスモークテスト）が既に確立した非ピン留め状態の接続を借用してしまい、`pinning-before`固有の挙動を単独で観測できていない**可能性。負荷生成を連続実行したことで、この2つの効果が混ざっている

## 今後の検証設計への示唆

以下は優先度順。実際の想定アプリケーションでは、複数のLambda関数（クライアント）が同じRDS Proxy・同じターゲットグループ・同じDBユーザーを使う構成が前提のため、「4パターンを完全に独立させる」ような変更は現実の利用形態から乖離してしまう。今回の実測（コネクションがしっかり使い回されている＝多重化が機能している）が確認できたこと自体が大きな成果であり、以下はいずれも今すぐ着手する優先度ではない。

- RDS Proxyのログ（audit/error/general/slowquery）を有効化すれば、ピン留めが発生した際に何がトリガーだったかを直接特定できる。ただし`DatabaseConnectionsCurrentlySessionPinned`メトリクスだけでも「発生したかどうか」の判定には十分で、今回のようにこのメトリクス自体が生成されない（＝発生していない）ことを確認できれば、それだけで大きな情報になる。ログ有効化はやる価値はそこそこあるが、優先度は低い
- より高い並列度・長い持続時間での負荷生成は、ピン留めをより顕在化させる可能性があるが、実際にどの程度の同時利用が想定されるかという前提が定まらないと、負荷条件の設定自体が難しい。想定ユーザー数・アクセスパターンが固まった段階で改めて検討する
- 4パターンを完全に独立させて計測する案は、優先順位はかなり低い。同じRDS Proxy構成を複数クライアントで共有するのが現実の想定利用形態であるため

## 検証に使ったコマンドと証跡

### 負荷生成

```
./bin/loadgen -function lambda-rds-proxy-pinning-before -n 500 -c 20 -out tmp/results-before.jsonl
./bin/loadgen -function lambda-rds-proxy-pinning-after-1a -n 500 -c 20 -out tmp/results-after-1a.jsonl
./bin/loadgen -function lambda-rds-proxy-pinning-after-1b -n 500 -c 20 -out tmp/results-after-1b.jsonl
./bin/loadgen -function lambda-rds-proxy-pinning-after-2 -n 500 -c 20 -out tmp/results-after-2.jsonl
```

結果（JSON Lines、各呼び出しの`invocation_id`/`start_time`/`end_time`/`status`/`payload`）:

- [docs/evidences/round1-results-before.jsonl](evidences/round1-results-before.jsonl)
- [docs/evidences/round1-results-after-1a.jsonl](evidences/round1-results-after-1a.jsonl)
- [docs/evidences/round1-results-after-1b.jsonl](evidences/round1-results-after-1b.jsonl)
- [docs/evidences/round1-results-after-2.jsonl](evidences/round1-results-after-2.jsonl)

### CloudWatchメトリクス確認

ピン留めメトリクス自体の有無を確認（結果: 空、メトリクス未生成）:

```
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnectionsCurrentlySessionPinned \
  --dimensions Name=ProxyName,Value=lambda-rds-proxy \
  --start-time 2026-08-23T13:25:00Z \
  --end-time 2026-08-23T13:40:00Z \
  --period 60 \
  --statistics Maximum \
  --region ap-northeast-1
```

RDS Proxyに存在する全メトリクスの一覧（`DatabaseConnectionsCurrentlySessionPinned`が含まれないことの確認）:

```
aws cloudwatch list-metrics --namespace AWS/RDS --dimensions Name=ProxyName,Value=lambda-rds-proxy --region ap-northeast-1
```
→ [docs/evidences/round1-cw-list-metrics.json](evidences/round1-cw-list-metrics.json)

同時接続数（Maximum、期間中の最大値6を確認）:

```
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=ProxyName,Value=lambda-rds-proxy \
  --start-time 2026-08-23T13:25:00Z \
  --end-time 2026-08-23T13:40:00Z \
  --period 60 \
  --statistics Maximum \
  --region ap-northeast-1
```
→ [docs/evidences/round1-cw-database-connections.json](evidences/round1-cw-database-connections.json)

新規接続確立数（Sum、期間合計9件を確認）:

```
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnectionsSetupSucceeded \
  --dimensions Name=ProxyName,Value=lambda-rds-proxy \
  --start-time 2026-08-23T13:25:00Z \
  --end-time 2026-08-23T13:40:00Z \
  --period 60 \
  --statistics Sum \
  --region ap-northeast-1
```
→ [docs/evidences/round1-cw-database-connections-setup-succeeded.json](evidences/round1-cw-database-connections-setup-succeeded.json)

`DatabaseConnectionsCurrentlyBorrowed`はメトリクス名として存在しないことが`list-metrics`の結果から判明したため、参考として空の結果を残す:

→ [docs/evidences/round1-cw-database-connections-currently-borrowed.json](evidences/round1-cw-database-connections-currently-borrowed.json)

認証情報（AWSプロファイル/リージョン設定、Secrets Manager経由のDB認証情報等）は上記コマンド・証跡いずれにも含まれない。
