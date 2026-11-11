.PHONY: help test test-ui pushgateway-start pushgateway-stop test-reporter pull-artifact

PUSHGATEWAY_CONTAINER ?= grid-pushgateway
PUSHGATEWAY_PORT ?= 9091

TEST_NAME ?=
OUTPUT_DIR ?= ./playwright-report

help:
	@echo "Available targets:"
	@echo "  test               - Run Playwright tests headlessly"
	@echo "  test-ui            - Run Playwright tests with interactive UI"
	@echo "  pushgateway-start  - Start a local Pushgateway container on :9091"
	@echo "  pushgateway-stop   - Stop and remove the local Pushgateway container"
	@echo "  test-reporter      - Run tests against local Pushgateway to validate reporter"
	@echo "  pull-artifact      - Download latest Playwright report from S3 (TEST_NAME=<name>)"

test:
	cd playwright-synthetics && npx playwright test

test-ui:
	cd playwright-synthetics && npx playwright test --ui

pushgateway-start:
	docker run -d -p $(PUSHGATEWAY_PORT):9091 --name $(PUSHGATEWAY_CONTAINER) prom/pushgateway
	@echo "Pushgateway running at http://localhost:$(PUSHGATEWAY_PORT)"

pushgateway-stop:
	docker rm -f $(PUSHGATEWAY_CONTAINER) || true

test-reporter:
	cd playwright-synthetics && PUSHGATEWAY_URL=http://localhost:$(PUSHGATEWAY_PORT) GRID_ENV=local npx playwright test

pull-artifact:
	./scripts/pull-artifact.sh $(TEST_NAME) $(OUTPUT_DIR)
