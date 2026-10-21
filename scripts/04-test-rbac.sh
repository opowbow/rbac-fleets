#!/usr/bin/env bash
# ==============================================================================
# 04-test-rbac.sh — Test 1: Verify Multi-Cluster Namespace & RBAC (Alpha vs Bravo)
# Matches Blog Section: "Test 1: Verify automatic multi-cluster namespace & RBAC setup (Alpha vs. Bravo)"
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

for CLUSTER_SPEC in "cluster-a:${REGION_1}" "cluster-b:${REGION_2}"; do
  CLUSTER="${CLUSTER_SPEC%%:*}"
  REGION="${CLUSTER_SPEC##*:}"
  echo ">>> Checking ${CLUSTER} (${REGION}) <<<"
  gcloud container fleet memberships get-credentials "${CLUSTER}" --location="${REGION}" --project="${PROJECT_ID}"
  kubectl get ns ns-fleet-payments
  kubectl get rolebinding -n ns-fleet-payments
  echo -n "Alpha in ns-standard-checkout (Expected: yes): "
  kubectl auth can-i create deployments -n ns-standard-checkout --as="${ALPHA_USER}" || true
  echo -n "Alpha in ns-fleet-payments    (Expected: no):  "
  kubectl auth can-i get pods -n ns-fleet-payments --as="${ALPHA_USER}" || true
  echo -n "Bravo in ns-fleet-payments    (Expected: yes): "
  kubectl auth can-i create deployments -n ns-fleet-payments --as="${BRAVO_USER}" || true
  echo -n "Bravo in ns-standard-checkout (Expected: no):  "
  kubectl auth can-i get pods -n ns-standard-checkout --as="${BRAVO_USER}" || true
done
