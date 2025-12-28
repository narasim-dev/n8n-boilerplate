#!/bin/sh

set -e

SCRIPT_DIR="$(dirname "$0")"
TOTAL_PASSED=0
TOTAL_FAILED=0

echo "========================================"
echo "=== n8n Test Suite ==="
echo "========================================"
echo ""

echo ">>> Running DB Tests..."
echo ""

if sh "$SCRIPT_DIR/db/test-migrations.sh"; then
    echo ""
else
    echo "DB migration tests failed!"
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi

if sh "$SCRIPT_DIR/db/test-workflows.sh"; then
    echo ""
else
    echo "DB workflow tests failed!"
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi

echo ">>> Running API Tests..."
echo ""

if sh "$SCRIPT_DIR/api/test-agent-chat.sh"; then
    echo ""
else
    echo "API agent chat tests failed!"
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi

echo "========================================"
if [ "$TOTAL_FAILED" -gt 0 ]; then
    echo "=== SOME TESTS FAILED ==="
    exit 1
else
    echo "=== ALL TEST SUITES PASSED ==="
fi
echo "========================================"
