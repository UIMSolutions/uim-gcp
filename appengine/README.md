# uim-appengine-service

D language service using `vibe.d` and `uim-framework`, packaged for container execution with Podman and deployment to Kubernetes.

## Endpoints

- `GET /` service metadata
- `GET /healthz` liveness
- `GET /readyz` readiness

## Local build (DUB)

```bash
dub build -b release
./uim-appengine-service
```

The service listens on `PORT` (default `8080`).

## Build image with Podman

Build the binary first so `Dockerfile` can copy `./uim-appengine-service` into the image.

```bash
dub build -b release
podman build -t localhost/uim-appengine-service:0.1.0 .
```

## Run container with Podman

```bash
podman run --rm -p 8080:8080 -e PORT=8080 localhost/uim-appengine-service:0.1.0
```

## Deploy to Kubernetes

1. Ensure your cluster can pull local images (for example with kind):

```bash
kind load docker-image localhost/uim-appengine-service:0.1.0
```

2. Apply manifests:

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
```

3. Verify:

```bash
kubectl get pods,svc,ingress
kubectl port-forward svc/uim-appengine-service 8080:80
curl http://127.0.0.1:8080/healthz
```

## Local Kind workflow (Podman + Kubernetes)

This repository includes scripts for local end-to-end deployment with Kind using Podman as provider.

```bash
./scripts/kind-up.sh
```

This script will:

- build the D binary with `dub`
- build the container image with `podman`
- create Kind cluster `uim-local` (if missing)
- load image into the cluster
- apply `k8s/*.yaml` manifests

Optional environment variables:

```bash
CLUSTER_NAME=my-cluster IMAGE=localhost/uim-appengine-service:0.1.0 ./scripts/kind-up.sh
```

Delete cluster:

```bash
./scripts/kind-down.sh
```

## App Engine-style descriptor

`app.yaml` is included with `runtime: custom` so the same codebase can be aligned with an App Engine style service definition.
