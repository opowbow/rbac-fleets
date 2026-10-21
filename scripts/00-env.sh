#!/usr/bin/env bash
# ==============================================================================
# 00-env.sh — Shared Environment Variables for GKE RBAC vs. Fleet Team Scopes
# Usage: source ./scripts/00-env.sh
# ==============================================================================

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
export ADMIN_USER="${ADMIN_USER:-$(gcloud config get-value account)}"
export ADMIN_DOMAIN="${ADMIN_USER#*@}"
export ALPHA_USER="${ALPHA_USER:-alpha@${ADMIN_DOMAIN}}"
export BRAVO_USER="${BRAVO_USER:-bravo@${ADMIN_DOMAIN}}"
export REGION_1="${REGION_1:-europe-west1}"
export REGION_2="${REGION_2:-us-central1}"

echo "Environment configured:"
echo "  PROJECT_ID : ${PROJECT_ID}"
echo "  ADMIN_USER : ${ADMIN_USER}"
echo "  ALPHA_USER : ${ALPHA_USER} (Track A - Standard K8s RBAC)"
echo "  BRAVO_USER : ${BRAVO_USER} (Track B - GKE Fleet Team Scope)"
echo "  CLUSTERS   : cluster-a (${REGION_1}), cluster-b (${REGION_2})"
