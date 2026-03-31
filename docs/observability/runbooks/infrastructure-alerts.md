# Runbook: Infrastructure Alerts

> **Purpose**: Per-alert investigation guide for Kubernetes infrastructure alerts covering the USE Method (Utilization, Saturation, Errors) for pods, nodes, workloads, cache, API server, and network.
>
> **Manifests**:
> - [`kubernetes-pod-resources-alerts.yaml`](../../../kubernetes/infra/configs/monitoring/prometheusrules/kubernetes-pod-resources-alerts.yaml)
> - [`kubernetes-workload-alerts.yaml`](../../../kubernetes/infra/configs/monitoring/prometheusrules/kubernetes-workload-alerts.yaml)
> - [`kubernetes-node-alerts.yaml`](../../../kubernetes/infra/configs/monitoring/prometheusrules/kubernetes-node-alerts.yaml)
> - [`valkey-alerts.yaml`](../../../kubernetes/infra/configs/monitoring/prometheusrules/valkey-alerts.yaml)
> - [`kube-apiserver-alerts.yaml`](../../../kubernetes/infra/configs/monitoring/prometheusrules/kube-apiserver-alerts.yaml)
> - [`kubernetes-network-rules.yaml`](../../../kubernetes/infra/configs/monitoring/prometheusrules/kubernetes-network-rules.yaml)
>
> **Last Updated**: 2026-03-31

---

## Table of Contents

1. [Pod Resource Alerts](#1-pod-resource-alerts)
2. [Kubernetes Workload Alerts](#2-kubernetes-workload-alerts)
3. [Node Alerts](#3-node-alerts)
4. [Valkey/Redis Alerts](#4-valkeyredis-alerts)
5. [API Server Alerts](#5-api-server-alerts)
6. [Network Alerts](#6-network-alerts)
7. [Alert Summary](#7-alert-summary)

---

## 1. Pod Resource Alerts

### KubePodCPUThrottlingHigh

**Fires when**: Container CPU throttling exceeds 25% of CFS periods for 15 minutes.

**Severity**: warning | **Category**: resources

**Possible causes**:
- CPU limits too low for the workload
- Bursty CPU usage hitting CFS quota ceiling
- Noisy neighbor on the same node consuming CPU

**Investigation**:

```bash
# Check container resource limits
kubectl get pod -n $NAMESPACE $POD -o jsonpath='{.spec.containers[*].resources}'

# Check actual CPU usage vs limits
kubectl top pod -n $NAMESPACE $POD --containers
```

```promql
# Verify throttling percentage
sum by (namespace, pod, container) (
  increase(container_cpu_cfs_throttled_periods_total{namespace="$NAMESPACE", pod="$POD"}[5m])
) / sum by (namespace, pod, container) (
  increase(container_cpu_cfs_periods_total{namespace="$NAMESPACE", pod="$POD"}[5m])
)
```

**Resolution**:
- Increase CPU limits if the workload genuinely needs more CPU
- Consider removing CPU limits entirely (use requests only) per [Google's best practices](https://home.robusta.dev/blog/stop-using-cpu-limits)
- If the service is a Go app, check `GOMAXPROCS` aligns with CPU requests

---

### KubePodMemoryNearLimit

**Fires when**: Container memory working set exceeds 90% of its memory limit for 15 minutes.

**Severity**: warning | **Category**: resources

**Possible causes**:
- Memory limits too conservative for the workload
- Memory leak (gradually increasing over time)
- Large in-memory cache or data structure

**Investigation**:

```bash
# Check memory limits
kubectl get pod -n $NAMESPACE $POD -o jsonpath='{.spec.containers[*].resources}'

# Check actual memory usage
kubectl top pod -n $NAMESPACE $POD --containers
```

```promql
# Memory usage ratio
container_memory_working_set_bytes{namespace="$NAMESPACE", pod="$POD"}
/ kube_pod_container_resource_limits{resource="memory", namespace="$NAMESPACE", pod="$POD"}
```

**Resolution**:
- Increase memory limits if usage is stable at high levels
- If Go service: check heap profiles via Pyroscope, tune `GOMEMLIMIT`
- Check for memory leak pattern: steadily increasing `go_memstats_alloc_bytes` without returning to baseline

**Related alerts**: `KubePodOOMKilled` (fires if memory hits the hard limit)

---

### KubePodOOMKilled

**Fires when**: A container is terminated with OOMKilled reason.

**Severity**: critical | **Category**: resources

**Possible causes**:
- Container exceeded its memory limit
- Memory leak
- Spike in request volume causing temporary memory pressure

**Investigation**:

```bash
# Check terminated container status
kubectl describe pod -n $NAMESPACE $POD | grep -A5 "Last State"

# Check previous container logs
kubectl logs -n $NAMESPACE $POD -c $CONTAINER --previous --tail=200
```

```promql
# Check memory trajectory before OOM
container_memory_working_set_bytes{namespace="$NAMESPACE", pod=~"$POD.*"}
```

**Resolution**:
- Increase memory limits
- For Go services: set `GOMEMLIMIT` to ~90% of the memory limit to trigger GC before OOM
- Investigate heap profiles in Pyroscope for memory leak detection

---

### KubePodCrashLooping

**Fires when**: Container is in CrashLoopBackOff for 10 minutes.

**Severity**: critical | **Category**: resources

**Possible causes**:
- Application startup failure (missing config, database unavailable)
- Readiness/liveness probe misconfiguration
- Dependency not ready (database, secrets, ConfigMap)

**Investigation**:

```bash
# Check pod events
kubectl describe pod -n $NAMESPACE $POD

# Check previous container logs
kubectl logs -n $NAMESPACE $POD --previous --tail=200

# Check if dependencies are ready
kubectl get pods -n $NAMESPACE
kubectl get externalsecrets -n $NAMESPACE
```

**Resolution**:
- Fix the root cause from container logs
- Check if database migrations completed (`kubectl get jobs -n $NAMESPACE`)
- Verify ExternalSecret sync status if secrets are missing

---

### KubePodNotReady

**Fires when**: Pod stuck in Pending/Unknown state for 15 minutes.

**Severity**: warning | **Category**: resources

**Possible causes**:
- Insufficient cluster resources (CPU/memory)
- Node affinity/taint preventing scheduling
- PVC not bound
- Image pull failure

**Investigation**:

```bash
# Check pod events for scheduling issues
kubectl describe pod -n $NAMESPACE $POD

# Check node resources
kubectl describe nodes | grep -A5 "Allocated resources"

# Check PVC status
kubectl get pvc -n $NAMESPACE
```

**Resolution**:
- If resource constrained: scale down other workloads or add nodes
- If PVC issue: check StorageClass and provisioner
- If image pull: verify image exists and credentials are correct

---

## 2. Kubernetes Workload Alerts

### KubeDeploymentReplicasMismatch

**Fires when**: Deployment desired replicas != ready replicas for 15 minutes.

**Severity**: warning | **Category**: workloads

**Investigation**:

```bash
# Check deployment status
kubectl get deployment -n $NAMESPACE $DEPLOYMENT
kubectl describe deployment -n $NAMESPACE $DEPLOYMENT

# Check replica set events
kubectl get rs -n $NAMESPACE -l app=$DEPLOYMENT
kubectl describe rs -n $NAMESPACE $(kubectl get rs -n $NAMESPACE -l app=$DEPLOYMENT --sort-by=.metadata.creationTimestamp -o name | tail -1)
```

```promql
# Verify mismatch
kube_deployment_spec_replicas{namespace="$NAMESPACE", deployment="$DEPLOYMENT"}
- kube_deployment_status_ready_replicas{namespace="$NAMESPACE", deployment="$DEPLOYMENT"}
```

**Resolution**:
- Check if pods are stuck in Pending (resource constraints) or CrashLoopBackOff
- If during rollout: wait for completion or rollback with `kubectl rollout undo`
- Check HPA if autoscaling is active

---

### KubeStatefulSetReplicasMismatch

**Fires when**: StatefulSet ready replicas != desired replicas for 15 minutes.

**Severity**: warning | **Category**: workloads

**Investigation**:

```bash
kubectl get statefulset -n $NAMESPACE $STATEFULSET
kubectl describe statefulset -n $NAMESPACE $STATEFULSET
kubectl get pvc -n $NAMESPACE -l app=$STATEFULSET
```

**Resolution**:
- StatefulSets scale sequentially; check if a pod is stuck
- Verify PVCs are bound for each replica
- For database StatefulSets: check operator status (Zalando/CNPG)

---

### KubeJobFailed

**Fires when**: A Job has failed pods for 5 minutes.

**Severity**: warning | **Category**: workloads

**Investigation**:

```bash
kubectl describe job -n $NAMESPACE $JOB_NAME
kubectl logs -n $NAMESPACE job/$JOB_NAME --tail=200
```

**Resolution**:
- Check job logs for the failure reason
- For Flyway migration jobs: check database connectivity and SQL syntax
- Retry: `kubectl delete job -n $NAMESPACE $JOB_NAME` (will be recreated if managed by Flux)

---

### KubeHPAMaxedOut

**Fires when**: HPA current replicas == max replicas for 15 minutes.

**Severity**: warning | **Category**: saturation

**Investigation**:

```bash
kubectl get hpa -n $NAMESPACE $HPA
kubectl describe hpa -n $NAMESPACE $HPA
```

```promql
# Check current vs max
kube_horizontalpodautoscaler_status_current_replicas{namespace="$NAMESPACE"}
/ kube_horizontalpodautoscaler_spec_max_replicas{namespace="$NAMESPACE"}
```

**Resolution**:
- If load is genuinely higher: increase `maxReplicas` in HPA spec
- If load is temporary: wait for scale-down
- Check if CPU/memory requests are too low (causing premature scale-up)

---

### KubePersistentVolumeFillingUp

**Fires when**: PVC has less than 15% free space for 10 minutes.

**Severity**: warning (15%), critical (5%)

**Investigation**:

```bash
# Check PVC usage
kubectl exec -n $NAMESPACE $POD -- df -h /path/to/mount

# Check PVC capacity
kubectl get pvc -n $NAMESPACE $PVC -o jsonpath='{.status.capacity.storage}'
```

```promql
# PVC utilization
1 - kubelet_volume_stats_available_bytes{namespace="$NAMESPACE", persistentvolumeclaim="$PVC"}
    / kubelet_volume_stats_capacity_bytes{namespace="$NAMESPACE", persistentvolumeclaim="$PVC"}
```

**Resolution**:
- Expand PVC if StorageClass supports volume expansion
- For database PVCs: check WAL accumulation, run VACUUM, or investigate replication lag
- Clean up old data/logs if applicable

---

## 3. Node Alerts

### KubeNodeNotReady

**Fires when**: Node Ready condition is false for 5 minutes.

**Severity**: critical | **Category**: nodes

**Investigation**:

```bash
kubectl get nodes
kubectl describe node $NODE
kubectl get events --field-selector involvedObject.name=$NODE
```

**Resolution**:
- Check kubelet logs on the node
- In Kind: restart the Kind container (`docker restart kind-control-plane`)
- Check for disk pressure or memory pressure conditions

---

### KubeNodeMemoryPressure

**Fires when**: Node MemoryPressure condition is true for 5 minutes.

**Severity**: warning | **Category**: nodes

**Investigation**:

```bash
kubectl describe node $NODE | grep -A10 "Conditions"
kubectl top pods --all-namespaces --sort-by=memory | head -20
```

**Resolution**:
- Identify and scale down memory-heavy pods
- Add memory limits to unbounded pods
- In Kind: increase Docker memory allocation

---

### KubeNodeDiskPressure

**Fires when**: Node DiskPressure condition is true for 5 minutes.

**Severity**: warning | **Category**: nodes

**Investigation**:

```bash
kubectl describe node $NODE | grep -A10 "Conditions"
# In Kind:
docker exec kind-control-plane df -h
docker exec kind-control-plane crictl images
```

**Resolution**:
- Clean up unused images: `docker exec kind-control-plane crictl rmi --prune`
- Check for large log files or WAL accumulation
- Expand disk allocation for Docker/Kind

---

### KubeNodePIDPressure

**Fires when**: Node PIDPressure condition is true for 5 minutes.

**Severity**: warning | **Category**: nodes

**Investigation**:

```bash
kubectl describe node $NODE | grep -A10 "Conditions"
# Check process count in Kind:
docker exec kind-control-plane ps aux | wc -l
```

**Resolution**:
- Identify pods with goroutine leaks (check `MicroserviceGoroutineLeak` alert)
- Kill runaway processes
- Increase PID limits if configured

---

### KubeNodeUnschedulable

**Fires when**: Node is cordoned (unschedulable) for 5 minutes.

**Severity**: warning | **Category**: nodes

**Investigation**:

```bash
kubectl get nodes -o wide
kubectl describe node $NODE | grep -i taint
```

**Resolution**:
- If intentional (maintenance): no action needed
- If accidental: `kubectl uncordon $NODE`

---

## 4. Valkey/Redis Alerts

### ValkeyDown

**Fires when**: `redis_up == 0` for 1 minute.

**Severity**: critical | **Category**: availability

**Investigation**:

```bash
kubectl get pods -n cache-system
kubectl describe pod -n cache-system -l app.kubernetes.io/name=valkey
kubectl logs -n cache-system -l app.kubernetes.io/name=valkey --tail=100
```

**Resolution**:
- Check pod events for OOM or scheduling issues
- Verify PVC is bound if persistence is enabled
- Check HelmRelease status: `kubectl get helmrelease -n cache-system`

**Impact**: Cache-Aside pattern will fall through to database for all cached endpoints (product service). Expect increased database load.

---

### ValkeyMemorySaturation

**Fires when**: Memory usage exceeds 90% (warning) or 95% (critical) of maxmemory.

**Severity**: warning/critical | **Category**: saturation

**Investigation**:

```promql
# Current memory usage ratio
redis_memory_used_bytes / redis_memory_max_bytes

# Eviction rate
rate(redis_evicted_keys_total[5m])
```

```bash
# Check memory config
kubectl exec -n cache-system $POD -- redis-cli INFO memory
```

**Resolution**:
- Increase `maxmemory` in Valkey Helm values
- Review key TTLs: shorten TTLs for less critical data
- Check eviction policy (`allkeys-lru` recommended for cache use case)

---

### ValkeyHighEvictionRate

**Fires when**: Eviction rate exceeds 100 keys/sec for 10 minutes.

**Severity**: warning | **Category**: saturation

**Resolution**:
- Increase `maxmemory` to reduce eviction pressure
- Audit cache key patterns: are large/unnecessary keys consuming space?
- Consider adding a second Valkey instance for hot key isolation

---

### ValkeyHighMissRatio

**Fires when**: Cache miss ratio exceeds 50% for 10 minutes.

**Severity**: warning | **Category**: errors

**Possible causes**:
- Cache warming not complete after restart
- Key TTLs too short
- Application querying keys that were never cached
- Evictions removing frequently accessed keys

**Investigation**:

```promql
# Hit ratio
rate(redis_keyspace_hits_total[5m])
/ (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))
```

**Resolution**:
- If after restart: wait for cache to warm up
- Increase TTLs for frequently accessed keys
- Check that Cache-Aside pattern is correctly implemented in application code

---

### ValkeyHighClientConnections

**Fires when**: Connected clients exceed 100 for 5 minutes.

**Severity**: warning | **Category**: saturation

**Investigation**:

```bash
kubectl exec -n cache-system $POD -- redis-cli CLIENT LIST | wc -l
kubectl exec -n cache-system $POD -- redis-cli INFO clients
```

**Resolution**:
- Check for connection leaks in application code (connections not being returned to pool)
- Tune connection pool settings in microservices
- Increase `maxclients` if legitimately needed

---

### ValkeyRejectedConnections

**Fires when**: Any connections rejected in 5 minutes.

**Severity**: critical | **Category**: errors

**Resolution**:
- Increase `maxclients` configuration
- Fix connection leaks (see `ValkeyHighClientConnections`)
- Check if a burst of new pod replicas overwhelmed the connection limit

---

## 5. API Server Alerts

### KubeAPIServerDown

**Fires when**: API server is unreachable for 5 minutes.

**Severity**: critical | **Category**: availability

**Investigation**:

```bash
kubectl cluster-info
# In Kind:
docker ps | grep control-plane
docker logs kind-control-plane 2>&1 | tail -50
```

**Resolution**:
- In Kind: `docker restart kind-control-plane`
- Check etcd health (API server depends on it)
- Check for resource exhaustion on control plane node

---

### KubeAPIServerHighLatency

**Fires when**: API server P99 latency exceeds 1s for non-LIST/WATCH verbs for 10 minutes.

**Severity**: warning | **Category**: latency

**Investigation**:

```promql
# P99 latency by verb and resource
histogram_quantile(0.99,
  sum by (le, verb, resource) (
    rate(apiserver_request_duration_seconds_bucket{verb!~"LIST|WATCH"}[5m])
  )
)
```

**Resolution**:
- Check for slow admission webhooks
- Check etcd latency
- Look for resource-intensive custom controllers

---

### KubeAPIServerErrorRate

**Fires when**: 5xx error rate exceeds 3% for 10 minutes.

**Severity**: warning | **Category**: errors

**Investigation**:

```promql
# Error rate by verb and resource
sum by (verb, resource, code) (rate(apiserver_request_total{code=~"5.."}[5m]))
```

**Resolution**:
- Check for failing webhooks (`MutatingWebhookConfiguration`, `ValidatingWebhookConfiguration`)
- Check etcd connectivity
- Review recent CRD changes

---

### KubeAPIServerHighInflight

**Fires when**: Inflight requests exceed 200 for 5 minutes.

**Severity**: warning | **Category**: saturation

**Investigation**:

```promql
apiserver_current_inflight_requests
```

**Resolution**:
- Identify controllers making excessive API calls
- Check for tight reconciliation loops in Flux or other operators
- Increase API server `--max-requests-inflight` if legitimately needed

---

## 6. Network Alerts

### KubeContainerNetworkErrors

**Fires when**: Network error rate exceeds 1 error/sec for 10 minutes.

**Severity**: warning | **Category**: network

**Investigation**:

```promql
sum by (namespace, pod) (
  rate(container_network_receive_errors_total[5m])
  + rate(container_network_transmit_errors_total[5m])
)
```

```bash
kubectl describe pod -n $NAMESPACE $POD
kubectl get networkpolicies -n $NAMESPACE
```

**Resolution**:
- Check CNI plugin health (in Kind: kindnet)
- Review NetworkPolicies that might be causing drops
- Check for DNS resolution issues

---

## 7. Alert Summary

| Group | Alert | Severity | For | Methodology |
|-------|-------|----------|-----|-------------|
| **Pod CPU** | `KubePodCPUThrottlingHigh` | warning | 15m | USE: Saturation |
| **Pod Memory** | `KubePodMemoryNearLimit` | warning | 15m | USE: Utilization |
| | `KubePodOOMKilled` | critical | 0m | USE: Errors |
| **Pod Health** | `KubePodCrashLooping` | critical | 10m | USE: Errors |
| | `KubePodNotReady` | warning | 15m | USE: Errors |
| **Workloads** | `KubeDeploymentReplicasMismatch` | warning | 15m | USE: Errors |
| | `KubeStatefulSetReplicasMismatch` | warning | 15m | USE: Errors |
| | `KubeJobFailed` | warning | 5m | USE: Errors |
| **Autoscaling** | `KubeHPAMaxedOut` | warning | 15m | USE: Saturation |
| **Storage** | `KubePersistentVolumeFillingUp` | warning | 10m | USE: Utilization |
| | `KubePersistentVolumeFillingUpCritical` | critical | 5m | USE: Utilization |
| **Nodes** | `KubeNodeNotReady` | critical | 5m | Golden: Errors |
| | `KubeNodeMemoryPressure` | warning | 5m | USE: Saturation |
| | `KubeNodeDiskPressure` | warning | 5m | USE: Saturation |
| | `KubeNodePIDPressure` | warning | 5m | USE: Saturation |
| | `KubeNodeUnschedulable` | warning | 5m | USE: Errors |
| **Valkey** | `ValkeyDown` | critical | 1m | USE: Errors |
| | `ValkeyMemorySaturation` | warning | 5m | USE: Saturation |
| | `ValkeyMemorySaturationCritical` | critical | 2m | USE: Saturation |
| | `ValkeyHighEvictionRate` | warning | 10m | USE: Saturation |
| | `ValkeyHighMissRatio` | warning | 10m | RED: Errors |
| | `ValkeyHighClientConnections` | warning | 5m | USE: Saturation |
| | `ValkeyRejectedConnections` | critical | 0m | USE: Errors |
| **API Server** | `KubeAPIServerDown` | critical | 5m | Golden: Errors |
| | `KubeAPIServerHighLatency` | warning | 10m | Golden: Latency |
| | `KubeAPIServerErrorRate` | warning | 10m | Golden: Errors |
| | `KubeAPIServerHighInflight` | warning | 5m | Golden: Saturation |
| **Network** | `KubeContainerNetworkErrors` | warning | 10m | USE: Errors |
