package loadgen

import "time"

type Status string

const (
	StatusSuccess Status = "success"
	StatusError   Status = "error"
)

// Result は1回のLambda Invoke呼び出しの記録。CloudWatchログと突き合わせるため、
// loadgen側のタイムスタンプとLambdaレスポンス本文の両方を保持する。
type Result struct {
	InvocationID string    `json:"invocation_id"`
	StartTime    time.Time `json:"start_time"`
	EndTime      time.Time `json:"end_time"`
	Status       Status    `json:"status"`
	StatusCode   int32     `json:"status_code,omitempty"`
	Payload      string    `json:"payload,omitempty"`
	Error        string    `json:"error,omitempty"`
}
