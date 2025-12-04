# Continuous Profiling Guide

## Quick Summary

**Objectives:**
- Enable continuous profiling for performance analysis
- Identify CPU, memory, and concurrency bottlenecks
- Use flamegraphs to visualize performance data

**Learning Outcomes:**
- Continuous profiling concepts
- CPU, heap, goroutine, and mutex profiling
- Flamegraph interpretation
- Performance optimization techniques
- Production profiling best practices

**Keywords:**
Continuous Profiling, CPU Profiling, Heap Profiling, Goroutine Profiling, Mutex Profiling, Flamegraph, Performance Analysis, Optimization, Pyroscope

**Technologies:**
- Pyroscope (continuous profiling)
- Go pprof (profiling format)
- Flamegraph visualization

## Overview

**Pyroscope** provides continuous profiling for all services, enabling performance analysis and optimization.

## Profile Types

The following profile types are collected:

1. **CPU**: CPU usage profiling
2. **Alloc Objects**: Object allocation count
3. **Alloc Space**: Memory allocation size
4. **Inuse Objects**: Objects in use
5. **Inuse Space**: Memory in use
6. **Goroutines**: Goroutine count
7. **Mutex Count**: Mutex contention count
8. **Mutex Duration**: Mutex contention duration
9. **Block Count**: Blocking operation count
10. **Block Duration**: Blocking operation duration

## Configuration

### Environment Variables

- `PYROSCOPE_ENDPOINT`: Pyroscope server endpoint (default: `http://pyroscope.monitoring.svc.cluster.local:4040`)
- `APP_NAME`: Service name (from Kubernetes pod label)
- `NAMESPACE`: Kubernetes namespace (from pod metadata)

### Service Initialization

```go
// Initialize Pyroscope profiling
if err := middleware.InitProfiling(); err != nil {
    logger.Warn("Failed to initialize profiling", zap.Error(err))
} else {
    defer middleware.StopProfiling()
}
```

## Viewing Profiles

### Grafana

1. Port-forward Grafana:
   ```bash
   kubectl port-forward -n monitoring svc/grafana-service 3000:3000
   ```

2. Open Grafana: http://localhost:3000

3. Navigate to **Explore** → Select **Pyroscope** datasource

4. Select:
   - Service name
   - Profile type (CPU, heap, etc.)
   - Time range

### Pyroscope UI (Direct)

```bash
kubectl port-forward -n monitoring svc/pyroscope 4040:4040
# Open http://localhost:4040
```

## Flamegraphs

Flamegraphs visualize where CPU time or memory is being spent:

1. Select a service and profile type
2. View the flamegraph
3. Click on functions to drill down
4. Compare different time ranges

## Use Cases

### CPU Profiling

Identify CPU bottlenecks:
- High CPU usage functions
- Hot paths in code
- Optimization opportunities

### Memory Profiling

Identify memory issues:
- Memory leaks
- High allocation rates
- Large object allocations

### Goroutine Profiling

Identify goroutine issues:
- Goroutine leaks
- High goroutine counts
- Blocked goroutines

### Mutex Profiling

Identify lock contention:
- High contention locks
- Long-held locks
- Deadlock potential

## Best Practices

1. **Profile in production**: Use production workloads for accurate profiling
2. **Compare before/after**: Profile before and after optimizations
3. **Focus on hotspots**: Prioritize optimizing high-impact functions
4. **Monitor trends**: Watch for gradual performance degradation
5. **Use multiple profile types**: Different profiles reveal different issues

## Troubleshooting

### Profiles not appearing

1. Check Pyroscope pod status:
   ```bash
   kubectl get pods -n monitoring -l app=pyroscope
   ```

2. Check Pyroscope logs:
   ```bash
   kubectl logs -n monitoring deployment/pyroscope
   ```

3. Verify service configuration:
   - Check `PYROSCOPE_ENDPOINT` environment variable
   - Verify profiling initialization in service logs
   - Check for initialization errors

### High overhead

Profiling has minimal overhead (<1%), but if needed:
- Reduce profile frequency
- Disable specific profile types
- Use sampling

## References

- [Pyroscope Documentation](https://pyroscope.io/docs/)
- [Go Profiling Guide](https://go.dev/blog/pprof)

