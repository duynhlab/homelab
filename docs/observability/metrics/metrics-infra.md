# Infrastructure Metrics (USE)

The **infrastructure layer** of the metrics pillar: the health and resource
behaviour of the cluster itself — pods, nodes, workloads, network, and the API
server — measured with the **USE method** (Utilization, Saturation, Errors). For
methodology theory, the stack, and the other layers, start at the
[metrics hub](README.md).

| | |
|---|---|
| **Source** | kube-state-metrics, the `up` synthetic metric, control-plane endpoints |
| **Method** | USE — Utilization, Saturation, Errors per resource |
| **Scope** | Pods, nodes, PVC/disk, network, workloads, API server |
| **Rules** | USE alerts + recording rules in VMAlert (see [§ Manifest index](#manifest-index)) |
| **Environment note** | Some control-plane components are scoped out on Kind (see [§ Not covered](#not-covered-scoped-out-for-kind)) |

---

## Overview

Infrastructure is resource-driven, so it is measured with **USE** rather than
RED: for each resource, *how much is in use* (Utilization), *how much demand is
queued/contended* (Saturation), and *what is failing* (Errors). These roll up
into the Four Golden Signals alongside the application RED metrics. Most series
come from **kube-state-metrics** (object state) and the **`up`** metric VMAgent
synthesizes per scrape target.

## Kubernetes metrics

| Metric | Type | Labels | Purpose |
|--------|------|--------|---------|
| `up` | Gauge | `job`, `app`, `namespace`, `instance` | Target reachability — `1` up / `0` down; `count()` for healthy instances |
| `kube_pod_container_status_restarts_total` | Counter | `namespace`, `pod`, `container` | Container restarts — frequent restarts ⇒ OOM/crash |

kube-state-metrics additionally exposes object-level series (pod phase, node
conditions, PVC capacity, HPA status, job state, deployment replicas) consumed by
the USE alerts below.

## USE method coverage

| Resource | Utilization | Saturation | Errors |
|----------|:-----------:|:----------:|:------:|
| **Pod CPU** | ✅ throttling % | ✅ CFS periods | ✅ OOMKill |
| **Pod Memory** | ✅ near-limit % | ✅ working set vs limit | ✅ OOMKill |
| **Node** | ✅ KSM conditions | ✅ pressure flags | ✅ NotReady |
| **PVC / Disk** | ✅ available/capacity | ✅ filling up | ✅ < 5% critical |
| **Network** | ✅ RX/TX recording rules | — | ✅ error rate |
| **K8s Workloads** | ✅ replica status | ✅ HPA maxed | ✅ job failures, mismatch |
| **API Server** | ✅ CPU, memory | ✅ inflight requests | ✅ 5xx rate |
| **PostgreSQL** | ✅ connections, TPS, cache hit | ✅ connection saturation, locks | ✅ replication lag, offline |
| **Valkey / Redis** | ✅ memory ratio | ✅ evictions, connections | ✅ down, rejected |

> The backing alert/recording rules per resource (exact files + counts) are in
> the [Alert Catalog](../alerting/alert-catalog.md) — see [§ Manifest
> index](#manifest-index). Request-driven microservices use **RED**, not USE
> (see [metrics-apps.md](metrics-apps.md)); database and cache USE detail lives in
> the [databases layer](postgresql/monitoring.md).

### Not covered (scoped out for Kind)

| Resource | Reason |
|----------|--------|
| **etcd** | Metrics endpoint not accessible in Kind without host networking |
| **scheduler / controller-manager** | Not exposed via Services in Kind |
| **Ingress controller** | No ingress controller deployed |
| **node_exporter** | Kind nodes are Docker containers; KSM conditions used instead |

These are tracked for a production cluster: node_exporter (real node CPU/mem/disk
I/O), etcd (leader elections, proposal latency, DB size), ingress controller
metrics, scheduler/controller-manager, and CoreDNS (DNS latency, NXDOMAIN).
(The kubelet **is** already scraped here via `VMNodeScrape` — cAdvisor container
metrics plus volume-stats gauges; and cert-manager expiry alerts **are** deployed
— see the [Alert Catalog](../alerting/alert-catalog.md).)

## Go process vs container (cAdvisor) metrics

The microservices dashboard's memory/CPU panels show **Go process** metrics
(from the Go runtime), **not** Kubernetes container metrics. For container-level
figures (full RSS, CPU vs limits, network, disk I/O), cAdvisor in the kubelet is
the source.

| Aspect | Go process metrics | Container metrics (cAdvisor) |
|--------|-------------------|------------------------------|
| **Source** | Go runtime (`runtime.MemStats`) | cAdvisor in kubelet |
| **Scope** | Go process only | Whole container (app + OS) |
| **Memory** | Heap allocated | Container RSS, cache, buffers |
| **CPU** | Go process CPU time | Container CPU vs limits |
| **Network / Disk I/O** | Not available | TX/RX, read/write bytes |

The "Total Network Traffic per Service" panel therefore measures HTTP body size
only (via `http_server_request_body_size_bytes` / `http_server_response_body_size_bytes`), missing TCP/HTTP
headers, TLS overhead, and health-check traffic.

## Manifest index

Infrastructure alert and recording rules are owned by the alerting docs — the
authoritative, per-domain index (exact files under
`prometheusrules/kubernetes/` and `prometheusrules/valkey/`, with counts and
production impact) is the [Alert Catalog](../alerting/alert-catalog.md):

- [Kubernetes](../alerting/alert-catalog.md#6-kubernetes) — nodes, workloads, pods, API server, control plane, network
- [Valkey cache](../alerting/alert-catalog.md#3-valkey-cache)

Database manifests are indexed in the
[databases layer](postgresql/monitoring.md); application RED manifests in
[metrics-apps.md](metrics-apps.md#manifest-index). Runbook:
[`infrastructure-alerts.md`](../runbooks/infrastructure-alerts.md).

## References

- [Metrics hub](README.md) · [Application metrics (RED)](metrics-apps.md) · [Database metrics](postgresql/monitoring.md)
- [VictoriaMetrics Operator Stack](victoriametrics.md) · [PromQL Guide](promql-guide.md)
- [SLO Documentation](../slo/README.md) · [Grafana Dashboard Guide](../grafana/dashboard-reference.md)

---

_Last updated: 2026-07-09 — USE coverage via kube-state-metrics; control-plane components scoped out on Kind; HTTP body-size metrics renamed to semconv (RFC-0014 P3)._
