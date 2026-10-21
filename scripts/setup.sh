#!/usr/bin/env bash
# ==============================================================================
# setup.sh — Environment, Clusters, Track A (RBAC) & Track B (Fleet Scopes)
# ==============================================================================

export PROJECT_ID=$(gcloud config get-value project)
export ADMIN_USER=$(gcloud config get-value account)
export ADMIN_DOMAIN="${ADMIN_USER#*@}"
export ALPHA_USER="${ALPHA_USER:-alpha@${ADMIN_DOMAIN}}"
export BRAVO_USER="${BRAVO_USER:-bravo@${ADMIN_DOMAIN}}"
export REGION_1="europe-west1"
export REGION_2="us-central1"
# 1. Enable GKE, Fleet, Connect Gateway & Observability APIs
gcloud services enable \
  container.googleapis.com \
  gkehub.googleapis.com \
  connectgateway.googleapis.com \
  anthos.googleapis.com \
  cloudresourcemanager.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  --project="${PROJECT_ID}"
# 2. Ensure the GKE node Service Account can write container logs to Cloud Logging
PROJECT_NUM=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${PROJECT_NUM}-compute@developer.gserviceaccount.com" \
  --role="roles/container.defaultNodeServiceAccount" \
  --condition=None \
  --quiet >/dev/null
# 3. Provision two GKE clusters registered to the project's Fleet
gcloud container clusters create-auto cluster-a \
  --region="${REGION_1}" \
  --enable-fleet \
  --project="${PROJECT_ID}" \
  --async
gcloud container clusters create-auto cluster-b \
  --region="${REGION_2}" \
  --enable-fleet \
  --project="${PROJECT_ID}"

# A. Standard Per-Cluster Kubernetes RBAC Approach
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="user:${ALPHA_USER}" --role="roles/container.clusterViewer" --condition=None --quiet >/dev/null
for CLUSTER_SPEC in "cluster-a:${REGION_1}" "cluster-b:${REGION_2}"; do
  CLUSTER="${CLUSTER_SPEC%%:*}"
  REGION="${CLUSTER_SPEC##*:}"
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
done

kubectl describe rolebindings -n ns-standard-checkout

# Track B. GKE Fleet Team Scopes
# 1. Enable Fleet Observability & Scope Logs
gcloud container fleet fleetobservability enable --project="${PROJECT_ID}"
gcloud container fleet fleetobservability update --project="${PROJECT_ID}" \
  --logging-config=<(printf "loggingConfig:\n  defaultConfig:\n    mode: COPY\n  fleetScopeLogsConfig:\n    mode: COPY\n")

# 2. Create the Team Scope & Bind Target Clusters
gcloud container fleet scopes create team-payments --project="${PROJECT_ID}"
gcloud container fleet memberships bindings create bind-cluster-a \
  --membership=cluster-a --location="${REGION_1}" --scope=team-payments --project="${PROJECT_ID}"
gcloud container fleet memberships bindings create bind-cluster-b \
  --membership=cluster-b --location="${REGION_2}" --scope=team-payments --project="${PROJECT_ID}"

# 3. Create the Fleet Namespace & Bind the Team Identity
# 1. Define the namespace ONCE at the Scope level
gcloud container fleet scopes namespaces create ns-fleet-payments \
  --scope=team-payments \
  --project="${PROJECT_ID}"
# 2. Bind the developer/group ONCE to the Scope
gcloud beta container fleet scopes add-app-operator-binding team-payments \
  --role=edit \
  --user="${BRAVO_USER}" \
  --project="${PROJECT_ID}"
