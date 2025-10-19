# Go REST API Monitoring Demo

**Complete monitoring solution with 25 Grafana panels** - Kubernetes-ready with Prometheus & Grafana

---

## 🎯 What You Get

### 25 Grafana Dashboard Panels

**Performance Metrics (8 panels)**
- Response time percentiles (P50, P95, P99)
- RPS (Requests Per Second)
- Total requests
- Apdex Score
- Latency trends by endpoint
- Response time heatmaps

**Traffic Analysis (6 panels)**
- Status code distribution
- Requests by endpoint
- RPS per pod
- Traffic patterns
- 🆕 **Request Rate by HTTP Method + Endpoint** - Detailed breakdown by GET/POST/PUT/DELETE
- 🆕 **Error Rate by HTTP Method + Endpoint** - Pinpoint exact failing methods

**Resource Monitoring (6 panels)**
- Memory usage (Go heap)
- CPU usage
- Network I/O
- Go routines & threads
- GC performance
- Memory allocations

**Reliability (5 panels)**
- Up instances
- Pod restarts
- Requests in flight
- Error rates

---

## 🚀 Quick Start

### Deploy (5 minutes)

```bash
git clone <repo-url>
cd project-monitoring-golang

# One command to deploy everything
./scripts/deploy-all.sh
```

### Access

```
📊 Grafana:    http://localhost:3000 (admin/admin)
📈 Prometheus: http://localhost:9090
🔧 API:        http://localhost:8080
```

### View Dashboard

Open Grafana → **"Go REST API Monitoring - Demo"** dashboard is auto-loaded!

**Direct link**: http://localhost:3000/d/go-monitoring-demo/

---

## 📊 Dashboard Highlights

### Key Metrics at a Glance

| Panel | What It Shows | Why It Matters |
|-------|--------------|----------------|
| **P99 Response Time** | 99% of requests complete within this time | Tail latency - worst user experience |
| **RPS** | Requests per second | System throughput |
| **Apdex Score** | User satisfaction (0-1 scale) | Overall performance health |
| **Error Rate** | 4xx + 5xx responses | Reliability indicator |
| **Memory Usage** | Go heap allocation | Detect memory leaks |
| **CPU Usage** | Process CPU consumption | Resource utilization |

### Health Indicators

**🟢 Healthy System:**
- P95 < 300ms, P99 < 1s
- Apdex > 0.85
- Error rate < 1%
- 0 restarts
- Stable memory

**🟡 Warning:**
- P99 > 1s
- Apdex 0.7-0.85
- Error rate 1-5%
- Memory slowly growing

**🔴 Critical:**
- P99 > 2s
- Apdex < 0.7
- Error rate > 5%
- Frequent restarts
- Memory leak

---

## 🔍 Understanding the Metrics

### Custom Application Metrics

The Go application exposes **6 custom metrics**:

1. **`request_duration_seconds`** (Histogram)
   - HTTP request latency
   - Powers P50/P95/P99 calculations
   - Buckets optimized for Apdex

2. **`requests_total`** (Counter)
   - Total HTTP requests
   - Used for RPS calculation

3. **`requests_in_flight`** (Gauge)
   - Concurrent requests
   - Detects traffic spikes

4. **`request_size_bytes`** (Histogram)
   - Incoming data volume

5. **`response_size_bytes`** (Histogram)
   - Outgoing data volume

6. **`error_rate_total`** (Counter)
   - Failed requests (4xx, 5xx)

### Go Runtime Metrics

Automatically exposed by `prometheus/client_golang`:
- `go_memstats_*` - Memory statistics
- `go_goroutines` - Goroutine count
- `go_gc_duration_seconds` - GC pause times
- `process_cpu_seconds_total` - CPU time

**📖 For detailed metrics documentation, see [docs/METRICS.md](./docs/METRICS.md)**  
**🆕 NEW: HTTP Method dimension panels - see [docs/NEW_METHOD_PANELS.md](./docs/NEW_METHOD_PANELS.md)**

---

## 🧪 Load Testing

### Automatic Testing

A Kubernetes CronJob generates traffic every 2 minutes:

```bash
kubectl get cronjob -n monitoring-demo
# demo-loadtest runs every */2 * * * *
```

### Manual Testing

```bash
# Quick test (100 requests)
for i in {1..100}; do curl http://localhost:8080/api/users & done

# Or trigger CronJob manually
kubectl create job --from=cronjob/demo-loadtest manual-test-$(date +%s) -n monitoring-demo
```

---

## 🏗️ Architecture

```
┌─────────────┐
│   Go API    │ ← HTTP Requests
│   (3 pods)  │
└──────┬──────┘
       │ :8080/metrics
       │
┌──────▼──────────┐
│   Prometheus    │ ← Scrapes metrics every 15s
│   (1 pod)       │
└──────┬──────────┘
       │
┌──────▼──────────┐
│    Grafana      │ ← Queries Prometheus
│   (1 pod)       │   Displays 23 panels
└─────────────────┘
```

**Kubernetes Components:**
- **Kind** - Local 3-node cluster (1 control-plane + 2 workers)
- **kube-state-metrics** - K8s object metrics
- **metrics-server** - Resource usage data

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| **[METRICS.md](./docs/METRICS.md)** | ⭐ **Complete guide với phân tích chi tiết tất cả 25 panels** (bao gồm HTTP Method panels, namespace support) |
| **[K6_LOAD_TESTING.md](./docs/K6_LOAD_TESTING.md)** | 🚀 **k6 continuous load generator setup & configuration** |
| **[SLO_IMPLEMENTATION.md](./slo/docs/SLO_IMPLEMENTATION.md)** | 🎯 **SRE practices: SLI/SLO definitions, error budgets, burn rate alerts** |
| **[PROMETHEUS_RATE_EXPLAINED.md](./docs/PROMETHEUS_RATE_EXPLAINED.md)** | 📊 Chi tiết về `rate()`, `increase()` và counter resets |
| **[SETUP.md](./docs/SETUP.md)** | Step-by-step deployment guide |
| **[VARIABLES_REGEX.md](./docs/VARIABLES_REGEX.md)** | 🎯 Dashboard variables & regex patterns |

---

## 🎯 SRE Practices

### SLI/SLO Implementation

This project includes comprehensive SRE practices with **Service Level Objectives (SLOs)** and **Error Budget** tracking:

**📊 SLI Definitions:**
- **Availability**: 99.5% (30d), 99.0% (7d) - Non-5xx responses
- **Latency**: 95% (30d), 90% (7d) - Requests < 500ms  
- **Error Rate**: 99% (30d), 98% (7d) - Non-4xx/5xx responses

**💰 Error Budget Policy:**
- **30-day Budget**: 0.5% of total requests
- **7-day Budget**: 1.0% of total requests
- **Burn Rate Alerts**: 15x (critical), 4x (warning), 1x (info)

**🚨 Multi-Window Alerts:**
- Critical: Budget exhausted in 2 days (15x burn rate)
- Warning: Budget exhausted in 7 days (4x burn rate)
- Info: Budget below 20%

**📈 SLO Dashboard:**
- Real-time error budget tracking
- Burn rate monitoring (1h, 6h, 3d windows)
- Time to exhaustion estimates
- SLI trend analysis

**🤖 Automated Runbooks:**
- `diagnose-latency.sh` - Latency issue analysis
- `error-budget-alert.sh` - Budget alert response
- Auto-classification of incidents by severity

**🚀 One-Command Deployment:**
```bash
./slo/scripts/deploy-slo.sh
```

**📖 Full Documentation:** [SLO_IMPLEMENTATION.md](./slo/docs/SLO_IMPLEMENTATION.md)

---

## 🛠️ Technology Stack

- **Go 1.21** - Application runtime
- **Gorilla Mux** - HTTP router
- **Prometheus** - Metrics collection
- **Grafana** - Visualization
- **Kind** - Local Kubernetes

### Dependencies

```go
github.com/gorilla/mux v1.8.1
github.com/prometheus/client_golang v1.19.0
```

---

## 🎯 Use Cases

### Demo & Presentation
- Show complete monitoring solution
- Explain observability concepts
- Demo real-time metrics

### Learning
- Understand Prometheus metrics
- Learn PromQL queries
- Practice K8s deployments

### Development
- Monitor local services
- Test performance
- Debug issues

### Production-Ready Template
- Copy & modify for real apps
- Add custom metrics
- Setup alerting

---

## 🔧 Customization

### Add Custom Metrics

1. Define metric in `pkg/middleware/prometheus.go`:
```go
var MyMetric = promauto.NewCounterVec(
    prometheus.CounterOpts{
        Name: "my_metric_total",
        Help: "My custom metric",
    },
    []string{"label"},
)
```

2. Use in code:
```go
MyMetric.WithLabelValues("value").Inc()
```

3. Add panel to `grafana-dashboard.json`

### Modify Dashboard

- Edit `grafana-dashboard.json`
- Update ConfigMap: `kubectl create configmap grafana-dashboard-json --from-file=...`
- Restart Grafana: `kubectl rollout restart deployment grafana -n monitoring-demo`

---

## 🧹 Cleanup

```bash
# Delete everything
./scripts/cleanup.sh

# Or manual
kind delete cluster --name monitoring-demo
```

---

## ❓ FAQ

**Q: Why Kind instead of Docker Compose?**
A: Kind provides real Kubernetes metrics. Docker Compose only gives 13/23 panels. Kind gives all 23!

**Q: Can I use this in production?**
A: Yes! This is a production-ready template. Add:
- TLS/ingress
- Persistent storage
- Alerting rules
- Authentication

**Q: How do I add more endpoints?**
A: Add handlers in `handlers/` directory. Metrics are auto-collected via middleware.

**Q: Dashboard shows no data?**
A: Generate traffic first! CronJob runs every 2 minutes automatically, or trigger manually with `kubectl create job --from=cronjob/demo-loadtest test-now -n monitoring-demo`

**Q: What's Apdex Score?**
A: Application Performance Index. 0-1 scale measuring user satisfaction based on response times.

---

## 🤝 Contributing

Contributions welcome! Areas to improve:
- Add more metrics
- New dashboard panels
- Additional endpoints
- Documentation

---

## 📝 License

MIT License - Use freely!

---

## 🌟 Star This Repo!

If this helps you understand monitoring, please ⭐ star the repository!

---

**Built with ❤️ for learning observability**

🚀 **Happy Monitoring!**


kubectl port-forward -n monitoring-demo svc/grafana 3000:3000
