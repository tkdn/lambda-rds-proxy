package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"

	"github.com/tkdn/lambda-rds-proxy/db/migrations"
)

var logger = slog.New(slog.NewJSONHandler(os.Stdout, nil))

type response struct {
	Message string `json:"message"`
}

func handleRequest(ctx context.Context, _ json.RawMessage) (response, error) {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		return response{}, fmt.Errorf("DATABASE_URL is required")
	}

	// RDS Proxyを経由せずAuroraクラスターエンドポイントへ直接接続する。
	// 単発のDDL適用のみが目的でウォームスタート間の接続再利用は不要なため、
	// pgxpoolではなくpgx.Connectの単発接続を使う。
	conn, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		logger.ErrorContext(ctx, "connect failed", slog.String("error", err.Error()))
		return response{}, err
	}
	defer func() {
		if err := conn.Close(ctx); err != nil {
			logger.ErrorContext(ctx, "connection close failed", slog.String("error", err.Error()))
		}
	}()

	if _, err := conn.Exec(ctx, migrations.CreateAccessLogs); err != nil {
		logger.ErrorContext(ctx, "ddl apply failed", slog.String("error", err.Error()))
		return response{}, err
	}

	logger.InfoContext(ctx, "ddl apply succeeded")
	return response{Message: "access_logs table ensured"}, nil
}

func main() {
	lambda.Start(handleRequest)
}
