# Research: Jaeger + Tempo Dual Backend Architecture

## Executive Summary

This research investigates best practices for running Jaeger and Tempo in parallel, focusing on industry patterns, SDK vs sidecar approaches, and production recommendations. The current setup uses OpenTelemetry Collector as a fan-out layer, with microservices using OTel SDK to send traces to both backends simultaneously.

**Key Findings:**
- Dual backend strategy is valid for migration scenarios and A/B testing
- SDK approach is appropriate for Go microservices with custom instrumentation needs
- Current architecture aligns with CNCF best practices for gradual migration
- Production improvements needed: persistent storage, HA, and monitoring

## Current Architecture Analysis

### Setup Overview

**Components:**
1. **OpenTelemetry Collector** (Deployment mode)
   - Receives traces via OTLP (gRPC:4317, HTTP:4318)
   - Fan-out to Tempo and Jaeger
   - Batch processing and memory limiting

2. **Jaeger v2** (All-in-one, in-memory)
   - OTLP receiver enabled
   - Memory storage (100k traces max)
   - Query UI on port 16686

3. **Tempo** (Existing)
   - OTLP receiver
   - Object storage backend

4. **Microservices** (9 Go services)
   - OpenTelemetry SDK instrumentation
   - Direct OTLP HTTP export to collector
   - 10% sampling in production

### Architecture Diagram

```
Microservices (SDK)
    ↓ OTLP HTTP
OpenTelemetry Collector (Fan-out)
    ├─→ Tempo (Production)
    └─→ Jaeger v2 (Alternative UI)
```

### Code Analysis

**SDK Implementation** (`services/pkg/middleware/tracing.go`):
- Uses `otlptracehttp` exporter
- Batch export with 5s timeout
- Compression enabled (Gzip)
- Kubernetes resource auto-detection
- Custom sampling (10% production)

**Configuration Pattern:**
- All services use `OTEL_COLLECTOR_ENDPOINT` env var (renamed from TEMPO_ENDPOINT in v0.8.1)
- Points to OTel Collector (not directly to backends)
- Consistent across all 9 microservices

## Industry Patterns & Case Studies

### Uber's Jaeger Implementation

**Architecture:**
- Developed Jaeger for microservices ecosystem
- Processes billions of spans daily
- Agent-based architecture (UDP → Collector)
- Storage backends: Cassandra, Elasticsearch

**Key Insights:**
- Agent pattern reduces application overhead
- Scalable collector architecture
- Real-time query capabilities

**Relevance:**
- Our SDK approach is simpler but less scalable
- Consider agent pattern for high-volume production

### Netflix's Tracing at Scale

**Approach:**
- Custom adaptive sampling strategies
- Real-time alerting on trace anomalies
- Integration with chaos engineering
- Correlation with business metrics

**Key Insights:**
- Sampling is critical at scale
- Traces should drive alerts, not just debugging
- Business context matters

**Relevance:**
- Current 10% sampling is good start
- Need adaptive sampling for production
- Consider trace-based alerting

### Google's Dapper

**Design Principles:**
- Low overhead instrumentation
- Massive scalability
- Sampling mechanisms
- Influenced Jaeger and Zipkin

**Key Insights:**
- Instrumentation must be lightweight
- Sampling is essential
- System-wide visibility

**Relevance:**
- SDK approach aligns with low overhead
- Current batch export reduces impact
- Need better sampling strategies

### Dual Backend Strategies

**Common Use Cases:**
1. **Migration Scenarios:**
   - Running both during transition
   - Validate new backend before cutover
   - Gradual service migration

2. **A/B Testing:**
   - Compare backend performance
   - Evaluate features
   - Cost analysis

3. **Redundancy:**
   - Backup for critical traces
   - Different retention policies
   - Compliance requirements

**CNCF Recommendations:**
- Use OTel Collector for fan-out (matches our approach)
- Parallel operation during migration
- Validate before decommissioning old backend

## SDK vs Sidecar Comparison

### SDK Approach (Current)

**Advantages:**
- ✅ Full control over instrumentation
- ✅ Custom sampling and attributes
- ✅ No additional containers
- ✅ Language-specific optimizations
- ✅ Lower resource overhead (no sidecar)
- ✅ Simpler deployment

**Disadvantages:**
- ❌ Requires code changes
- ❌ Language-specific implementation
- ❌ Application handles export overhead
- ❌ Less flexible for polyglot environments

**Performance:**
- CPU overhead: ~1-3% per service
- Memory: ~10-20MB per service
- Network: Direct to collector (efficient)

### Sidecar Approach

**Advantages:**
- ✅ No code changes required
- ✅ Works with any language
- ✅ Auto-instrumentation possible
- ✅ Offloads processing from app
- ✅ Centralized configuration

**Disadvantages:**
- ❌ Higher resource usage (extra container)
- ❌ More complex deployment
- ❌ Less control over instrumentation
- ❌ Pod resource limits shared

**Performance:**
- CPU overhead: ~5-10% per pod (collector)
- Memory: ~50-100MB per pod (collector)
- Network: Localhost (very efficient)

### Recommendation

**For Current Setup (Go Microservices):**
- **SDK approach is correct** for:
  - Homogeneous Go stack
  - Custom instrumentation needs
  - Resource efficiency
  - Learning/POC environment

**Consider Sidecar When:**
- Polyglot services (Java, Python, Node.js)
- Zero-code instrumentation needed
- Large-scale production (100+ services)
- Need centralized collector management

## Dual Backend Strategies

### Current Strategy: Fan-out via OTel Collector

**Architecture:**
```
Apps → OTel Collector → {Tempo, Jaeger}
```

**Benefits:**
- Single endpoint for applications
- Easy to add/remove backends
- Consistent configuration
- No application changes needed

**Limitations:**
- Single point of failure (collector)
- Resource overhead (fan-out processing)
- Both backends receive all traces

### Alternative Strategies

**1. Conditional Routing:**
```
Apps → OTel Collector → Router → {Tempo (prod), Jaeger (dev)}
```
- Route by service, environment, or sampling
- More efficient resource usage
- Complex configuration

**2. Direct Export (Not Recommended):**
```
Apps → {Tempo, Jaeger}
```
- No collector overhead
- Application complexity
- Harder to manage

**3. Tiered Architecture:**
```
Apps → OTel Collector → Tempo (primary)
                    → Jaeger (backup/archive)
```
- Primary/backup pattern
- Cost optimization
- Different retention policies

### Recommendation

**Current fan-out approach is appropriate for:**
- Migration scenarios
- A/B testing
- POC/development environments

**For Production:**
- Consider conditional routing
- Implement tiered architecture
- Add monitoring and alerting

## Production Recommendations

### Immediate Improvements

**1. Persistent Storage for Jaeger:**
```yaml
storage:
  type: badger
  badger:
    ephemeral: false
    directory: /badger
```
- Current in-memory storage loses data on restart
- Badger provides persistence without external DB

**2. High Availability:**
- Scale OTel Collector to 2+ replicas
- Load balancer for collector service
- Health checks and auto-restart

**3. Monitoring:**
- Monitor collector metrics (port 8888)
- Alert on export failures
- Track trace volume and latency

**4. Resource Allocation:**
```yaml
resources:
  requests:
    memory: "512Mi"  # Increase from 256Mi
    cpu: "200m"      # Increase from 100m
  limits:
    memory: "1Gi"    # Increase from 512Mi
    cpu: "500m"      # Keep same
```

### Medium-term Improvements

**1. Adaptive Sampling:**
- Head-based sampling in collector
- Tail-based sampling for errors
- Service-specific rates

**2. Trace-based Alerting:**
- Alert on error rate spikes
- SLA violation detection
- Anomaly detection

**3. Cost Optimization:**
- Conditional routing (dev → Jaeger, prod → Tempo)
- Different retention policies
- Archive old traces

**4. Security:**
- TLS between collector and backends
- Authentication for query endpoints
- Network policies

### Long-term Considerations

**1. Migration Path:**
- Phase 1: Parallel operation (current)
- Phase 2: Validate Tempo meets requirements
- Phase 3: Route production to Tempo only
- Phase 4: Decommission Jaeger

**2. Scaling:**
- Horizontal scaling of collector
- Distributed tracing storage
- Multi-region support

**3. Advanced Features:**
- Trace correlation with logs/metrics
- Service dependency graphs
- Performance profiling integration

## Migration Paths

### From Current to Production-Ready

**Step 1: Add Persistence**
- Configure Badger storage for Jaeger
- Test data retention
- Verify performance

**Step 2: Improve Reliability**
- Scale collector to 2 replicas
- Add health checks
- Implement retry logic

**Step 3: Add Monitoring**
- Expose collector metrics
- Create Grafana dashboards
- Set up alerts

**Step 4: Optimize**
- Implement conditional routing
- Fine-tune sampling
- Optimize resource allocation

### From Dual to Single Backend

**If Choosing Tempo:**
1. Validate Tempo meets all requirements
2. Update collector to route only to Tempo
3. Monitor for issues
4. Decommission Jaeger

**If Choosing Jaeger:**
1. Configure persistent storage (Cassandra/ES)
2. Scale Jaeger for production
3. Update collector configuration
4. Decommission Tempo

## Jaeger Operator Status

### Jaeger Operator v1 (Deprecated for v2)

**Status:**
- Jaeger Operator v1 (`jaegertracing.io/v1`) is for **Jaeger v1 only**
- **Deprecated** for Jaeger v2 deployments
- Still maintained for existing v1 deployments
- Uses CRD: `apiVersion: jaegertracing.io/v1`

**Use Case:**
- Legacy Jaeger v1 deployments
- Not recommended for new deployments

### Jaeger v2 Deployment Options

**1. Helm Chart (Current Approach) ✅**
```yaml
# k8s/jaeger/values.yaml
allInOne:
  enabled: true
  image:
    repository: jaegertracing/jaeger
    tag: ""
```

**Advantages:**
- Simple and straightforward
- No operator overhead
- Direct control over configuration
- Works well for POC/development

**Disadvantages:**
- Manual scaling and management
- No auto-instrumentation
- Less Kubernetes-native

**2. OpenTelemetry Operator (Recommended for Production)**
```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: jaeger-instance
spec:
  image: jaegertracing/jaeger:latest
  config:
    # OTel Collector config
```

**Advantages:**
- Kubernetes-native (CRD-based)
- Auto-instrumentation support
- Dynamic scaling
- GitOps-friendly
- Unified with OTel ecosystem

**Disadvantages:**
- Requires cert-manager
- More complex setup
- Operator overhead

**3. Direct Deployment (Not Recommended)**
- Manual YAML manifests
- No automation
- Hard to maintain

### Recommendation

**Current Setup (Helm Chart):**
- ✅ **Perfect for POC/learning** - Simple, direct control
- ✅ **No operator overhead** - Lighter weight
- ✅ **Easy to understand** - Clear configuration

**When to Consider OpenTelemetry Operator:**
- Production with 10+ services
- Need auto-instrumentation
- GitOps workflow
- Multiple collectors across namespaces
- Dynamic scaling requirements

### Migration Path (If Needed)

**From Helm to Operator:**
1. Install OpenTelemetry Operator
2. Create `OpenTelemetryCollector` CRD
3. Migrate config from `values.yaml` to CRD
4. Test and validate
5. Remove Helm deployment

**Note:** Current Helm approach is fine - no need to migrate unless you need operator features.

## Open Questions

1. **Retention Policy:**
   - How long to keep traces?
   - Different policies per backend?
   - Archive strategy?

2. **Sampling Strategy:**
   - Current 10% sufficient?
   - Need adaptive sampling?
   - Error-based sampling?

3. **Cost Analysis:**
   - Storage costs comparison?
   - Compute overhead?
   - Network bandwidth?

4. **Team Preferences:**
   - UI preference (Jaeger vs Grafana)?
   - Query language (TraceQL vs Jaeger search)?
   - Integration with existing tools?

5. **Deployment Method:**
   - Stick with Helm (current)?
   - Migrate to OpenTelemetry Operator?
   - When to consider operator?

## Conclusion

The current dual backend architecture with OTel Collector fan-out is a solid foundation that aligns with industry best practices for migration scenarios. The SDK approach is appropriate for Go microservices, providing good control and efficiency.

**Key Recommendations:**
1. Add persistent storage for Jaeger
2. Scale collector for HA
3. Implement monitoring and alerting
4. Consider conditional routing for production
5. Plan migration path to single backend

**Next Steps:**
- Document architecture in `docs/development/TRACING_ARCHITECTURE.md`
- Create production deployment guide
- Set up monitoring dashboards
- Plan migration timeline
