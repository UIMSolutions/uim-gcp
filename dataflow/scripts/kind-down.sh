#!/usr/bin/env bash
set -euo pipefail

# Environment options:
#   CLUSTER_NAME (default: uim-dataflow-local)
#   KIND_EXPERIMENTAL_PROVIDER (default: podman)
#   WORKER_COUNT (ignored by kind-down; used only by kind-up)

CLUSTER_NAME="${CLUSTER_NAME:-uim-dataflow-local}"
export KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"
WORKER_COUNT="${WORKER_COUNT:-2}"

echo "Deleting cluster: $CLUSTER_NAME"
echo "WORKER_COUNT=$WORKER_COUNT (ignored by kind-down)"

kind delete cluster --name "$CLUSTER_NAME"
