package dbconn

import (
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tkdn/lambda-rds-proxy/config"
)

func BuildPoolConfig(cfg config.Config) (*pgxpool.Config, error) {
	poolCfg, err := pgxpool.ParseConfig(cfg.DatabaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse DATABASE_URL: %w", err)
	}

	switch cfg.ExecMode {
	case config.ExecModeCacheStatement:
		poolCfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeCacheStatement
	case config.ExecModeSimpleProtocol:
		poolCfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
	case config.ExecModeDescribeExec:
		poolCfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeDescribeExec
	default:
		return nil, fmt.Errorf("unknown EXEC_MODE: %q", cfg.ExecMode)
	}

	// pgxpool.ParseConfig経由のためデフォルトは defaultMaxConnLifetime = time.Hour (pgxpool/pool.go)。
	// After-2パターンのみ環境変数 MAX_CONN_LIFETIME=30s で上書きする。
	if cfg.MaxConnLifetime > 0 {
		poolCfg.MaxConnLifetime = cfg.MaxConnLifetime
	}

	return poolCfg, nil
}
