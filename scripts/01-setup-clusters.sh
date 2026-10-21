#!/usr/bin/env bash
# ==============================================================================
# 01-setup-clusters.sh — Enable APIs, Node SA IAM & Provision GKE Fleet Clusters
# Matches Blog Section: "Setting Up the Multi-Cluster Environment"
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

# 1. Enable GKE, Fleet, Connect Gateway & Observability APIs
echo "=== 1. Enabling GKE, Fleet, Connect Gateway & Observability APIs ==="
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
echo "=== 2. Granting roles/container.defaultNodeServiceAccount to Compute Engine default SA ==="
PROJECT_NUM=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${PROJECT_NUM}-compute@developer.gserviceaccount.com" \
  --role="roles/container.defaultNodeServiceAccount" \
  --condition=None \
  --quiet >/dev/null

# 3. Provision two GKE clusters registered to the project's Fleet
echo "=== 3. Provisioning cluster-a (${REGION_1}) and cluster-b (${REGION_2}) ==="
if ! gcloud container clusters describe cluster-a --region="${REGION_1}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud container clusters create-auto cluster-a \
    --region="${REGION_1}" \
    --enable-fleet \
    --project="${PROJECT_ID}" \
    --async
else
  echo "cluster-a already exists in ${REGION_1}; ensuring Fleet registration..."
  gcloud container clusters update cluster-a --region="${REGION_1}" --enable-fleet --project="${PROJECT_ID}" || true
fi

if ! gcloud container clusters describe cluster-b --region="${REGION_2}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud container clusters create-auto cluster-b \
    --region="${REGION_2}" \
    --enable-fleet \
    --project="${PROJECT_ID}"
else
  echo "cluster-b already exists in ${REGION_2}; ensuring Fleet registration..."
  gcloud container clusters update cluster-b --region="${REGION_2}" --enable-fleet --project="${PROJECT_ID}" || true
fi

# Wait for any async cluster creation operation (e.g., cluster-a) to finish
while [[ -n "$(gcloud container operations list --project="${PROJECT_ID}" --filter="status!=DONE" --format="value(name)")" ]]; do
  echo "Waiting for cluster operations to complete..."
  sleep 20
done

echo "=== Multi-cluster environment ready! ==="
