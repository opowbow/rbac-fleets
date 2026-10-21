# `rbac-fleets`: GKE Standard RBAC vs. Fleet Team Scopes Demo

Companion scripts for **GKE Fleet Scopes: Unifying Multi-Cluster RBAC and Logging**, comparing **Track A (Standard Per-Cluster Kubernetes RBAC)** for `ALPHA_USER` against **Track B (GKE Fleet Team Scopes & Scope Logs)** for `BRAVO_USER`.

## Repository Structure

~~~text
rbac-fleets/
├── README.md                # Overview & usage instructions
└── scripts/
    ├── setup.sh             # Setup steps from the blog post (Environment, Clusters, Track A & Track B)
    ├── demo_verify.sh       # Complete setup and verification steps from the blog post
    └── teardown.sh          # Cleans up demo resources (pass --delete-clusters to also delete cluster-a & cluster-b)
~~~

## Quick Start

~~~bash
# Run setup
./scripts/setup.sh

# Run setup and verification steps
./scripts/demo_verify.sh

# Clean up demo resources
./scripts/teardown.sh
~~~
