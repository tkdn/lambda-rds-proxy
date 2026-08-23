package loadgen

import "time"

type Status string

const (
	StatusSuccess Status = "success"
	StatusError   Status = "error"
)

// Result は1回のLambda Invoke呼び出しの記録。
//
// InvocationIDはloadgen側で発番するローカルな識別子であり、handler側が
// レスポンスに含むinvocation_id(Payload内)とは別物で直接は対応しない。
// CloudWatchログと突き合わせる場合は、StartTime/EndTimeによる時刻ウィンドウ
// での相関、またはPayloadをパースしてhandler側のinvocation_idを取り出す
// 必要がある。
type Result struct {
	InvocationID string    `json:"invocation_id"`
	StartTime    time.Time `json:"start_time"`
	EndTime      time.Time `json:"end_time"`
	Status       Status    `json:"status"`
	StatusCode   int32     `json:"status_code,omitempty"`
	Payload      string    `json:"payload,omitempty"`
	Error        string    `json:"error,omitempty"`
}
