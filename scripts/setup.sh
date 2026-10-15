#!/usr/bin/env bash
# ==============================================================================
# GKE Standard RBAC vs. Fleet Team Scopes — Setup Script
# ==============================================================================
set -euo pipefail

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
export DEV_SUBJECT="${DEV_SUBJECT:-admin@powerm-1.altostrat.com}"
export DEV_PRINCIPAL="user:${DEV_SUBJECT}"
export CLUSTER_A="${CLUSTER_A:-cluster-a}"
export REGION_1="${REGION_1:-europe-west1}"
export CLUSTER_B="${CLUSTER_B:-cluster-b}"
export REGION_2="${REGION_2:-us-central1}"
export SCOPE_NAME="${SCOPE_NAME:-team-payments}"
export FLEET_NS="${FLEET_NS:-ns-fleet-payments}"
export STD_NS="${STD_NS:-ns-standard-checkout}"

echo "=== Project: ${PROJECT_ID} | Developer Identity: ${DEV_SUBJECT} ==="

# 1. Enable required GKE & Fleet APIs
gcloud services enable \
  container.googleapis.com \
  gkehub.googleapis.com \
  connectgateway.googleapis.com \
  anthos.googleapis.com \
  cloudresourcemanager.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  --project="${PROJECT_ID}"

# 2. Create cluster-a and cluster-b if they don't already exist
if ! gcloud container clusters describe "${CLUSTER_A}" --region="${REGION_1}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "=== Creating ${CLUSTER_A} (${REGION_1}) ==="
  gcloud container clusters create-auto "${CLUSTER_A}" \
    --region="${REGION_1}" --enable-fleet --project="${PROJECT_ID}" --async
fi

if ! gcloud container clusters describe "${CLUSTER_B}" --region="${REGION_2}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "=== Creating ${CLUSTER_B} (${REGION_2}) ==="
  gcloud container clusters create-auto "${CLUSTER_B}" \
    --region="${REGION_2}" --enable-fleet --project="${PROJECT_ID}"
fi

while [[ -n "$(gcloud container operations list --project="${PROJECT_ID}" --filter="status!=DONE" --format="value(name)")" ]]; do
  echo "Waiting for cluster operations to complete..."
  sleep 20
done

# Ensure both clusters are registered to the Fleet
gcloud container clusters update "${CLUSTER_A}" --region="${REGION_1}" --enable-fleet --project="${PROJECT_ID}" || true
gcloud container clusters update "${CLUSTER_B}" --region="${REGION_2}" --enable-fleet --project="${PROJECT_ID}" || true

# ==============================================================================
# 3. TRACK A: Standard Kubernetes RBAC (Repeated Manually per Cluster)
# ==============================================================================
echo "=== Track A: Applying Standard K8s RBAC (${STD_NS}) on ${CLUSTER_A} and ${CLUSTER_B} ==="
for CLUSTER_SPEC in "${CLUSTER_A}:${REGION_1}" "${CLUSTER_B}:${REGION_2}"; do
  CLUSTER="${CLUSTER_SPEC%%:*}"
  REGION="${CLUSTER_SPEC##*:}"
  gcloud container clusters get-credentials "${CLUSTER}" --region="${REGION}" --project="${PROJECT_ID}"

  kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${STD_NS}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: standard-checkout-edit
  namespace: ${STD_NS}
subjects:
  - kind: User
    name: "${DEV_SUBJECT}"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit
  apiGroup: rbac.authorization.k8s.io
EOF
done

# ==============================================================================
# 4. TRACK B: GKE Fleet Team Scope (Configured ONCE Centrally)
# ==============================================================================
echo "=== Track B: Configuring GKE Fleet Team Scope (${SCOPE_NAME}) ==="

# 4a. Enable Fleet Observability & Scope Logs routing
gcloud container fleet fleetobservability enable --project="${PROJECT_ID}" || true
cat <<EOF > /tmp/fleet-logging-config.yaml
loggingConfig:
  defaultConfig:
    mode: COPY
  fleetScopeLogsConfig:
    mode: COPY
EOF
gcloud container fleet fleetobservability update \
  --logging-config=/tmp/fleet-logging-config.yaml \
  --project="${PROJECT_ID}"

# 4b. Create the Team Scope once
gcloud container fleet scopes create "${SCOPE_NAME}" --project="${PROJECT_ID}" || true

# 4c. Auto-detect membership locations & bind both clusters to the Team Scope
LOC_A=$(gcloud container fleet memberships list --project="${PROJECT_ID}" --filter="name~${CLUSTER_A}" --format="value(location)" | head -n 1)
LOC_B=$(gcloud container fleet memberships list --project="${PROJECT_ID}" --filter="name~${CLUSTER_B}" --format="value(location)" | head -n 1)

gcloud container fleet memberships bindings create "bind-${CLUSTER_A}" \
  --membership="${CLUSTER_A}" --location="${LOC_A}" --scope="${SCOPE_NAME}" --project="${PROJECT_ID}" || true

gcloud container fleet memberships bindings create "bind-${CLUSTER_B}" \
  --membership="${CLUSTER_B}" --location="${LOC_B}" --scope="${SCOPE_NAME}" --project="${PROJECT_ID}" || true

# 4d. Create the Fleet Namespace ONCE (auto-provisioned across both clusters)
gcloud container fleet scopes namespaces create "${FLEET_NS}" \
  --scope="${SCOPE_NAME}" --project="${PROJECT_ID}" || true

# 4e. Bind the Developer Identity ONCE (sets Scope IAM, Project IAM, Log View IAM & Fleet RBACRoleBinding)
gcloud beta container fleet scopes add-app-operator-binding "${SCOPE_NAME}" \
  --role=edit --user="${DEV_SUBJECT}" --project="${PROJECT_ID}" || true

# Also create a named RBACRoleBinding for clear visibility in kubectl get rolebinding
gcloud container fleet scopes rbacrolebindings create payments-edit-binding \
  --scope="${SCOPE_NAME}" --role=edit --user="${DEV_SUBJECT}" --project="${PROJECT_ID}" || true

# 4f. Ensure the Scope Log Bucket, Views & Log Router Sink exist immediately (no waiting for background polling)
gcloud logging buckets create "fleet-o11y-scope-${SCOPE_NAME}" \
  --location=global --project="${PROJECT_ID}" 2>/dev/null || true

gcloud logging views create "fleet-o11y-scope-${SCOPE_NAME}-k8s_container" \
  --bucket="fleet-o11y-scope-${SCOPE_NAME}" --location=global \
  --log-filter='resource.type="k8s_container"' --project="${PROJECT_ID}" 2>/dev/null || true

gcloud logging views create "fleet-o11y-scope-${SCOPE_NAME}-k8s_pod" \
  --bucket="fleet-o11y-scope-${SCOPE_NAME}" --location=global \
  --log-filter='resource.type="k8s_pod"' --project="${PROJECT_ID}" 2>/dev/null || true

PROJECT_NUM=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
gcloud logging sinks create "fleet-o11y-${PROJECT_NUM}-scope-${SCOPE_NAME}" \
  "logging.googleapis.com/projects/${PROJECT_ID}/locations/global/buckets/fleet-o11y-scope-${SCOPE_NAME}" \
  --log-filter="(resource.type=\"k8s_container\" OR resource.type=\"k8s_pod\") AND resource.labels.namespace_name=\"${FLEET_NS}\"" \
  --project="${PROJECT_ID}" 2>/dev/null || true

echo "=== Setup Complete! Run ./scripts/demo-verify.sh to verify RBAC actuation & Scope Logs ==="
