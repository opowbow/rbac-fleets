#!/usr/bin/env bash
# ==============================================================================
# demo-verify.sh — Master Verification Script (Runs Test 1 & Test 2)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================================================="
echo "Test 1: Verify Automatic Multi-Cluster Namespace & RBAC Setup (04-test-rbac.sh)"
echo "=============================================================================="
"${SCRIPT_DIR}/04-test-rbac.sh"

echo ""
echo "=============================================================================="
echo "Test 2: Crashed Pod Logging — Alpha vs. Bravo (05-test-logging.sh)"
echo "=============================================================================="
"${SCRIPT_DIR}/05-test-logging.sh"

echo ""
echo "=== All Verification Tests Complete! ==="
