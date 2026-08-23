package migrations

import _ "embed"

//go:embed 0001_create_access_logs.sql
var CreateAccessLogs string
