# RustFS - S3-Compatible Object Storage

RustFS is a high-performance, distributed object storage system (S3-compatible) built in Rust.

## Deployment Modes

| Mode | Pods | PVCs | Use Case |
|------|------|------|----------|
| **Standalone** | 1 | 1 | Local/dev (current) |
| **Distributed** | 4 | 16 (4 per pod) | Default production |
| **Distributed** | 16 | 16 (1 per pod) | Large scale |

## Current Config (Standalone)

- **Namespace:** rustfs
- **Mode:** Standalone (1 pod, 1 PVC)
- **Service:** ClusterIP on port 9000 (API), 9001 (Console)
- **Ingress:** Disabled (no ingress controller in local Kind)
- **ingress.className:** nginx (avoids TraefikService CRD - cluster has no Traefik)

## Access

```bash
# Port-forward for local access
kubectl port-forward -n rustfs svc/rustfs 9000:9000 9001:9001

# API: http://localhost:9000
# Console: http://localhost:9001
# Default credentials: rustfsadmin / rustfsadmin
```

## Switch to Distributed Mode

Edit `helmrelease.yaml`:

```yaml
mode:
  standalone:
    enabled: false
  distributed:
    enabled: true

# Style 1: 4 pods, 4 PVCs each (default)
replicaCount: 4

# Style 2: 16 pods, 1 PVC each
replicaCount: 16
```

## StorageClass

Uses `standard` StorageClass (Kind default). If your cluster uses `local-path`, set:

```yaml
storageclass:
  name: local-path
```

Kind clusters typically have `standard` (provisioner: rancher.io/local-path).
