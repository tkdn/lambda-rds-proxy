package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/lambda"

	"github.com/tkdn/lambda-rds-proxy/loadgen"
)

func main() {
	functionName := flag.String("function", "", "対象Lambda関数名(必須)")
	count := flag.Int("n", 100, "総リクエスト数")
	concurrency := flag.Int("c", 10, "並列数")
	outPath := flag.String("out", "", "JSON Lines出力先ファイル(未指定時は標準出力)")
	flag.Parse()

	if *functionName == "" {
		fmt.Fprintln(os.Stderr, "-function is required")
		os.Exit(1)
	}

	allSucceeded, err := run(*functionName, *count, *concurrency, *outPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}
	if !allSucceeded {
		os.Exit(1)
	}
}

func run(functionName string, count, concurrency int, outPath string) (allSucceeded bool, err error) {
	ctx := context.Background()
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return false, fmt.Errorf("failed to load AWS config: %w", err)
	}
	client := lambda.NewFromConfig(awsCfg)

	results := loadgen.Run(ctx, client, loadgen.InvokeConfig{
		FunctionName: functionName,
		Count:        count,
		Concurrency:  concurrency,
	})

	out := io.Writer(os.Stdout)
	if outPath != "" {
		f, createErr := os.Create(outPath)
		if createErr != nil {
			return false, fmt.Errorf("failed to create output file: %w", createErr)
		}
		defer func() {
			if closeErr := f.Close(); closeErr != nil && err == nil {
				err = fmt.Errorf("failed to close output file: %w", closeErr)
			}
		}()
		out = f
	}

	encoder := json.NewEncoder(out)
	successCount := 0
	for _, r := range results {
		if encErr := encoder.Encode(r); encErr != nil {
			return false, fmt.Errorf("failed to encode result: %w", encErr)
		}
		if r.Status == loadgen.StatusSuccess {
			successCount++
		}
	}

	fmt.Fprintf(os.Stderr, "done: %d/%d succeeded\n", successCount, len(results))
	return successCount == len(results), nil
}
