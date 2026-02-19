#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-uim-loadbalancing-local}"
IMAGE="${IMAGE:-localhost/uim-loadbalancing-service:0.1.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require kind
require kubectl
require podman
require dub

cd "$ROOT_DIR"

echo "[1/5] Building D binary"
dub build -b release

echo "[2/5] Building image $IMAGE"
podman build -t "$IMAGE" .

echo "[3/5] Ensuring kind cluster $CLUSTER_NAME"
if ! kind get clusters | grep -Fxq "$CLUSTER_NAME"; then
  kind create cluster --name "$CLUSTER_NAME" --config kind-config.yaml
fi

echo "[4/5] Loading image into kind"
kind load docker-image "$IMAGE" --name "$CLUSTER_NAME"

echo "[5/5] Deploying manifests"
kubectl apply -f k8s/deployment.yaml -f k8s/service.yaml -f k8s/ingress.yaml -f k8s/hpa.yaml
kubectl rollout status deployment/uim-loadbalancing-service --timeout=120s

echo "Ready. Test with:"
echo "  kubectl port-forward svc/uim-loadbalancing-service 8080:80"
echo "  curl -s http://127.0.0.1:8080/healthz"
