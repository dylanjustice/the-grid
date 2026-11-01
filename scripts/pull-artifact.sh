#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-the-grid-synthetics}"
BUCKET="${BUCKET:-393657359434-us-east-2-artifacts}"
REGION="${REGION:-us-east-2}"
TEST_NAME="${1:-}"
OUTPUT_DIR="${2:-./playwright-report}"

if [ -n "$TEST_NAME" ]; then
    SELECTOR="-l the-grid.io/synthetic-test=$TEST_NAME"
    echo "Looking for most recent workflow for test: $TEST_NAME"
else
    SELECTOR=""
    echo "Looking for most recent workflow in namespace: $NAMESPACE"
fi

WORKFLOW=$(kubectl get workflows -n "$NAMESPACE" $SELECTOR \
    --sort-by='.metadata.creationTimestamp' \
    -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || true)

if [ -z "$WORKFLOW" ]; then
    echo "error: no workflows found" >&2
    exit 1
fi

echo "Workflow: $WORKFLOW"

S3_KEY=$(kubectl get workflow "$WORKFLOW" -n "$NAMESPACE" \
    -o jsonpath='{.status.nodes[*].outputs.artifacts[?(@.name=="playwright-report")].s3.key}' \
    2>/dev/null | tr ' ' '\n' | grep . | head -1 || true)

if [ -z "$S3_KEY" ]; then
    echo "error: no playwright-report artifact found in workflow $WORKFLOW (artifact storage may not be enabled or workflow may not have completed)" >&2
    exit 1
fi

echo "Downloading: s3://$BUCKET/$S3_KEY"

TMPFILE=$(mktemp /tmp/playwright-report.XXXXXX.tgz)
trap 'rm -f "$TMPFILE"' EXIT

aws s3 cp "s3://$BUCKET/$S3_KEY" "$TMPFILE" --region "$REGION"

mkdir -p "$OUTPUT_DIR"
tar -xzf "$TMPFILE" -C "$OUTPUT_DIR" --strip-components=1 2>/dev/null \
    || tar -xzf "$TMPFILE" -C "$OUTPUT_DIR"

echo "Report extracted to: $OUTPUT_DIR"
echo "Open:  open $OUTPUT_DIR/index.html"
