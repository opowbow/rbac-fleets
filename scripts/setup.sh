#!/usr/bin/env bash
# ==============================================================================
# setup.sh — Master Setup Script (Runs 01, 02, and 03 in sequence)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================================================="
echo "Step 1/3: Multi-Cluster Environment Setup (01-setup-clusters.sh)"
echo "=============================================================================="
"${SCRIPT_DIR}/01-setup-clusters.sh"

echo ""
echo "=============================================================================="
echo "Step 2/3: Track A — Standard Per-Cluster Kubernetes RBAC (02-setup-track-a-rbac.sh)"
echo "=============================================================================="
"${SCRIPT_DIR}/02-setup-track-a-rbac.sh"

echo ""
echo "=============================================================================="
echo "Step 3/3: Track B — GKE Fleet Team Scopes & Scope Logs (03-setup-track-b-fleet.sh)"
echo "=============================================================================="
"${SCRIPT_DIR}/03-setup-track-b-fleet.sh"

echo ""
echo "=== All Setup Steps Complete! Run ./scripts/demo-verify.sh to run Test 1 & Test 2 ==="
