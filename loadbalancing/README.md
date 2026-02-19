# uim-loadbalancing-service

Cloud Load Balancing-like service in D using `vibe.d` + `uim-framework`, packaged for Podman and Kubernetes.

## API

- `GET /` service info and backend counts
- `GET /healthz` liveness
- `GET /readyz` readiness (ready when at least one healthy backend exists)
- `POST /v1/backends` register backend via key-value body
- `GET /v1/backends` list registered backends
- `POST /v1/backends/<backendId>/health` set backend health via key-value body
- `GET /v1/next` select next backend (weighted round-robin among healthy backends)
- `POST /v1/simulate` run request distribution simulation

## Backend registration payload

Body is key-value lines:

```text
url=http://backend-a:8080
weight=2
healthy=true
```

Health update payload:

```text
healthy=false
```

Simulation payload:

```text
requests=200
```

## Local run

```bash
dub build -b release
./uim-loadbalancing-service
```

Quick test:

```bash
curl -s -X POST http://127.0.0.1:8080/v1/backends --data-binary $'url=http://svc-a:8080\nweight=3\nhealthy=true'
curl -s -X POST http://127.0.0.1:8080/v1/backends --data-binary $'url=http://svc-b:8080\nweight=1\nhealthy=true'
curl -s http://127.0.0.1:8080/v1/next
curl -s -X POST http://127.0.0.1:8080/v1/simulate --data-binary 'requests=100'
```

## Podman image

```bash
dub build -b release
podman build -t localhost/uim-loadbalancing-service:0.1.0 .
podman run --rm -p 8080:8080 -e PORT=8080 localhost/uim-loadbalancing-service:0.1.0
```

## Kubernetes deploy

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/hpa.yaml
```

## Local kind workflow

```bash
./scripts/kind-up.sh
./scripts/kind-down.sh
```
