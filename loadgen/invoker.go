package loadgen

import (
	"context"
	"sync"
	"time"
	"uuid"

	"github.com/aws/aws-sdk-go-v2/service/lambda"
)

type InvokeConfig struct {
	FunctionName string
	Count        int
	Concurrency  int
}

// Run はFunctionNameをCount回、Concurrency並列でInvokeする。1件のエラーで
// 全体を打ち切らず、全リクエストの成否を独立に記録する(errgroupではなく
// WaitGroup+チャネルを使う理由)。
func Run(ctx context.Context, client *lambda.Client, cfg InvokeConfig) []Result {
	results := make([]Result, cfg.Count)
	sem := make(chan struct{}, cfg.Concurrency)
	var wg sync.WaitGroup

	for i := range cfg.Count {
		wg.Add(1)
		sem <- struct{}{}
		go func(idx int) {
			defer wg.Done()
			defer func() { <-sem }()
			results[idx] = invokeOne(ctx, client, cfg.FunctionName)
		}(i)
	}

	wg.Wait()
	return results
}

func invokeOne(ctx context.Context, client *lambda.Client, functionName string) Result {
	invocationID := uuid.New().String()
	start := time.Now()

	out, err := client.Invoke(ctx, &lambda.InvokeInput{
		FunctionName: &functionName,
	})

	result := Result{
		InvocationID: invocationID,
		StartTime:    start,
		EndTime:      time.Now(),
	}

	if err != nil {
		result.Status = StatusError
		result.Error = err.Error()
		return result
	}

	result.StatusCode = out.StatusCode
	result.Payload = string(out.Payload)

	if out.FunctionError != nil {
		result.Status = StatusError
		result.Error = *out.FunctionError
		return result
	}

	result.Status = StatusSuccess
	return result
}
