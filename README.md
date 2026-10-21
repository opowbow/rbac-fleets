# `rbac-fleets`: GKE Standard RBAC vs. Fleet Team Scopes Demo

Companion scripts for the walkthrough **GKE Fleet Scopes: Unifying Multi-Cluster RBAC and Logging**, comparing:

* **Track A — Traditional Per-Cluster Kubernetes RBAC:** Per-cluster `Namespace` (`ns-standard-checkout`) and `RoleBinding` (`standard-checkout-edit`) applied cluster-by-cluster for developer `ALPHA_USER`.
* **Track B — Central GKE Fleet Team Scope:** Single Fleet Team Scope (`team-payments`), Fleet Namespace (`ns-fleet-payments`), `add-app-operator-binding`, and isolated Fleet Scope Logs (`fleet-o11y-scope-team-payments`) for developer `BRAVO_USER`.

## Repository Structure

~~~text
rbac-fleets/
├── README.md                           # Overview & usage instructions
└── scripts/
    ├── 00-env.sh                       # Shared environment variables (PROJECT_ID, ALPHA_USER, BRAVO_USER, regions)
    ├── 01-setup-clusters.sh            # Enables APIs, sets node SA IAM role, provisions cluster-a & cluster-b with --enable-fleet
    ├── 02-setup-track-a-rbac.sh        # Track A: Grants clusterViewer & applies ns-standard-checkout RoleBinding per cluster
    ├── 03-setup-track-b-fleet.sh       # Track B: Enables Fleet Observability (COPY), creates team-payments Scope, ns-fleet-payments & Bravo binding
    ├── 04-test-rbac.sh                 # Test 1: Verifies multi-cluster namespace actuation & kubectl auth can-i (Alpha vs. Bravo)
    ├── 05-test-logging.sh              # Test 2: Deploys crashing payment-worker, deletes after log flush, tests Cloud Logging isolation
    ├── setup.sh                        # Master setup wrapper (runs 01, 02, and 03 in sequence)
    ├── demo-verify.sh                  # Master verification wrapper (runs 04-test-rbac.sh and 05-test-logging.sh)
    └── teardown.sh                     # Cleans up demo resources (pass --delete-clusters to also delete cluster-a & cluster-b)
~~~

## Quick Start

### Option 1: Run Step-by-Step (Following the Blog Walkthrough)

~~~bash
# 0. Load environment variables (override ALPHA_USER / BRAVO_USER if desired)
source ./scripts/00-env.sh

# 1. Enable APIs, node SA logging role, and create cluster-a (europe-west1) & cluster-b (us-central1)
./scripts/01-setup-clusters.sh

# 2. Set up Track A (Standard per-cluster Kubernetes RBAC for ALPHA_USER)
./scripts/02-setup-track-a-rbac.sh

# 3. Set up Track B (GKE Fleet Team Scope, Fleet Namespace & Scope Logs for BRAVO_USER)
./scripts/03-setup-track-b-fleet.sh

# 4. Run Test 1: Verify multi-cluster RBAC & automatic namespace reconciliation
./scripts/04-test-rbac.sh

# 5. Run Test 2: Crashed pod post-mortem logging (Alpha vs. Bravo)
./scripts/05-test-logging.sh
~~~

### Option 2: Run All-in-One Wrapper Scripts

~~~bash
# Run all setup steps (01, 02, 03)
./scripts/setup.sh

# Run both verification tests (Test 1 & Test 2)
./scripts/demo-verify.sh

# Clean up demo resources (or pass --delete-clusters to also remove cluster-a & cluster-b)
./scripts/teardown.sh
~~~
