#!/usr/bin/env bash
# ==============================================================================
# 03-setup-track-b-fleet.sh — Track B: GKE Fleet Team Scopes & Scope Logs
# Matches Blog Section: "Track B. GKE Fleet Team Scopes"
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

# 1. Enable Fleet Observability & Scope Logs
echo "=== 1. Enabling Fleet Observability & Scope Logs (COPY mode) ==="
gcloud container fleet fleetobservability enable --project="${PROJECT_ID}" || true
gcloud container fleet fleetobservability update --project="${PROJECT_ID}" \
  --logging-config=<(printf "loggingConfig:\n  defaultConfig:\n    mode: COPY\n  fleetScopeLogsConfig:\n    mode: COPY\n")

# 2. Create the Team Scope & Bind Target Clusters
echo "=== 2. Creating Team Scope (team-payments) and binding cluster-a & cluster-b ==="
gcloud container fleet scopes create team-payments --project="${PROJECT_ID}" || true

gcloud container fleet memberships bindings create bind-cluster-a \
  --membership=cluster-a --location="${REGION_1}" --scope=team-payments --project="${PROJECT_ID}" || true

gcloud container fleet memberships bindings create bind-cluster-b \
  --membership=cluster-b --location="${REGION_2}" --scope=team-payments --project="${PROJECT_ID}" || true

# 3. Create the Fleet Namespace & Bind the Team Identity
echo "=== 3. Creating Fleet Namespace (ns-fleet-payments) and binding ${BRAVO_USER} ==="
# 1. Define the namespace ONCE at the Scope level
gcloud container fleet scopes namespaces create ns-fleet-payments \
  --scope=team-payments \
  --project="${PROJECT_ID}" || true

# 2. Bind the developer/group ONCE to the Scope
gcloud beta container fleet scopes add-app-operator-binding team-payments \
  --role=edit \
  --user="${BRAVO_USER}" \
  --project="${PROJECT_ID}"

echo "=== Track B setup complete! ==="
