# MOP Helm Chart

Generic Helm chart for deploying all 9 microservices in the monitoring project (Microservices Observability Platform).

## Quick Start

### Local Chart Installation

```bash
# Manual single service deployment
helm upgrade --install auth charts/mop -f charts/mop/values/auth.yaml -n auth --create-namespace
```

### OCI Registry Installation

```bash
# Install from OCI registry
helm install auth oci://ghcr.io/duynhne/charts/mop \
  --version 0.4.2 \
  -f charts/mop/values/auth.yaml \
  -n auth --create-namespace
```

**OCI Registry**: `oci://ghcr.io/duynhne/charts/mop`

---

## Helm Template Examples

### Preview Rendered Templates

```bash
# Preview all rendered templates
helm template auth charts/mop -f charts/mop/values/auth.yaml
```

### Dry-Run Installation

```bash
# See what would be installed without actually installing
helm install auth charts/mop -f charts/mop/values/auth.yaml -n auth --dry-run --debug
```

### Validate Chart

```bash
# Lint chart for errors
helm lint charts/mop

# Validate with values file
helm lint charts/mop -f charts/mop/values/auth.yaml
```

### Template with Custom Values

```bash
# Override values inline
helm template auth charts/mop \
  --set name=auth \
  --set image.repository=ghcr.io/duynhne/auth \
  --set image.tag=v5 \
  --set replicaCount=3

```

---

## Chart Structure

```
charts/mop/
├── Chart.yaml             # Chart metadata (version: 0.4.2)
├── values.yaml            # Default values template
├── values/                # Per-service value overrides
│   ├── auth.yaml
│   ├── user.yaml
│   ├── product.yaml
│   ├── cart.yaml
│   ├── order.yaml
│   ├── review.yaml
│   ├── notification.yaml
│   ├── shipping.yaml
│   └── k6.yaml
└── templates/
    ├── _helpers.tpl       # Template helper functions
    ├── deployment.yaml    # Includes initContainer for migrations
    ├── service.yaml
    └── NOTES.txt          # Post-installation notes
```

