# `rbac-fleets`: GKE Standard RBAC vs. Fleet Team Scopes Demo

A hands-on Google Cloud / GKE demo environment comparing **Standard Per-Cluster Kubernetes RBAC** (`Track A`) against **GKE Fleet Team Management (`Scopes` & `Fleet Namespaces`)** (`Track B`) across two multi-region GKE Autopilot clusters (`cluster-a` in `europe-west1` and `cluster-b` in `us-central1`).

## Repository Structure

~~~text
rbac-fleets/
├── README.md                # Overview & quickstart instructions
└── scripts/
    ├── setup.sh             # Provisions Track A (Standard K8s RBAC) & Track B (Fleet Scope + Scope Logs)
    ├── demo-verify.sh       # Verifies multi-cluster RBAC actuation & isolated Fleet Scope Logs
    └── teardown.sh          # Surgical cleanup of demo resources (leaves existing clusters intact by default)
~~~

## What Each Script Does

* **`scripts/setup.sh`**
  * Enables required GKE, Fleet (`gkehub`), Connect Gateway, and Cloud Logging APIs.
  * Creates (or reuses existing) `cluster-a` (`europe-west1`) and `cluster-b` (`us-central1`) and registers them to the Fleet.
  * **Track A (`ns-standard-checkout`):** Applies a standard Kubernetes `Namespace` and `RoleBinding` (`ClusterRole/edit`) per cluster.
  * **Track B (`team-payments` / `ns-fleet-payments`):** Creates a single Fleet Team Scope (`team-payments`), binds both clusters, creates the Fleet Namespace `ns-fleet-payments`, binds the operator identity via `add-app-operator-binding`, and configures the isolated `fleet-o11y-scope-team-payments` Cloud Logging bucket, views, and Log Router sink.
* **`scripts/demo-verify.sh`**
  * **Moment 1:** Connects to both clusters via Fleet memberships and verifies that `ns-fleet-payments` and the `fleet-rrb-actuation-*` `RoleBinding` were reconciled automatically.
  * **Moment 2:** Emits a simulated crashed-pod error log (`FATAL: Checkout DB timeout code=5004`) for `ns-fleet-payments` and queries it back from the isolated `fleet-o11y-scope-team-payments-k8s_container` Log View.
* **`scripts/teardown.sh`**
  * Safely removes **only** the demo resources (`RBACRoleBindings`, Fleet Namespace `ns-fleet-payments`, cluster membership bindings, `team-payments` Scope, `fleet-o11y-*` sink/bucket, and `ns-standard-checkout`) while leaving `cluster-a`, `cluster-b`, and the GCP project intact.
  * Optional flags: `--delete-clusters` (also deletes `cluster-a` and `cluster-b`) or `--delete-project`.

## Quick Start

~~~bash
export PROJECT_ID="op-hack-001"
export DEV_SUBJECT="admin@powerm-1.altostrat.com"

# 1. Provision Track A & Track B demo environment
./scripts/setup.sh

# 2. Run verification checks
./scripts/demo-verify.sh

# 3. Tear down demo resources (keeps clusters intact)
./scripts/teardown.sh
~~~
