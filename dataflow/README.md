# uim-dataflow-service

Dataflow-like service in D using `vibe.d` + `uim-framework`, designed for Podman containers and Kubernetes.

## API

- `GET /` service info
- `GET /healthz` liveness
- `GET /readyz` readiness
- `POST /v1/jobs` submit a text processing job (request body = input text)
- `GET /v1/jobs` list jobs
- `GET /v1/jobs/<jobId>` get job status/result

Jobs are processed asynchronously by a background worker, so status transitions are `queued` -> `running` -> `done` (or `failed`).

Parallelism is controlled by `WORKER_COUNT` (default: `2`).

## Local run

```bash
dub build -b release
WORKER_COUNT=4 ./uim-dataflow-service
```

Submit a job:

```bash
curl -s -X POST http://127.0.0.1:8080/v1/jobs \
  -H "Content-Type: text/plain" \
  --data-binary $'hello world\nthis is a pipeline'
```

Check job status:

```bash
curl -s http://127.0.0.1:8080/v1/jobs/<jobId>
```

## Podman image

```bash
dub build -b release
podman build -t localhost/uim-dataflow-service:0.1.0 .
podman run --rm -p 8080:8080 -e PORT=8080 localhost/uim-dataflow-service:0.1.0
```

## Kubernetes deploy

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/hpa.yaml
```

Verify:

```bash
kubectl get pods,svc,ingress,hpa
kubectl port-forward svc/uim-dataflow-service 8080:80
curl -s http://127.0.0.1:8080/healthz
```

## Local kind workflow

```bash
./scripts/kind-up.sh
./scripts/kind-down.sh
```

Override worker parallelism during deploy:

```bash
WORKER_COUNT=6 ./scripts/kind-up.sh
```

The up script builds binary + image, creates a kind cluster (Podman provider), loads image, and applies deployment/service/ingress/HPA manifests.
