#!/usr/bin/env bash
# ==============================================================================
# GKE Standard RBAC vs. Fleet Team Scopes — Surgical Teardown Script
#
# By default, safely removes ONLY the demo resources (Fleet RBACRoleBindings,
# Fleet Namespace, Membership Bindings, Team Scope, Log Router Sink, and
# Track A Namespace) while leaving your existing clusters and project intact!
#
# Optional flags:
#   --delete-clusters   Also delete cluster-a and cluster-b
#   --delete-project    Delete the entire GCP project (ONLY use on a throwaway project)
# ==============================================================================
set -euo pipefail

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
export CLUSTER_A="${CLUSTER_A:-cluster-a}"
export REGION_1="${REGION_1:-europe-west1}"
export CLUSTER_B="${CLUSTER_B:-cluster-b}"
export REGION_2="${REGION_2:-us-central1}"
export SCOPE_NAME="${SCOPE_NAME:-team-payments}"
export FLEET_NS="${FLEET_NS:-ns-fleet-payments}"
export STD_NS="${STD_NS:-ns-standard-checkout}"

DELETE_CLUSTERS=false
DELETE_PROJECT=false

for arg in "$@"; do
  case "$arg" in
    --delete-clusters) DELETE_CLUSTERS=true ;;
    --delete-project)  DELETE_PROJECT=true ;;
  esac
done

echo "=== Cleaning up GKE RBAC vs. Fleets demo resources in project: ${PROJECT_ID} ==="

# 1. Delete all RBACRoleBindings under the Team Scope
echo "1. Removing Fleet RBACRoleBindings in scope ${SCOPE_NAME}..."
for RRB in $(gcloud container fleet scopes rbacrolebindings list \
  --scope="${SCOPE_NAME}" --project="${PROJECT_ID}" --format="value(name.basename())" 2>/dev/null || true); do
  echo "   Deleting RBACRoleBinding: ${RRB}"
  gcloud container fleet scopes rbacrolebindings delete "${RRB}" \
    --scope="${SCOPE_NAME}" --project="${PROJECT_ID}" --quiet || true
done

# 2. Delete the Fleet Namespace (automatically removes ns-fleet-payments from both clusters)
echo "2. Deleting Fleet Namespace ${FLEET_NS}..."
gcloud container fleet scopes namespaces delete "${FLEET_NS}" \
  --scope="${SCOPE_NAME}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 3. Delete Cluster Membership Bindings from the Team Scope
echo "3. Removing cluster membership bindings from scope ${SCOPE_NAME}..."
LOC_A=$(gcloud container fleet memberships list --project="${PROJECT_ID}" --filter="name~${CLUSTER_A}" --format="value(location)" | head -n 1 || echo "${REGION_1}")
LOC_B=$(gcloud container fleet memberships list --project="${PROJECT_ID}" --filter="name~${CLUSTER_B}" --format="value(location)" | head -n 1 || echo "${REGION_2}")

gcloud container fleet memberships bindings delete "bind-${CLUSTER_A}" \
  --membership="${CLUSTER_A}" --location="${LOC_A:-${REGION_1}}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true

gcloud container fleet memberships bindings delete "bind-${CLUSTER_B}" \
  --membership="${CLUSTER_B}" --location="${LOC_B:-${REGION_2}}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 4. Delete the Team Scope
echo "4. Deleting Fleet Team Scope ${SCOPE_NAME}..."
gcloud container fleet scopes delete "${SCOPE_NAME}" \
  --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 5. Delete the Scope Log Router Sink & Log Bucket
echo "5. Removing Scope Log Router Sink & Log Bucket..."
PROJECT_NUM=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
gcloud logging sinks delete "fleet-o11y-${PROJECT_NUM}-scope-${SCOPE_NAME}" \
  --project="${PROJECT_ID}" --quiet 2>/dev/null || true

gcloud logging buckets delete "fleet-o11y-scope-${SCOPE_NAME}" \
  --location=global --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 6. Delete Track A Standard RBAC Namespace from both clusters
echo "6. Deleting Track A namespace (${STD_NS}) from ${CLUSTER_A} and ${CLUSTER_B}..."
for CLUSTER_SPEC in "${CLUSTER_A}:${REGION_1}" "${CLUSTER_B}:${REGION_2}"; do
  CLUSTER="${CLUSTER_SPEC%%:*}"
  REGION="${CLUSTER_SPEC##*:}"
  if gcloud container clusters get-credentials "${CLUSTER}" --region="${REGION}" --project="${PROJECT_ID}" 2>/dev/null; then
    kubectl delete namespace "${STD_NS}" --ignore-not-found --wait=false || true
  fi
done

# 7. Optional: Delete clusters or entire throwaway project
if [[ "${DELETE_CLUSTERS}" == "true" ]]; then
  echo "7. Deleting ${CLUSTER_A} and ${CLUSTER_B}..."
  gcloud container clusters delete "${CLUSTER_A}" --region="${REGION_1}" --project="${PROJECT_ID}" --quiet --async || true
  gcloud container clusters delete "${CLUSTER_B}" --region="${REGION_2}" --project="${PROJECT_ID}" --quiet || true
fi

if [[ "${DELETE_PROJECT}" == "true" ]]; then
  echo "8. Deleting entire GCP project ${PROJECT_ID}..."
  gcloud projects delete "${PROJECT_ID}" --quiet
fi

echo "=== Teardown Complete! ==="
