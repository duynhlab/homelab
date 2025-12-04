# APM (Application Performance Monitoring) Documentation

## Quick Summary

**Objectives:**
- Understand the complete APM stack (Metrics, Tracing, Logging, Profiling)
- Learn how to deploy and configure all APM components
- Integrate APM into microservices for comprehensive observability

**Learning Outcomes:**
- 4 pillars of observability: Metrics, Traces, Logs, Profiles
- How APM components work together (correlation)
- Service integration patterns with middleware
- Accessing and querying APM data in Grafana

**Keywords:**
APM, Observability, Metrics, Distributed Tracing, Structured Logging, Continuous Profiling, Correlation, Trace-ID, OpenTelemetry, Tempo, Loki, Vector, Pyroscope, Grafana

**Technologies:**
- Grafana Tempo (distributed tracing)
- Vector + Loki (log aggregation)
- Pyroscope (continuous profiling)
- OpenTelemetry (tracing standard)
- Zap (structured logging)
- Prometheus (metrics - already implemented)

## Overview

This project implements a comprehensive APM solution with four pillars:

1. **Metrics** - Prometheus metrics (already implemented)
2. **Distributed Tracing** - Grafana Tempo with OpenTelemetry
3. **Structured Logging** - JSON logs with trace-id correlation via Vector → Loki
4. **Continuous Profiling** - Pyroscope for CPU, heap, lock, and goroutine profiling

## Architecture

```
┌─────────────┐
│ Microservices│
│  (9 services)│
└──────┬──────┘
       │
       ├─── Metrics ────► Prometheus ────► Grafana
       │
       ├─── Traces ─────► Tempo ─────────► Grafana
       │
       ├─── Logs ───────► Vector ────────► Loki ──────► Grafana
       │
       └─── Profiles ───► Pyroscope ─────► Grafana
```

## Components

### 1. Distributed Tracing (Tempo)

**Purpose**: End-to-end request tracing across microservices

**Technology**: Grafana Tempo + OpenTelemetry

**Features**:
- Automatic span creation for HTTP requests
- W3C Trace Context propagation
- Trace-to-logs correlation
- Trace-to-metrics correlation

**Configuration**:
- Tempo endpoint: `http://tempo.monitoring.svc.cluster.local:4318`
- OTLP HTTP protocol
- Service name from `APP_NAME` environment variable

**Deployment**:
```bash
./scripts/04a-deploy-tempo.sh
```

### 2. Structured Logging (Vector + Loki)

**Purpose**: Centralized log aggregation with trace-id correlation

**Technology**: Vector (log collection) + Loki (log storage)

**Features**:
- JSON log parsing
- Trace-id extraction and enrichment
- Service name and namespace labels
- Log-to-trace correlation

**Configuration**:
- Vector collects logs from all pods
- Parses JSON logs and extracts trace-id
- Sends to Loki with labels for correlation

**Deployment**:
```bash
./scripts/04c-deploy-loki.sh
```

### 3. Continuous Profiling (Pyroscope)

**Purpose**: CPU, heap, lock contention, and goroutine profiling

**Technology**: Pyroscope

**Features**:
- CPU profiling
- Heap profiling (allocations, in-use)
- Goroutine profiling
- Mutex and block profiling
- Flamegraph visualization

**Configuration**:
- Pyroscope endpoint: `http://pyroscope.monitoring.svc.cluster.local:4040`
- Service name and namespace tags

**Deployment**:
```bash
./scripts/04b-deploy-pyroscope.sh
```

## Quick Start

Deploy all APM components:

```bash
./scripts/04-deploy-apm.sh
```

This will deploy:
1. Tempo (tracing)
2. Pyroscope (profiling)
3. Loki + Vector (logging)

## Service Integration

All services automatically include:

1. **Tracing Middleware**: Creates spans for HTTP requests
2. **Logging Middleware**: Structured JSON logs with trace-id
3. **Profiling**: Continuous profiling enabled on startup

### Middleware Order

```go
// Tracing middleware (must be first for context propagation)
r.Use(middleware.TracingMiddleware())

// Logging middleware
r.Use(middleware.LoggingMiddleware(logger))

// Prometheus middleware
r.Use(middleware.PrometheusMiddleware())
```

## Trace-ID Propagation

Trace-IDs are propagated via:
- **W3C Trace Context**: `traceparent` header (primary)
- **X-Trace-ID**: Custom header (fallback)

Trace-IDs are:
- Generated if not present in request
- Included in all log entries
- Stored in spans
- Added to response headers

## Correlation

### Trace-to-Logs
- Logs include `trace_id` field
- Grafana can search logs by trace-id
- Tempo datasource configured with Loki correlation

### Trace-to-Metrics
- Spans include service name and operation
- Prometheus metrics can be correlated with traces
- Tempo datasource configured with Prometheus correlation

### Trace-to-Profiles
- Profiles tagged with service name
- Can filter profiles by trace-id (future enhancement)

## Accessing APM Data

### Grafana
```bash
kubectl port-forward -n monitoring svc/grafana-service 3000:3000
# Open http://localhost:3000
```

**Datasources**:
- Prometheus (metrics)
- Tempo (traces)
- Loki (logs)
- Pyroscope (profiles)

### Direct Access
```bash
# Tempo
kubectl port-forward -n monitoring svc/tempo 3200:3200

# Pyroscope
kubectl port-forward -n monitoring svc/pyroscope 4040:4040

# Loki
kubectl port-forward -n monitoring svc/loki 3100:3100
```

## Documentation

- [Architecture Guide](./ARCHITECTURE.md) - ⭐ **3-layer architecture & APM integration diagrams**
- [Tracing Guide](./TRACING.md) - Distributed tracing details
- [Logging Guide](./LOGGING.md) - Structured logging guide
- [Profiling Guide](./PROFILING.md) - Continuous profiling guide

## Troubleshooting

### Traces not appearing
- Check Tempo pod logs: `kubectl logs -n monitoring deployment/tempo`
- Verify service has `TEMPO_ENDPOINT` env var or default is correct
- Check OpenTelemetry initialization in service logs

### Logs not appearing in Loki
- Check Vector pod logs: `kubectl logs -n monitoring -l app=vector`
- Verify Loki is running: `kubectl get pods -n monitoring -l app=loki`
- Check Vector configmap for correct Loki endpoint

### Profiles not appearing
- Check Pyroscope pod logs: `kubectl logs -n monitoring deployment/pyroscope`
- Verify service has `PYROSCOPE_ENDPOINT` env var or default is correct
- Check profiling initialization in service logs

## Next Steps

1. ✅ **3-Layer Architecture Refactor** - Completed: Services refactored into web/logic/core layers
2. **APM Dashboard** - Create comprehensive Grafana dashboard
3. **Alerting** - Set up alerts based on traces and profiles
4. **Performance Optimization** - Use profiling data to optimize services

