#!/usr/bin/env bash
# ==============================================================================
# 02-setup-track-a-rbac.sh — Track A: Standard Per-Cluster Kubernetes RBAC
# Matches Blog Section: "A. Standard Per-Cluster Kubernetes RBAC Approach"
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Track A: Granting roles/container.clusterViewer to ${ALPHA_USER} ==="
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="user:${ALPHA_USER}" \
  --role="roles/container.clusterViewer" \
  --condition=None \
  --quiet >/dev/null

echo "=== Track A: Applying Namespace (ns-standard-checkout) & RoleBinding per cluster ==="
for CLUSTER_SPEC in "cluster-a:${REGION_1}" "cluster-b:${REGION_2}"; do
  CLUSTER="${CLUSTER_SPEC%%:*}"
  REGION="${CLUSTER_SPEC##*:}"
  echo ">>> Configuring ${CLUSTER} (${REGION}) <<<"
  gcloud container clusters get-credentials "${CLUSTER}" --region="${REGION}" --project="${PROJECT_ID}"
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ns-standard-checkout
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: standard-checkout-edit
  namespace: ns-standard-checkout
subjects:
  - kind: User
    name: "${ALPHA_USER}"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit
  apiGroup: rbac.authorization.k8s.io
EOF
  kubectl describe rolebindings -n ns-standard-checkout
done

echo "=== Track A setup complete! ==="
