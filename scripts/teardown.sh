#!/usr/bin/env bash
# ==============================================================================
# teardown.sh — Surgical Teardown Script for GKE RBAC vs. Fleet Team Scopes
#
# By default, safely removes the demo resources (test Deployments, Fleet
# app-operator binding & RBACRoleBindings, Fleet Namespace, Membership Bindings,
# Team Scope, Scope Log Sink/Bucket, and Track A Namespace) while leaving your
# clusters and GCP project intact.
#
# Optional flags:
#   --delete-clusters   Also delete cluster-a and cluster-b
#   --delete-project    Delete the entire GCP project (use ONLY on a throwaway project)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

DELETE_CLUSTERS=false
DELETE_PROJECT=false

for arg in "$@"; do
  case "$arg" in
    --delete-clusters) DELETE_CLUSTERS=true ;;
    --delete-project)  DELETE_PROJECT=true ;;
  esac
done

echo "=== Cleaning up GKE RBAC vs. Fleets demo resources in project: ${PROJECT_ID} ==="

# 1. Remove any leftover test Deployments and Track A namespace
echo "1. Removing test workloads and Track A namespace (ns-standard-checkout)..."
for CLUSTER_SPEC in "cluster-a:${REGION_1}" "cluster-b:${REGION_2}"; do
  CLUSTER="${CLUSTER_SPEC%%:*}"
  REGION="${CLUSTER_SPEC##*:}"
  if gcloud container clusters get-credentials "${CLUSTER}" --region="${REGION}" --project="${PROJECT_ID}" 2>/dev/null; then
    kubectl delete deployment payment-worker -n ns-standard-checkout --ignore-not-found --wait=false || true
    kubectl delete deployment payment-worker -n ns-fleet-payments --ignore-not-found --wait=false || true
    kubectl delete namespace ns-standard-checkout --ignore-not-found --wait=false || true
  fi
done

# 2. Remove Track B app-operator binding and RBACRoleBindings under team-payments
echo "2. Removing Track B app-operator binding and Fleet RBACRoleBindings..."
gcloud beta container fleet scopes remove-app-operator-binding team-payments \
  --role=edit \
  --user="${BRAVO_USER}" \
  --project="${PROJECT_ID}" 2>/dev/null || true

for RRB in $(gcloud container fleet scopes rbacrolebindings list \
  --scope=team-payments --project="${PROJECT_ID}" --format="value(name.basename())" 2>/dev/null || true); do
  echo "   Deleting RBACRoleBinding: ${RRB}"
  gcloud container fleet scopes rbacrolebindings delete "${RRB}" \
    --scope=team-payments --project="${PROJECT_ID}" --quiet || true
done

# 3. Delete the Fleet Namespace (automatically removes ns-fleet-payments from both clusters)
echo "3. Deleting Fleet Namespace (ns-fleet-payments)..."
gcloud container fleet scopes namespaces delete ns-fleet-payments \
  --scope=team-payments --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 4. Delete Cluster Membership Bindings from the Team Scope
echo "4. Removing cluster membership bindings from scope team-payments..."
gcloud container fleet memberships bindings delete bind-cluster-a \
  --membership=cluster-a --location="${REGION_1}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true

gcloud container fleet memberships bindings delete bind-cluster-b \
  --membership=cluster-b --location="${REGION_2}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 5. Delete the Team Scope
echo "5. Deleting Fleet Team Scope (team-payments)..."
gcloud container fleet scopes delete team-payments \
  --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 6. Delete the Scope Log Router Sink & Log Bucket
echo "6. Removing Scope Log Router Sink & Log Bucket..."
PROJECT_NUM=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
gcloud logging sinks delete "fleet-o11y-${PROJECT_NUM}-scope-team-payments" \
  --project="${PROJECT_ID}" --quiet 2>/dev/null || true

gcloud logging buckets delete "fleet-o11y-scope-team-payments" \
  --location=global --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 7. Optional: Delete clusters or entire throwaway project
if [[ "${DELETE_CLUSTERS}" == "true" ]]; then
  echo "7. Deleting cluster-a (${REGION_1}) and cluster-b (${REGION_2})..."
  gcloud container clusters delete cluster-a --region="${REGION_1}" --project="${PROJECT_ID}" --quiet --async || true
  gcloud container clusters delete cluster-b --region="${REGION_2}" --project="${PROJECT_ID}" --quiet || true
fi

if [[ "${DELETE_PROJECT}" == "true" ]]; then
  echo "8. Deleting entire GCP project ${PROJECT_ID}..."
  gcloud projects delete "${PROJECT_ID}" --quiet
fi

echo "=== Teardown Complete! ==="
