# /analyze Command

## Purpose
Analyze dashboard, metrics, or system health

## Instructions
1. Read dashboard JSON and extract panel queries
2. Check Prometheus for metric availability
3. Identify missing metrics or gaps
4. Suggest improvements based on RED method and Four Golden Signals
5. Compare with industry best practices (Nginx, VictoriaMetrics dashboards)

## Analysis Process

### Dashboard Analysis
1. **Read Dashboard Structure**
   - Parse `grafana-dashboard.json`
   - Extract panel queries and configurations
   - Identify panel types and layouts

2. **Query Analysis**
   - Check Prometheus query syntax
   - Verify variable usage (`$rate`, `$namespace`, `$app`)
   - Identify potential performance issues

3. **Metrics Availability**
   - Check if metrics exist in Prometheus
   - Verify label consistency
   - Test queries with `promtool query instant`

### Gap Analysis
1. **RED Method Coverage**
   - Rate: RPS, error rate, throughput
   - Errors: 4xx/5xx responses, failed requests
   - Duration: P50, P95, P99 latencies

2. **Four Golden Signals**
   - Latency: Response time percentiles
   - Traffic: Request rate and volume
   - Errors: Error rate and types
   - Saturation: Resource utilization

3. **Missing Metrics**
   - Identify gaps in monitoring coverage
   - Suggest additional panels
   - Recommend alerting rules

### Best Practices Comparison
1. **Nginx Monitoring**
   - Request rate by method and path
   - Error rate by method and path
   - Response time percentiles

2. **VictoriaMetrics Patterns**
   - Memory leak detection
   - GC performance monitoring
   - Resource utilization tracking

3. **SRE Practices**
   - SLI/SLO definitions
   - Error budget tracking
   - Burn rate alerts
