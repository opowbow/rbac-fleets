#!/usr/bin/env bash
# ==============================================================================
# 05-test-logging.sh — Test 2: Crashed Pod Logging (Alpha vs. Bravo)
# Matches Blog Section: "Test 2: Pod Logging (Alpha vs. Bravo)"
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

gcloud container fleet memberships get-credentials cluster-a --location="${REGION_1}" --project="${PROJECT_ID}"

# 1. Deploy failing payment-worker into both Track A and Track B namespaces
echo "=== 1. Deploying failing payment-worker into ns-standard-checkout and ns-fleet-payments ==="
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
echo "=== 2. Waiting for payment-worker pods to run ==="
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
echo "ALPHA_POD=${ALPHA_POD}"
echo "BRAVO_POD=${BRAVO_POD}"

# 4. Check logs are written to cloud logging
echo "=== 4. Waiting for fluentbit-gke flush to Cloud Logging ==="
until [ -n "$(gcloud logging read 'resource.type="k8s_container" AND resource.labels.namespace_name="ns-standard-checkout" AND textPayload:"FATAL: Checkout DB timeout code=5004"' --project="${PROJECT_ID}" --limit=1 --format='value(textPayload)' 2>/dev/null)" ]; do
  echo "Waiting for fluentbit-gke flush to Cloud Logging..."
  sleep 10
done
echo "Logs flushed and detected in Cloud Logging!"

# 5. Delete both Deployments so the pods no longer exist in the Kubernetes API
echo "=== 5. Deleting both Deployments so the pods no longer exist in the Kubernetes API ==="
kubectl delete deployment payment-worker -n ns-standard-checkout
kubectl delete deployment payment-worker -n ns-fleet-payments

echo ""
echo "=== 6a. Both Alpha and Bravo try kubectl logs (Expected: NotFound) ==="
kubectl logs "${ALPHA_POD}" -n ns-standard-checkout --as="${ALPHA_USER}" || true
kubectl logs "${BRAVO_POD}" -n ns-fleet-payments --as="${BRAVO_USER}" || true

echo ""
echo "=== 6b. Track A (ALPHA_USER) queries Cloud Logging _Default bucket (Expected: PERMISSION_DENIED) ==="
gcloud logging read \
  'resource.type="k8s_container" AND resource.labels.namespace_name="ns-standard-checkout" AND textPayload:"FATAL: Checkout DB timeout code=5004"' \
  --bucket="_Default" --location=global --view="_Default" \
  --project="${PROJECT_ID}" \
  --account="${ALPHA_USER}" \
  --limit=3 || true

echo ""
echo "=== 6c. Track B (BRAVO_USER) queries isolated Fleet Scope Log View (Expected: SUCCESS) ==="
gcloud logging read \
  'resource.type="k8s_container" AND resource.labels.namespace_name="ns-fleet-payments" AND textPayload:"FATAL: Checkout DB timeout code=5004"' \
  --bucket="fleet-o11y-scope-team-payments" \
  --location=global \
  --view="fleet-o11y-scope-team-payments-k8s_container" \
  --project="${PROJECT_ID}" \
  --account="${BRAVO_USER}" \
  --limit=5 \
  --format="table(timestamp, severity, resource.labels.pod_name, textPayload)"
