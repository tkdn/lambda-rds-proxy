package handler

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"uuid"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tkdn/lambda-rds-proxy/config"
	"github.com/tkdn/lambda-rds-proxy/db/sqlc"
)

type Handler struct {
	pool     *pgxpool.Pool
	execMode config.ExecMode
	logger   *slog.Logger
}

func New(pool *pgxpool.Pool, execMode config.ExecMode, logger *slog.Logger) *Handler {
	return &Handler{pool: pool, execMode: execMode, logger: logger}
}

type Response struct {
	InvocationID  string `json:"invocation_id"`
	InsertedID    int64  `json:"inserted_id"`
	LatestPayload string `json:"latest_payload"`
}

func (h *Handler) Invoke(ctx context.Context, _ json.RawMessage) (Response, error) {
	invocationID := uuid.New().String()
	logger := h.logger.With(
		slog.String("exec_mode", string(h.execMode)),
		slog.String("invocation_id", invocationID),
	)

	tx, err := h.pool.Begin(ctx)
	if err != nil {
		logger.ErrorContext(ctx, "begin transaction failed", slog.String("error", err.Error()))
		return Response{}, fmt.Errorf("begin transaction: %w", err)
	}
	defer func() {
		if err := tx.Rollback(ctx); err != nil && !errors.Is(err, pgx.ErrTxClosed) {
			logger.ErrorContext(ctx, "rollback failed", slog.String("error", err.Error()))
		}
	}()

	queries := sqlc.New(tx)
	payload := fmt.Sprintf("invocation-%s", invocationID)

	inserted, err := queries.InsertAccessLog(ctx, payload)
	if err != nil {
		logger.ErrorContext(ctx, "insert failed", slog.String("error", err.Error()))
		return Response{}, fmt.Errorf("insert access log: %w", err)
	}
	logger.InfoContext(ctx, "insert succeeded", slog.Int64("inserted_id", inserted.ID))

	latest, err := queries.GetLatestAccessLog(ctx)
	if err != nil {
		logger.ErrorContext(ctx, "select failed", slog.String("error", err.Error()))
		return Response{}, fmt.Errorf("select latest access log: %w", err)
	}
	logger.InfoContext(ctx, "select succeeded", slog.Int64("latest_id", latest.ID))

	if err := tx.Commit(ctx); err != nil {
		logger.ErrorContext(ctx, "commit failed", slog.String("error", err.Error()))
		return Response{}, fmt.Errorf("commit transaction: %w", err)
	}

	return Response{
		InvocationID:  invocationID,
		InsertedID:    inserted.ID,
		LatestPayload: latest.Payload,
	}, nil
}
