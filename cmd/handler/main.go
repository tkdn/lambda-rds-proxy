package main

import (
	"context"
	"log/slog"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tkdn/lambda-rds-proxy/config"
	"github.com/tkdn/lambda-rds-proxy/dbconn"
	"github.com/tkdn/lambda-rds-proxy/handler"
)

// buildHandler は環境変数からPoolを構築しHandlerを返す。Lambda実行環境
// (コンテナ)のウォーム状態での再利用を前提に、mainから1回だけ呼び出す。
// ハンドラー呼び出しごとに作り直すと、RDS Proxy越しの接続確立パターンが
// 変わりピン留め観測条件が崩れる。
func buildHandler(ctx context.Context, logger *slog.Logger) (*handler.Handler, error) {
	cfg, err := config.LoadFromEnv()
	if err != nil {
		return nil, err
	}

	poolCfg, err := dbconn.BuildPoolConfig(cfg)
	if err != nil {
		return nil, err
	}

	pool, err := pgxpool.NewWithConfig(ctx, poolCfg)
	if err != nil {
		return nil, err
	}

	return handler.New(pool, cfg.ExecMode, logger), nil
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	h, err := buildHandler(context.Background(), logger)
	if err != nil {
		logger.Error("failed to build handler", slog.String("error", err.Error()))
		os.Exit(1)
	}

	lambda.Start(h.Invoke)
}
