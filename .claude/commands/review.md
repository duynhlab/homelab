# /review Command

## Purpose
Review code, configs, or dashboard changes

## Instructions
1. Check for consistency with existing patterns
2. Verify Prometheus query syntax and performance
3. Ensure panel descriptions are present and clear
4. Validate Kubernetes manifest syntax
5. Check for hardcoded values (should use variables)
6. Verify aggregation strategies (by app vs by pod)
7. Verify namespace structure matches current conventions

## Review Checklist

### Dashboard Review
- [ ] Panel descriptions present and concise
- [ ] Legend configured (table mode, Mean/Max, sorted by Max desc)
- [ ] Color thresholds appropriate (Green/Yellow/Red)
- [ ] Units correct (bytes, short, reqps, percent, ms)
- [ ] GridPos layout logical and not overlapping
- [ ] Template variables used (`$rate`, `$namespace`, `$app`)
- [ ] Dashboard UID: `microservices-monitoring-001`

### Prometheus Query Review
- [ ] `rate()` used for counters with `$rate` variable
- [ ] `job=~"microservices"` filter present in all queries
- [ ] Aggregation strategy appropriate (`sum(...) by (app)` for overview)
- [ ] Namespace filtering: `{namespace=~"$namespace"}`
- [ ] App filtering: `{app=~"$app"}`
- [ ] Histogram quantiles: `histogram_quantile(0.95, sum(rate(...)) by (le))`
- [ ] No hardcoded time windows (use `$rate`)
- [ ] No hardcoded namespace values

### Kubernetes Manifest Review
- [ ] Namespace: Service-specific (`auth`, `user`, `product`, etc.) or `monitoring` for monitoring components
- [ ] Labels: `app`, `component` (version label removed)
- [ ] Resource limits appropriate (memory: 64Mi-128Mi for services, larger for monitoring)
- [ ] ConfigMap naming: `{component}-{type}`
- [ ] Service naming matches deployment
- [ ] Deployment strategy: RollingUpdate
- [ ] Service selector matches pod labels

### Code Review
- [ ] Go code follows conventions
- [ ] Custom metrics use `prometheus/client_golang`
- [ ] Metric naming: `{domain}_{metric}_{unit}`
- [ ] Labels: app, namespace, method, path, code
- [ ] Histogram buckets optimized for Apdex
- [ ] Middleware centralized in `pkg/middleware/prometheus.go`

### SLO Review
- [ ] SLI definitions clear and measurable
- [ ] SLO targets realistic (99.9% availability, P95 < 500ms)
- [ ] Error budget: 30-day rolling window
- [ ] Burn rate windows: 1h (critical), 6h (warning), 24h (info)
- [ ] Alert severity levels defined
- [ ] Recording rules update every 1m
- [ ] SLO files in `slo/definitions/{service-name}.yaml`

### Service Structure Review
- [ ] Service has own namespace (auth, user, product, etc.)
- [ ] Service code in `cmd/{service-name}/` and `internal/{service-name}/`
- [ ] K8s manifests in `k8s/{service-name}/`
- [ ] SLO definition in `slo/definitions/{service-name}.yaml`
- [ ] Build script includes service
- [ ] Deploy script includes service

### Script Review
- [ ] Scripts use numbered prefixes (01-13)
- [ ] Scripts follow naming convention: `{number}-{purpose}.sh`
- [ ] Scripts reference correct namespaces
- [ ] SLO scripts use correct paths: `slo/definitions/`, `slo/generated/`
