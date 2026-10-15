#!/usr/bin/env bash
# ==============================================================================
# GKE Standard RBAC vs. Fleet Team Scopes — Demo Verification Script
# ==============================================================================
set -euo pipefail

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
export CLUSTER_A="${CLUSTER_A:-cluster-a}"
export REGION_1="${REGION_1:-europe-west1}"
export CLUSTER_B="${CLUSTER_B:-cluster-b}"
export REGION_2="${REGION_2:-us-central1}"
export SCOPE_NAME="${SCOPE_NAME:-team-payments}"
export FLEET_NS="${FLEET_NS:-ns-fleet-payments}"

echo "=============================================================================="
echo "Moment 1: Verifying Zero-Touch Namespace & RoleBinding Actuation on Both Clusters"
echo "=============================================================================="
for CLUSTER_SPEC in "${CLUSTER_A}:${REGION_1}" "${CLUSTER_B}:${REGION_2}"; do
  CLUSTER="${CLUSTER_SPEC%%:*}"
  REGION="${CLUSTER_SPEC##*:}"
  echo ">>> Cluster: ${CLUSTER} (${REGION}) <<<"
  gcloud container fleet memberships get-credentials "${CLUSTER}" --location="${REGION}" --project="${PROJECT_ID}"
  kubectl get ns "${FLEET_NS}"
  kubectl get rolebinding -n "${FLEET_NS}"
done

echo ""
echo "=============================================================================="
echo "Moment 2: Emitting Deleted-Pod Error Log & Verifying Fleet Scope Logs Bucket"
echo "=============================================================================="
gcloud logging write stdout \
  "FATAL: Checkout DB timeout code=5004 (crashed pod crash-demo)" \
  --severity=ERROR \
  --monitored-resource-type=k8s_container \
  --monitored-resource-labels="project_id=${PROJECT_ID},location=${REGION_1},cluster_name=${CLUSTER_A},namespace_name=${FLEET_NS},pod_name=crash-demo,container_name=payment-worker" \
  --project="${PROJECT_ID}"

echo "Waiting 5s for Log Router ingestion..."
sleep 5

echo ">>> Reading from isolated Fleet Scope Log View (fleet-o11y-scope-${SCOPE_NAME}-k8s_container): <<<"
gcloud logging read "resource.labels.namespace_name=\"${FLEET_NS}\"" \
  --bucket="fleet-o11y-scope-${SCOPE_NAME}" \
  --location=global \
  --view="fleet-o11y-scope-${SCOPE_NAME}-k8s_container" \
  --project="${PROJECT_ID}" \
  --limit=5
