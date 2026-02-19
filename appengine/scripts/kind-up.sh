#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-uim-local}"
IMAGE="${IMAGE:-localhost/uim-appengine-service:0.1.0}"
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

echo "[2/5] Building Podman image: $IMAGE"
podman build -t "$IMAGE" .

echo "[3/5] Ensuring kind cluster exists: $CLUSTER_NAME"
if ! kind get clusters | grep -Fxq "$CLUSTER_NAME"; then
  kind create cluster --name "$CLUSTER_NAME" --config kind-config.yaml
fi

echo "[4/5] Loading image into kind"
kind load docker-image "$IMAGE" --name "$CLUSTER_NAME"

echo "[5/5] Applying Kubernetes manifests"
kubectl apply -f k8s/deployment.yaml -f k8s/service.yaml -f k8s/ingress.yaml
kubectl rollout status deployment/uim-appengine-service --timeout=120s

echo
echo "Cluster ready. Test with:"
echo "  kubectl port-forward svc/uim-appengine-service 8080:80"
echo "  curl http://127.0.0.1:8080/healthz"
echo
echo "Optional ingress host entry:"
echo "  127.0.0.1 uim-appengine.local"
