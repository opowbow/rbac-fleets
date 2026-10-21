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

# a. Deploy Application and wait for running pods
# a1. Deploy Application
gcloud container fleet memberships get-credentials cluster-a --location="${REGION_1}" --project="${PROJECT_ID}"

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


# a2. Wait for runing pods
for NS in ns-standard-checkout ns-fleet-payments; do 
  echo "Checking status of payment-worker pods in namespace ${NS}..." 
  until kubectl get pods -n "${NS}" -l app=payment-worker 2>/dev/null | grep -qE 'Running|Error|CrashLoopBackOff'; do 
    sleep 3 
  done 
  echo "Status confirmed for namespace ${NS}." 
done 
echo "All pod checks completed."

# b. Wait for logs to be flushed to Cloud Logging
# b1. Set pod vars
ALPHA_POD=$(kubectl get pods -n ns-standard-checkout -l app=payment-worker -o jsonpath='{.items[0].metadata.name}')
BRAVO_POD=$(kubectl get pods -n ns-fleet-payments -l app=payment-worker -o jsonpath='{.items[0].metadata.name}')

# b2. Check logs are written to cloud logging
until [ -n "$(gcloud logging read 'resource.type="k8s_container" AND resource.labels.namespace_name="ns-standard-checkout" AND textPayload:"FATAL: Checkout DB timeout code=5004"' --project="${PROJECT_ID}" --limit=1 --format='value(textPayload)' 2>/dev/null)" ]; do 
  echo "Waiting for fluentbit-gke flush to Cloud Logging..." 
  sleep 10 
done 
echo "Logs flushed and detected in Cloud Logging!"

# b3. Delete the deployments
kubectl delete deployment payment-worker -n ns-standard-checkout
kubectl delete deployment payment-worker -n ns-fleet-payments


# check1 - Both Alpha and Bravo users try kubectl logs → Fails (logs NotFound):

kubectl logs "${ALPHA_POD}" -n ns-standard-checkout --as="${ALPHA_USER}"
kubectl logs "${BRAVO_POD}" -n ns-fleet-payments --as="${BRAVO_USER}"


# check2 - Track A (ALPHA_USER) queries Cloud Logging (_Default bucket) -> Fails (PERMISSION_DENIED):

gcloud logging read \
  'resource.type="k8s_container" AND resource.labels.namespace_name="ns-standard-checkout" AND textPayload:"FATAL: Checkout DB timeout code=5004"' \
  --bucket="_Default" --location=global --view="_Default" \
  --project="${PROJECT_ID}" \
  --account="${ALPHA_USER}" \
  --limit=3
# Output: ERROR: (gcloud.logging.read) PERMISSION_DENIED: The caller does not have permission

# Check3 - Track B (BRAVO_USER) queries the Fleet Scope Log View → Succeeds!

gcloud logging read \
  'resource.type="k8s_container" AND resource.labels.namespace_name="ns-fleet-payments" AND textPayload:"FATAL: Checkout DB timeout code=5004"' \
  --bucket="fleet-o11y-scope-team-payments" \
  --location=global \
  --view="fleet-o11y-scope-team-payments-k8s_container" \
  --project="${PROJECT_ID}" \
  --account="${BRAVO_USER}" \
  --limit=5 \
  --format="table(timestamp, severity, resource.labels.pod_name, textPayload)"
