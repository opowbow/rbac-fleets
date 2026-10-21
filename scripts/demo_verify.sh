#!/usr/bin/env bash
# ==============================================================================
# demo_verify.sh — Complete Setup & Verification Steps from the Blog Post
# ==============================================================================

# ------------------------------------------------------------------------------
# Setting Up the Multi-Cluster Environment
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# A. Standard Per-Cluster Kubernetes RBAC Approach
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# Track B. GKE Fleet Team Scopes
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# Test 1: Verify automatic multi-cluster namespace & RBAC setup (Alpha vs. Bravo)
# ------------------------------------------------------------------------------
for CLUSTER_SPEC in "cluster-a:${REGION_1}" "cluster-b:${REGION_2}"; do
  CLUSTER="${CLUSTER_SPEC%%:*}"
  REGION="${CLUSTER_SPEC##*:}"
  echo ">>> Checking ${CLUSTER} (${REGION}) <<<"
  gcloud container fleet memberships get-credentials "${CLUSTER}" --location="${REGION}" --project="${PROJECT_ID}"
  kubectl get ns ns-fleet-payments
  kubectl get rolebinding -n ns-fleet-payments
  echo -n "Alpha in ns-standard-checkout (Expected: yes): "
  kubectl auth can-i create deployments -n ns-standard-checkout --as="${ALPHA_USER}"
  echo -n "Alpha in ns-fleet-payments    (Expected: no):  "
  kubectl auth can-i get pods -n ns-fleet-payments --as="${ALPHA_USER}" || true
  echo -n "Bravo in ns-fleet-payments    (Expected: yes): "
  kubectl auth can-i create deployments -n ns-fleet-payments --as="${BRAVO_USER}"
  echo -n "Bravo in ns-standard-checkout (Expected: no):  "
  kubectl auth can-i get pods -n ns-standard-checkout --as="${BRAVO_USER}" || true
done

# ------------------------------------------------------------------------------
# Test 2: Pod Logging (Alpha vs. Bravo)
# ------------------------------------------------------------------------------
gcloud container fleet memberships get-credentials cluster-a --location="${REGION_1}" --project="${PROJECT_ID}"
# 1. Deploy failing payment-worker into both Track A and Track B namespaces
for NS in ns-standard-checkout ns-fleet-payments; do
  kubectl apply -n "${NS}" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-worker
  labels:
    app: payment-worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-worker
  template:
    metadata:
      labels:
        app: payment-worker
    spec:
      containers:
        - name: payment-worker
          image: mirror.gcr.io/library/busybox:1.36
          command: ["/bin/sh", "-c"]
          args:
            - |
              for i in 1 2 3 4; do
                echo "FATAL: Checkout DB timeout code=5004 (crashed pod crash-demo)" >&2
                sleep 5
              done
              exit 1
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
EOF
done
# 2. Wait for pods to run and fluentbit-gke to flush container logs to Cloud Logging
for NS in ns-standard-checkout ns-fleet-payments; do 
  echo "Checking status of payment-worker pods in namespace ${NS}..." 
  until kubectl get pods -n "${NS}" -l app=payment-worker 2>/dev/null | grep -qE 'Running|Error|CrashLoopBackOff'; do 
    sleep 3 
  done 
  echo "Status confirmed for namespace ${NS}." 
done 
echo "All pod checks completed."

# 3. Setup env variables for running pods
ALPHA_POD=$(kubectl get pods -n ns-standard-checkout -l app=payment-worker -o jsonpath='{.items[0].metadata.name}')
BRAVO_POD=$(kubectl get pods -n ns-fleet-payments -l app=payment-worker -o jsonpath='{.items[0].metadata.name}')
# 4. Check logs are written to cloud logging
until [ -n "$(gcloud logging read 'resource.type="k8s_container" AND resource.labels.namespace_name="ns-standard-checkout" AND textPayload:"FATAL: Checkout DB timeout code=5004"' --project="${PROJECT_ID}" --limit=1 --format='value(textPayload)' 2>/dev/null)" ]; do 
  echo "Waiting for fluentbit-gke flush to Cloud Logging..." 
  sleep 10 
done 
echo "Logs flushed and detected in Cloud Logging!"

# 5. Delete both Deployments so the pods no longer exist in the Kubernetes API
kubectl delete deployment payment-worker -n ns-standard-checkout
kubectl delete deployment payment-worker -n ns-fleet-payments

# 1. Both Alpha and Bravo users try kubectl logs -> Fails (logs NotFound):
kubectl logs "${ALPHA_POD}" -n ns-standard-checkout --as="${ALPHA_USER}"
kubectl logs "${BRAVO_POD}" -n ns-fleet-payments --as="${BRAVO_USER}"

# 2. Track A (ALPHA_USER) queries Cloud Logging (_Default bucket) -> Fails (PERMISSION_DENIED):
gcloud logging read \
  'resource.type="k8s_container" AND resource.labels.namespace_name="ns-standard-checkout" AND textPayload:"FATAL: Checkout DB timeout code=5004"' \
  --bucket="_Default" --location=global --view="_Default" \
  --project="${PROJECT_ID}" \
  --account="${ALPHA_USER}" \
  --limit=3
# Output: ERROR: (gcloud.logging.read) PERMISSION_DENIED: The caller does not have permission

# 3. Track B (BRAVO_USER) queries the Fleet Scope Log View -> Succeeds!
gcloud logging read \
  'resource.type="k8s_container" AND resource.labels.namespace_name="ns-fleet-payments" AND textPayload:"FATAL: Checkout DB timeout code=5004"' \
  --bucket="fleet-o11y-scope-team-payments" \
  --location=global \
  --view="fleet-o11y-scope-team-payments-k8s_container" \
  --project="${PROJECT_ID}" \
  --account="${BRAVO_USER}" \
  --limit=5 \
  --format="table(timestamp, severity, resource.labels.pod_name, textPayload)"
