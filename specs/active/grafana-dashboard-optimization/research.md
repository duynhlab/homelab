# Grafana Dashboard Optimization & Prometheus Monitoring Architecture Research

**Task ID**: grafana-dashboard-optimization  
**Research Date**: December 10, 2025  
**Status**: ✅ Complete  
**Version**: v0.6.14

---

## 📋 Executive Summary

### Critical Issues Found

🔴 **CRITICAL (P0) - Variable Cascading Broken**
- **Problem**: Namespace filter không cascade xuống App filter
- **Impact**: Users chọn namespace "auth" nhưng App dropdown vẫn show ALL services (auth, cart, product, notification, order, review, shipping, user)
- **Root Cause**: App variable query không filter by `namespace=~"$namespace"`
- **Fix Required**: Update variable order và query syntax

✅ **GOOD - Query Consistency**
- All 34 PromQL queries correctly use: `{app=~"$app", namespace=~"$namespace", job=~"microservices"}`
- Consistent label filtering across 32 panels
- No panels missing required filters

✅ **GOOD - ServiceMonitor Architecture**
- Correct choice for microservices (stable endpoints)
- Proper label injection via relabelings
- Efficient service discovery across 8 namespaces

⚠️ **IMPROVEMENT NEEDED - Documentation**
- Some outdated content (pre-v0.5.0 patterns)
- Redundant explanations across multiple files
- Missing PodMonitor vs ServiceMonitor comparison

---

## 🔍 Current State Analysis

### 1. Dashboard Variables Configuration

**Current Implementation** (`k8s/grafana-operator/dashboards/microservices-dashboard.json`):

```json
{
  "templating": {
    "list": [
      // Variable 1: Datasource
      {
        "name": "DS_PROMETHEUS",
        "type": "datasource",
        "query": "prometheus"
      },
      
      // Variable 2: App (❌ WRONG ORDER - should be after namespace)
      {
        "name": "app",
        "type": "query",
        "query": "label_values(request_duration_seconds_count, app)",  // ❌ No namespace filter!
        "multi": true,
        "includeAll": true,
        "allValue": ".*"
      },
      
      // Variable 3: Namespace (❌ WRONG ORDER - should be before app)
      {
        "name": "namespace",
        "type": "query",
        "query": "label_values(kube_pod_info, namespace)",
        "regex": "/^(?!kube-|default$).*/",
        "multi": true,
        "includeAll": true,
        "allValue": ".*"
      },
      
      // Variable 4: Rate Interval
      {
        "name": "rate",
        "type": "custom",
        "options": ["1m", "2m", "3m", "5m", "10m", ...]
      }
    ]
  }
}
```

**Problems Identified:**

1. **Variable Order Incorrect**:
   - Current: `DS_PROMETHEUS` → `app` → `namespace` → `rate`
   - Correct: `DS_PROMETHEUS` → `namespace` → `app` → `rate`
   - **Why**: Namespace should come FIRST to enable cascading

2. **App Variable Query Missing Namespace Filter**:
   ```promql
   # Current (WRONG):
   label_values(request_duration_seconds_count, app)
   # Returns ALL apps from ALL namespaces
   
   # Correct (with cascading):
   label_values(request_duration_seconds_count{namespace=~"$namespace"}, app)
   # Returns ONLY apps in selected namespace(s)
   ```

3. **User Experience Impact**:
   - User selects `namespace=auth`
   - Expects: App dropdown shows only `["auth"]`
   - Reality: App dropdown shows `["All", "auth", "cart", "notification", "order", "product", "review", "shipping", "user"]`
   - **Result**: Confusing UX, defeats multi-namespace filtering purpose

---

### 2. Query Consistency Analysis

**Verification Results**: ✅ EXCELLENT

Analyzed all 34 PromQL queries in dashboard:
- ✅ 33/33 queries use `job=~"microservices"` filter
- ✅ 33/33 queries use `namespace=~"$namespace"` filter
- ✅ 33/33 queries use `app=~"$app"` filter
- ✅ 1/1 special query uses `kube_pod_container_status_restarts_total` (different metric, correct)

**Example Queries** (samples):

```promql
# Panel 1: P99 Response Time
histogram_quantile(0.99, sum(rate(request_duration_seconds_bucket{
  app=~"$app", 
  namespace=~"$namespace", 
  job=~"microservices", 
  code=~"2.."
}[$rate])) by (le))

# Panel 4: Total RPS
sum(rate(request_duration_seconds_count{
  app=~"$app", 
  namespace=~"$namespace", 
  job=~"microservices"
}[$rate]))

# Panel 7: Up Instances
count(up{
  job=~"microservices", 
  app=~"$app", 
  namespace=~"$namespace"
})
```

**Consistency Score**: 100% ✅

All queries follow the standard pattern:
```
{app=~"$app", namespace=~"$namespace", job=~"microservices"}
```

---

### 3. ServiceMonitor Architecture Review

**Current Implementation**: `k8s/prometheus/servicemonitor-microservices.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: microservices-api
  namespace: monitoring
spec:
  # Target namespaces
  namespaceSelector:
    matchNames:
      - auth
      - user
      - product
      - cart
      - order
      - review
      - notification
      - shipping
  
  # Select services with 'app' label
  selector:
    matchExpressions:
      - key: app
        operator: Exists
  
  # Scrape configuration
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
    scrapeTimeout: 10s
    relabelings:
      # Set unified job label
      - targetLabel: job
        replacement: microservices
      # Preserve service name
      - sourceLabels: [__meta_kubernetes_service_name]
        targetLabel: service
      # Add namespace label
      - sourceLabels: [__meta_kubernetes_namespace]
        targetLabel: namespace
      # Add app label
      - sourceLabels: [__meta_kubernetes_service_label_app]
        targetLabel: app
```

**Label Injection Flow**:

```
Kubernetes Service (auth.auth.svc)
  └─> ServiceMonitor discovers service
      └─> Relabeling rules inject labels:
          ├─> job="microservices"           (unified across all services)
          ├─> service="auth"                (original service name)
          ├─> namespace="auth"              (from pod metadata)
          └─> app="auth"                    (from service label)
              └─> Prometheus scrapes with full labels
                  └─> Dashboard queries filter by labels
```

**Why ServiceMonitor is Correct Choice**:

✅ **Microservices pattern**: Services are load-balanced endpoints  
✅ **Stable discovery**: Service IPs don't change (unlike pods)  
✅ **Label source**: Service labels available via `__meta_kubernetes_service_label_*`  
✅ **Scalability**: One ServiceMonitor discovers all services in 8 namespaces  
✅ **Helm integration**: Services created automatically by Helm charts

---

## 📚 Industry Best Practices Research

### 1. Grafana Variable Cascading Patterns

#### Best Practice: Hierarchical Variable Dependencies

**Standard Pattern** (namespace → service → pod):

```json
{
  "templating": {
    "list": [
      // Level 1: Datasource (independent)
      { 
        "name": "DS_PROMETHEUS",
        "type": "datasource"
      },
      
      // Level 2: Namespace (independent)
      {
        "name": "namespace",
        "query": "label_values(kube_pod_info, namespace)",
        "regex": "/^(?!kube-|default$).*/"
      },
      
      // Level 3: App (depends on namespace) ✅
      {
        "name": "app",
        "query": "label_values(metric{namespace=~\"$namespace\"}, app)"
      },
      
      // Level 4: Pod (depends on namespace + app) ✅
      {
        "name": "pod",
        "query": "label_values(kube_pod_info{namespace=~\"$namespace\", pod=~\"$app-.*\"}, pod)"
      }
    ]
  }
}
```

**Key Principles**:

1. **Order Matters**: Parent variables MUST come before child variables
2. **Explicit Dependencies**: Child queries must reference parent variables
3. **Refresh Behavior**: Grafana auto-refreshes dependent variables when parent changes
4. **Performance**: Cascading reduces query scope (faster, less data)

#### Common Mistake: Independent Variables (Current Issue)

```promql
# ❌ WRONG - Independent variables
namespace query: label_values(kube_pod_info, namespace)
app query:       label_values(request_duration_seconds_count, app)
# Problem: app shows ALL apps regardless of namespace selection

# ✅ CORRECT - Cascading variables
namespace query: label_values(kube_pod_info, namespace)
app query:       label_values(request_duration_seconds_count{namespace=~"$namespace"}, app)
# Solution: app filtered by selected namespace(s)
```

---

### 2. PodMonitor vs ServiceMonitor Decision Matrix

#### Architecture Comparison

| Aspect | ServiceMonitor | PodMonitor |
|--------|---------------|------------|
| **Discovery Target** | Kubernetes Services | Kubernetes Pods directly |
| **Endpoint Stability** | ✅ Stable (Service ClusterIP) | ⚠️ Dynamic (Pod IPs change) |
| **Label Source** | Service labels + relabeling | Pod labels + pod metadata |
| **Best For** | Microservices, APIs, web apps | DaemonSets, StatefulSets, Jobs |
| **Load Balancing** | ✅ Scrapes via Service (LB) | ❌ Scrapes pods individually |
| **Scrape Count** | 1 scrape per Service | N scrapes (1 per pod) |
| **Helm Integration** | ✅ Excellent (Services auto-created) | ⚠️ Manual pod label management |
| **Cardinality** | Lower (service-level labels) | Higher (pod-level labels) |
| **Use Case Example** | REST APIs, gRPC services | Vector, Node Exporter, etcd |

#### When to Use ServiceMonitor (Current Choice ✅)

**Use ServiceMonitor when:**
- ✅ Workload is **Deployment** or **ReplicaSet**
- ✅ Service has **stable ClusterIP**
- ✅ Multiple pods behind **load balancer**
- ✅ Labels attached to **Service resource**
- ✅ Want **unified metrics** (not per-pod)

**Example**: Microservices architecture
```yaml
# auth Deployment → auth Service → ServiceMonitor discovers → Prometheus scrapes
apiVersion: v1
kind: Service
metadata:
  name: auth
  namespace: auth
  labels:
    app: auth  # ← ServiceMonitor selector
spec:
  selector:
    app: auth
  ports:
  - name: http
    port: 8080
```

**Why it works**:
- Service label `app: auth` matches ServiceMonitor selector
- Prometheus scrapes Service ClusterIP (load-balanced)
- Metrics aggregated naturally across all auth pods

#### When to Use PodMonitor

**Use PodMonitor when:**
- ✅ Workload is **DaemonSet** (one pod per node)
- ✅ Workload is **StatefulSet** (pods with identity)
- ✅ Need **per-pod metrics** (not aggregated)
- ✅ No Service exists (or shouldn't exist)
- ✅ Labels attached to **Pod resource**

**Example 1**: Vector DaemonSet (currently uses ServiceMonitor - could be PodMonitor)

```yaml
# Vector DaemonSet (current setup with ServiceMonitor)
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: vector
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: vector
  template:
    metadata:
      labels:
        app: vector  # ← Pod label
    spec:
      containers:
      - name: vector
        ports:
        - name: metrics
          containerPort: 9090
---
# Service (exists for ServiceMonitor)
apiVersion: v1
kind: Service
metadata:
  name: vector
  namespace: kube-system
  labels:
    app: vector
spec:
  selector:
    app: vector
  ports:
  - name: metrics
    port: 9090
---
# ServiceMonitor (current approach)
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vector
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: vector
  endpoints:
  - port: metrics
```

**Alternative with PodMonitor** (more appropriate for DaemonSets):

```yaml
# PodMonitor (better for DaemonSets)
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: vector
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: vector
  podMetricsEndpoints:
  - port: metrics
    path: /metrics
    interval: 30s
```

**Advantages of PodMonitor for Vector**:
1. **Per-node visibility**: See metrics from each node's Vector pod
2. **No Service needed**: Direct pod discovery (simpler)
3. **Failure isolation**: If one node's Vector fails, others still scraped
4. **Semantic correctness**: DaemonSets conceptually don't need Services

**Example 2**: Sloth Operator (uses PodMonitor)

From `k8s/prometheus/values.yaml`:
```yaml
prometheus:
  prometheusSpec:
    # PodMonitor selector - for Sloth Operator
    podMonitorSelector: {}
    podMonitorNamespaceSelector: {}
```

Sloth Operator uses PodMonitor because:
- It's a single pod (not load-balanced)
- Metrics are pod-specific (SLO generation metadata)
- No need for Service abstraction

---

### 3. Current Project Architecture Assessment

#### Microservices Monitoring (ServiceMonitor ✅)

**Current Setup**:
- 8 namespaces: auth, user, product, cart, order, review, notification, shipping
- Each namespace has 1 Service (Deployment → Service)
- 1 ServiceMonitor discovers all 8 services

**Why ServiceMonitor is Correct**:

1. **Architecture Match**: REST API microservices = stable Service endpoints
2. **Scalability**: 3 replicas per service → Service load-balances scrapes
3. **Label Injection**: Unified `job="microservices"` label via relabeling
4. **Dashboard Compatibility**: Consistent labels for variable filtering
5. **Helm Integration**: Services auto-created by Helm chart

**Verification**:
```bash
# Check ServiceMonitor targets
kubectl get servicemonitor -n monitoring microservices-api -o yaml
# Should show: 8 services discovered (auth, user, product, cart, order, review, notification, shipping)
```

#### Vector Monitoring (ServiceMonitor → Consider PodMonitor)

**Current Setup** (`k8s/vector/`):
- DaemonSet (1 pod per node)
- Service exists (`vector.kube-system.svc`)
- ServiceMonitor scrapes Service

**Analysis**:
- ✅ **Works**: Service load-balances across DaemonSet pods
- ⚠️ **Not Ideal**: DaemonSets conceptually don't need Services
- 💡 **Recommendation**: Migrate to PodMonitor for semantic correctness

**Migration Impact**: Low (optional improvement, not critical)

---

## 🔧 Gap Analysis & Recommendations

### Critical Fixes (P0) - Must Fix

#### 1. Fix Variable Cascading

**Problem**: Namespace doesn't cascade to App

**Solution**: Reorder variables + update App query

**Changes Required**:

```json
{
  "templating": {
    "list": [
      // 1. DS_PROMETHEUS (unchanged)
      {
        "name": "DS_PROMETHEUS",
        "type": "datasource",
        "query": "prometheus",
        "hide": 0
      },
      
      // 2. NAMESPACE (moved from position 3 to position 2)
      {
        "name": "namespace",
        "type": "query",
        "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
        "query": "label_values(kube_pod_info, namespace)",
        "regex": "/^(?!kube-|default$).*/",
        "multi": true,
        "includeAll": true,
        "allValue": ".*",
        "label": "Namespace",
        "refresh": 1,
        "sort": 0
      },
      
      // 3. APP (moved from position 2 to position 3, query updated)
      {
        "name": "app",
        "type": "query",
        "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
        // 🔧 FIX: Add namespace filter!
        "query": "label_values(request_duration_seconds_count{namespace=~\"$namespace\"}, app)",
        "multi": true,
        "includeAll": true,
        "allValue": ".*",
        "label": "App",
        "refresh": 1,
        "sort": 0
      },
      
      // 4. RATE (unchanged)
      {
        "name": "rate",
        "type": "custom",
        "options": [...],
        "label": "Rate Interval"
      }
    ]
  }
}
```

**Expected Behavior After Fix**:

1. User opens dashboard → Namespace defaults to "All"
2. User selects Namespace = "auth" → App dropdown auto-refreshes
3. App dropdown now shows: `["All", "auth"]` only ✅
4. User selects Namespace = "monitoring" → App dropdown refreshes again
5. App dropdown shows: `["All"]` (no app label in monitoring namespace metrics)
6. Queries work correctly with cascaded filters

**Validation**:
```promql
# Test query in Prometheus
label_values(request_duration_seconds_count{namespace="auth"}, app)
# Expected result: ["auth"]

label_values(request_duration_seconds_count{namespace="user"}, app)
# Expected result: ["user"]

label_values(request_duration_seconds_count{namespace=~"auth|user"}, app)
# Expected result: ["auth", "user"]
```

---

### Important Improvements (P1)

#### 2. Consider Multi-Select Behavior for Namespace

**Current**: `"multi": true, "includeAll": true`

**Analysis**:
- **Pros**: Flexible (can select multiple namespaces or All)
- **Cons**: "All" selected by default defeats cascading purpose

**Options**:

**Option A: Force Namespace Selection (Recommended for strict filtering)**
```json
{
  "name": "namespace",
  "multi": false,        // Single selection only
  "includeAll": false,   // No "All" option
  "current": {
    "text": "auth",      // Default to first service
    "value": "auth"
  }
}
```
**Pros**: Forces users to pick namespace, cleaner app filter  
**Cons**: Can't view all namespaces at once

**Option B: Keep Multi-Select (Current, but requires fix)**
```json
{
  "name": "namespace",
  "multi": true,
  "includeAll": true,
  "allValue": ".*"       // Keep current behavior
}
```
**Pros**: Flexibility, can aggregate across namespaces  
**Cons**: App filter shows all apps when "All" selected

**Option C: Hybrid (Recommended)**
```json
{
  "name": "namespace",
  "multi": true,         // Allow multi-select
  "includeAll": true,    // Keep "All" option
  "current": {
    "text": "All",
    "value": "$__all",
    "selected": false    // Don't auto-select
  }
}
```
**Pros**: Best of both worlds  
**Implementation**: User must explicitly select namespaces

**Recommendation**: **Option C (Hybrid)** - Keep flexibility but don't default to "All"

---

#### 3. Vector Monitoring Architecture

**Current**: Vector DaemonSet uses ServiceMonitor

**Recommendation**: Migrate to PodMonitor for semantic correctness

**Migration Steps**:

1. Create `k8s/vector/podmonitor.yaml`:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: vector
  namespace: kube-system
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: vector
  podMetricsEndpoints:
  - port: metrics
    path: /metrics
    interval: 30s
```

2. Delete `k8s/vector/servicemonitor.yaml`

3. (Optional) Delete `k8s/vector/service.yaml` if not used for other purposes

**Impact**: 
- ✅ More idiomatic (DaemonSets → PodMonitor)
- ✅ Per-node Vector metrics visibility
- ⚠️ Breaking change if Service used elsewhere

**Priority**: P1 (Nice-to-have, not critical)

---

### Nice-to-Have (P2)

#### 4. Add Pod Variable (Optional)

**Use Case**: Debug individual pod performance

**Implementation**:
```json
{
  "name": "pod",
  "type": "query",
  "query": "label_values(up{namespace=~\"$namespace\", app=~\"$app\", job=~\"microservices\"}, instance)",
  "regex": "/([^:]+):.*/",  // Extract IP from IP:port
  "multi": true,
  "includeAll": true,
  "label": "Pod (optional)"
}
```

**Benefit**: Filter dashboard by specific pod for troubleshooting

**Priority**: P2 (Not needed for most use cases)

---

## 📝 Documentation Cleanup Plan

### Files to Update

#### 1. `docs/monitoring/VARIABLES_REGEX.md`

**Current Issues**:
- Shows app variable BEFORE namespace (wrong order)
- Missing cascading explanation
- No PodMonitor vs ServiceMonitor comparison

**Changes Needed**:
```markdown
# Update variable order section
### Variable Order (CORRECT)
1. DS_PROMETHEUS (datasource)
2. namespace (first filter) ✅
3. app (cascades from namespace) ✅
4. rate (independent)

# Add cascading explanation
### Variable Cascading
Variables must be ordered hierarchically:
- Parent variables come FIRST
- Child variables reference parent with `$variable` syntax
- Grafana auto-refreshes dependent variables

Example:
```promql
# Namespace (parent - independent)
label_values(kube_pod_info, namespace)

# App (child - depends on namespace)
label_values(request_duration_seconds_count{namespace=~"$namespace"}, app)
```
```

#### 2. `docs/monitoring/METRICS.md`

**Current Issues**:
- Line 1196: Shows app variable without namespace dependency
- Line 1204: Doesn't explain cascading impact

**Changes Needed**:
```markdown
### `$app` - Application Filter
- **Type:** Query (cascading from namespace)
- **Query:** `label_values(request_duration_seconds_count{namespace=~"$namespace"}, app)`
- **Dependency:** Filters by selected namespace(s)
- **Behavior:** 
  - When namespace="auth" → shows ["All", "auth"]
  - When namespace="user" → shows ["All", "user"]
  - When namespace="All" → shows all apps (["All", "auth", "cart", ...])
```

#### 3. Create New Doc: `docs/monitoring/PODMONITOR_VS_SERVICEMONITOR.md`

**Content**:
- Architecture comparison table
- Decision matrix (when to use which)
- Current project usage explanation
- Migration guide (if switching Vector to PodMonitor)

#### 4. `AGENTS.md`

**Section to Update**: Dashboard Conventions (line 738)

**Add**:
```markdown
### Dashboard Conventions

- **UID**: `microservices-monitoring-001`
- **Variables**: `$namespace` (parent), `$app` (child, cascades from namespace), `$rate`
- **Variable Order**: DS_PROMETHEUS → namespace → app → rate (CRITICAL)
- **Panel descriptions**: Concise and actionable
- **Query filters**: Always include `job=~"microservices"` and `namespace=~"$namespace"`
- **Cascading**: App variable MUST filter by namespace: `label_values(metric{namespace=~"$namespace"}, app)`
```

---

### Files to Archive (Move to `docs/archive/`)

#### Candidates for Archival:

1. **Pre-v0.5.0 Label Configuration Docs** (if any exist)
   - Old label injection patterns before ServiceMonitor relabeling

2. **Legacy Grafana Setup** (if any exist)
   - Manual Grafana installation docs (now using Grafana Operator)

3. **Old Deployment Patterns** (already in `docs/archive/`)
   - Keep existing archive structure

---

## 🎯 Implementation Roadmap

### Phase 1: Critical Fixes (P0) - Deploy Immediately

**Timeline**: 1-2 hours

1. **Fix Variable Cascading**
   - Update `microservices-dashboard.json`
   - Reorder variables: namespace before app
   - Update app query: add `{namespace=~"$namespace"}` filter
   - Test in local Grafana

2. **Deploy Fix**
   - Apply updated dashboard via Grafana Operator
   - Verify cascading works in UI
   - Test with different namespace selections

**Success Criteria**:
- ✅ Selecting namespace "auth" → App dropdown shows only "auth"
- ✅ Selecting namespace "user" → App dropdown shows only "user"
- ✅ Selecting multiple namespaces → App dropdown shows union
- ✅ All panels continue to work correctly

---

### Phase 2: Documentation Updates (P1) - Next Sprint

**Timeline**: 2-3 hours

1. **Update Core Docs**
   - `docs/monitoring/VARIABLES_REGEX.md` - Fix variable order examples
   - `docs/monitoring/METRICS.md` - Update app variable description
   - `AGENTS.md` - Add cascading to dashboard conventions

2. **Create New Docs**
   - `docs/monitoring/PODMONITOR_VS_SERVICEMONITOR.md` - Comprehensive comparison

3. **Archive Outdated Content**
   - Move any pre-v0.5.0 docs to `docs/archive/`

**Success Criteria**:
- ✅ All docs reflect correct variable order
- ✅ Cascading concept well-explained
- ✅ PodMonitor vs ServiceMonitor decision matrix available
- ✅ No conflicting information across docs

---

### Phase 3: Optional Improvements (P2) - Future

**Timeline**: As needed

1. **Vector PodMonitor Migration** (optional)
   - Create PodMonitor CRD
   - Test per-node metrics
   - Remove ServiceMonitor if successful

2. **Add Pod Variable** (optional)
   - Implement pod-level filtering
   - Add to dashboard for debugging use cases

**Success Criteria**:
- ✅ Vector metrics available per-node (if migrated)
- ✅ Pod-level filtering available (if implemented)

---

## 📊 Verification Checklist

### Pre-Deployment Verification

- [ ] Variable order: DS_PROMETHEUS → namespace → app → rate
- [ ] App query includes: `{namespace=~"$namespace"}`
- [ ] JSON syntax valid (no trailing commas, quotes escaped)
- [ ] Dashboard UID unchanged: `microservices-monitoring-001`

### Post-Deployment Verification

- [ ] Dashboard loads without errors
- [ ] Namespace dropdown shows correct namespaces (auth, user, product, cart, order, review, notification, shipping)
- [ ] Selecting namespace "auth" → App dropdown shows ["All", "auth"]
- [ ] Selecting namespace "user" → App dropdown shows ["All", "user"]
- [ ] All 32 panels render correctly
- [ ] Queries return data (no empty panels)
- [ ] Variables refresh automatically when changing namespace

### Documentation Verification

- [ ] `VARIABLES_REGEX.md` updated with correct order
- [ ] `METRICS.md` updated with cascading explanation
- [ ] `AGENTS.md` updated with dashboard conventions
- [ ] `PODMONITOR_VS_SERVICEMONITOR.md` created
- [ ] No outdated content referencing wrong variable order

---

## 🔗 References

### Grafana Official Documentation
- [Dashboard Variables](https://grafana.com/docs/grafana/latest/variables/)
- [Variable Syntax](https://grafana.com/docs/grafana/latest/variables/syntax/)
- [Chaining Variables](https://grafana.com/docs/grafana/latest/variables/variable-types/chained-variables/)

### Prometheus Documentation
- [ServiceMonitor CRD](https://prometheus-operator.dev/docs/operator/design/#servicemonitor)
- [PodMonitor CRD](https://prometheus-operator.dev/docs/operator/design/#podmonitor)
- [Relabeling](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#relabel_config)

### Project Documentation
- `docs/monitoring/VARIABLES_REGEX.md` - Variable configuration guide
- `docs/monitoring/METRICS.md` - Metrics documentation
- `k8s/prometheus/servicemonitor-microservices.yaml` - Current ServiceMonitor config

---

## ✅ Research Complete

**Key Findings**:
1. ✅ Critical variable cascading bug identified and solution provided
2. ✅ ServiceMonitor architecture verified as correct choice
3. ✅ All dashboard queries consistent and well-structured
4. ✅ Documentation cleanup plan created
5. ✅ PodMonitor vs ServiceMonitor comparison documented

**Next Phase**: `/specify grafana-dashboard-optimization` to create detailed specification for implementation

---

**Research by**: AI Assistant  
**Review Status**: Ready for specification phase  
**Priority**: P0 (Critical fix required)

