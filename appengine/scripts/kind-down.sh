#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-uim-local}"
export KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"

if ! command -v kind >/dev/null 2>&1; then
  echo "Missing required command: kind" >&2
  exit 1
fi

kind delete cluster --name "$CLUSTER_NAME"
