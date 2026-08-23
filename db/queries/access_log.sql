-- name: InsertAccessLog :one
INSERT INTO access_logs (payload) VALUES ($1) RETURNING *;

-- name: GetLatestAccessLog :one
SELECT * FROM access_logs ORDER BY created_at DESC LIMIT 1;
