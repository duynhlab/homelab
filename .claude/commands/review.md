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

## Review Checklist

### Dashboard Review
- [ ] Panel descriptions present and concise
- [ ] Legend configured (table mode, Mean/Max, sorted by Max desc)
- [ ] Color thresholds appropriate (Green/Yellow/Red)
- [ ] Units correct (bytes, short, reqps, percent, ms)
- [ ] GridPos layout logical and not overlapping
- [ ] Template variables used (`$rate`, `$namespace`, `$app`)

### Prometheus Query Review
- [ ] `rate()` used for counters with `$rate` variable
- [ ] Aggregation strategy appropriate (`sum(...) by (app)` for overview)
- [ ] Namespace filtering: `{namespace=~"$namespace"}`
- [ ] App filtering: `{app=~"$app"}`
- [ ] Histogram quantiles: `histogram_quantile(0.95, sum(rate(...)) by (le))`
- [ ] No hardcoded time windows (use `$rate`)

### Kubernetes Manifest Review
- [ ] Namespace: `monitoring-demo`
- [ ] Labels: `app`, `version`, `component`
- [ ] Resource limits appropriate (memory: 256Mi-512Mi, CPU: 100m-500m)
- [ ] ConfigMap naming: `{component}-{type}`
- [ ] Service naming matches deployment
- [ ] Deployment strategy: RollingUpdate

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
