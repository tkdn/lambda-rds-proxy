package config

import (
	"fmt"
	"os"
	"time"
)

type Config struct {
	DatabaseURL     string
	ExecMode        string
	MaxConnLifetime time.Duration
}

func LoadFromEnv() (Config, error) {
	cfg := Config{
		DatabaseURL: os.Getenv("DATABASE_URL"),
		ExecMode:    os.Getenv("EXEC_MODE"),
	}
	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL is required")
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
