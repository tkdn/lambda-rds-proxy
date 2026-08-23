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

// Lambda実行環境(コンテナ)のウォーム状態での再利用を前提に、init()で1回だけ
// Poolを生成する。ハンドラー呼び出しごとに作り直すと、RDS Proxy越しの
// 接続確立パターンが変わりピン留め観測条件が崩れる。
var h *handler.Handler

func init() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	cfg, err := config.LoadFromEnv()
	if err != nil {
		logger.Error("failed to load config", slog.String("error", err.Error()))
		os.Exit(1)
	}

	poolCfg, err := dbconn.BuildPoolConfig(cfg)
	if err != nil {
		logger.Error("failed to build pool config", slog.String("error", err.Error()))
		os.Exit(1)
	}

	pool, err := pgxpool.NewWithConfig(context.Background(), poolCfg)
	if err != nil {
		logger.Error("failed to create pool", slog.String("error", err.Error()))
		os.Exit(1)
	}

	h = handler.New(pool, cfg.ExecMode, logger)
}

func main() {
	lambda.Start(h.Invoke)
}
