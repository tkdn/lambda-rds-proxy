.PHONY: build-handler build-migrator build-loadgen

build-handler:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o bootstrap ./cmd/handler
	zip -q -j handler.zip bootstrap
	rm bootstrap

build-migrator:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o bootstrap ./cmd/migrator
	zip -q -j migrator.zip bootstrap
	rm bootstrap

build-loadgen:
	go build -o bin/loadgen ./cmd/loadgen
