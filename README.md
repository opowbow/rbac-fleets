# `rbac-fleets`: GKE Standard RBAC vs. Fleet Team Scopes Demo

Companion scripts for **GKE Fleet Scopes: Unifying Multi-Cluster RBAC and Logging**, comparing **Track A (Standard Per-Cluster Kubernetes RBAC)** for `ALPHA_USER` against **Track B (GKE Fleet Team Scopes & Scope Logs)** for `BRAVO_USER`.

## Repository Structure

~~~text
rbac-fleets/
├── README.md                # Overview & usage instructions
└── scripts/
    ├── setup_verify.sh      # All setup and verification steps from the blog post in a single file
    ├── setup.sh             # Setup steps from the blog post (Environment, Clusters, Track A & Track B)
    ├── demo-verify.sh       # Verification tests from the blog post (Test 1: RBAC & Test 2: Pod Logging)
    └── teardown.sh          # Cleans up demo resources (pass --delete-clusters to also delete cluster-a & cluster-b)
~~~

## Quick Start

~~~bash
# Run everything (setup + verification) from the blog post
./scripts/setup_verify.sh

# Or run setup and verification separately
./scripts/setup.sh
./scripts/demo-verify.sh

# Clean up demo resources
./scripts/teardown.sh
~~~
