package main

import (
	"context"
	"encoding/json"

	"github.com/aws/aws-lambda-go/lambda"
)

type response struct {
	Message string `json:"message"`
}

func handleRequest(ctx context.Context, event json.RawMessage) (response, error) {
	return response{Message: "handler placeholder: DB access not yet wired"}, nil
}

func main() {
	lambda.Start(handleRequest)
}
