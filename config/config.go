package config

import (
	"fmt"
	"os"
	"time"
)

// ExecMode はpgx.QueryExecModeへ対応するEXEC_MODE環境変数の値。
// LoadFromEnvはhandlerからのみ呼ばれる(migratorはDATABASE_URLを直接読み、
// このパッケージを経由しない)ため、3つの実値のみを許容する。
type ExecMode string

const (
	ExecModeCacheStatement ExecMode = "cache_statement"
	ExecModeSimpleProtocol ExecMode = "simple_protocol"
	ExecModeDescribeExec   ExecMode = "describe_exec"
)

type Config struct {
	DatabaseURL     string
	ExecMode        ExecMode
	MaxConnLifetime time.Duration
}

func LoadFromEnv() (Config, error) {
	cfg := Config{
		DatabaseURL: os.Getenv("DATABASE_URL"),
		ExecMode:    ExecMode(os.Getenv("EXEC_MODE")),
	}
	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL is required")
	}

	switch cfg.ExecMode {
	case ExecModeCacheStatement, ExecModeSimpleProtocol, ExecModeDescribeExec:
	default:
		return Config{}, fmt.Errorf("unknown EXEC_MODE: %q", cfg.ExecMode)
	}

	if raw := os.Getenv("MAX_CONN_LIFETIME"); raw != "" {
		d, err := time.ParseDuration(raw)
		if err != nil {
			return Config{}, fmt.Errorf("invalid MAX_CONN_LIFETIME %q: %w", raw, err)
		}
		cfg.MaxConnLifetime = d
	}

	return cfg, nil
}
