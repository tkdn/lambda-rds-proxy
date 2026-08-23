package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
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

	ctx := context.Background()
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to load AWS config: %v\n", err)
		os.Exit(1)
	}
	client := lambda.NewFromConfig(awsCfg)

	results := loadgen.Run(ctx, client, loadgen.InvokeConfig{
		FunctionName: *functionName,
		Count:        *count,
		Concurrency:  *concurrency,
	})

	out := os.Stdout
	if *outPath != "" {
		f, err := os.Create(*outPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "failed to create output file: %v\n", err)
			os.Exit(1)
		}
		defer func() {
			if err := f.Close(); err != nil {
				fmt.Fprintf(os.Stderr, "failed to close output file: %v\n", err)
			}
		}()
		out = f
	}

	encoder := json.NewEncoder(out)
	successCount := 0
	for _, r := range results {
		if err := encoder.Encode(r); err != nil {
			fmt.Fprintf(os.Stderr, "failed to encode result: %v\n", err)
			os.Exit(1)
		}
		if r.Status == loadgen.StatusSuccess {
			successCount++
		}
	}

	fmt.Fprintf(os.Stderr, "done: %d/%d succeeded\n", successCount, len(results))
}
