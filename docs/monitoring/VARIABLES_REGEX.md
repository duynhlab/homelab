# Grafana Dashboard Variables & Regex Patterns

## 📊 Dashboard Variables Overview

Dashboard này sử dụng **4 variables động** để filter và customize metrics display:

### 1️⃣ **$DS_PROMETHEUS** (Datasource)
```yaml
Type: datasource
Query: prometheus
Purpose: Select Prometheus datasource
Default: Prometheus
```

### 2️⃣ **$app** (Application Filter)
```yaml
Type: query
Query: label_values(request_duration_seconds_count, app)
Purpose: Filter by application name
Default: All
Include All: true
Multi-select: false
Regex: (none) - shows all apps

Options:
  - All (shows combined metrics from all apps)
  - auth
  - user
  - product
  - cart
  - order
  - review
  - notification
  - shipping
  - shipping-v2
  - (auto-discover new apps)
```

**Usage in queries:**
```promql
# Example: RPS
sum(rate(request_duration_seconds_count{app=~"$app"}[$rate]))

# When "All" selected: app=~".*"
# When specific app: app=~"auth"
```

---

### 3️⃣ **$namespace** (Namespace Filter)
```yaml
Type: query
Query: label_values(kube_pod_info, namespace)
Purpose: Filter by Kubernetes namespace
Default: All (service namespaces: auth, user, product, etc., and monitoring)
Include All: false
Multi-select: false
Regex: /^(?!kube-|default$).*/

Options:
  - auth
  - user
  - product
  - monitoring
  - (any user namespaces, excluding system ones)
```

**Regex Breakdown:**
```regex
/^(?!kube-|default$).*/

^                    # Start of string
(?!                  # Negative lookahead (exclude patterns)
  kube-              # Anything starting with "kube-"
  |                  # OR
  default$           # Exactly "default"
)
.*                   # Match everything else
```

**Excluded namespaces:**
- `kube-system`
- `kube-public`
- `kube-node-lease`
- `default`

**Usage in queries:**
```promql
# Example: Pod restarts
sum(kube_pod_container_status_restarts_total{namespace=~"$namespace"})
```

---

### 4️⃣ **$pod** (Pod Filter) ⭐ NEW
```yaml
Type: query
Query: label_values(kube_pod_info{namespace=~"$namespace"}, pod)
Purpose: Filter by specific pods
Default: All
Include All: true
Multi-select: true (can select multiple pods)
Regex: /^(?!.*prometheus|.*grafana|.*kube-state|.*metrics-server).*/
Sort: Alphabetical (1)

Options:
  - All
  - auth-xxx-yyy
  - user-xxx-yyy
  - product-xxx-yyy
  - (auto-discover pods in selected namespace)
```

**Regex Breakdown:**
```regex
/^(?!.*prometheus|.*grafana|.*kube-state|.*metrics-server).*/

^                        # Start of string
(?!                      # Negative lookahead
  .*prometheus           # Exclude pods with "prometheus" in name
  |
  .*grafana              # Exclude pods with "grafana" in name
  |
  .*kube-state           # Exclude kube-state-metrics
  |
  .*metrics-server       # Exclude metrics-server
)
.*                       # Match everything else
```

**Excluded pods:**
- `prometheus-*`
- `grafana-*`
- `kube-state-metrics-*`
- `metrics-server-*`

**Result:** Chỉ hiển thị **application pods** (auth, user, product, etc.)

**Usage in queries:**
```promql
# Example: RPS per pod
sum(rate(request_duration_seconds_count{
  app=~"$app",
  kubernetes_pod_name=~"$pod"
}[$rate])) by (kubernetes_pod_name)

# Multi-select example:
# When selected: auth-xxx, auth-yyy
# Result: kubernetes_pod_name=~"auth-xxx|auth-yyy"
```

---

### 5️⃣ **$rate** (Rate Interval)
```yaml
Type: custom
Values: 1m, 5m, 10m, 30m, 1h
Purpose: Time window for rate() and increase() functions
Default: 5m
```

**Usage in queries:**
```promql
# Example: Request rate
sum(rate(request_duration_seconds_count{app=~"$app"}[$rate]))

# When $rate = 5m
# Actual query: rate(...[5m])
```

---

## 🎯 Common Regex Patterns

### **1. Exclude Patterns (Negative Lookahead)**
```regex
# Exclude prefixes
/^(?!kube-|system-).*/

# Exclude suffixes
/^(?!.*-test$|.*-dev$).*/

# Exclude contains
/^(?!.*debug|.*temp).*/

# Exclude exact match
/^(?!default$|kube-system$).*/
```

### **2. Include Patterns**
```regex
# Only production
/.*-prod$/

# Only specific prefix
/^demo-.*/

# Only versions
/.*(v1|v2|v3)$/

# Only running status
/.*Running.*/
```

### **3. Extract Patterns**
```regex
# Extract version from "app-v2"
/.*-(v\d+)$/

# Extract environment from "app-prod-us"
/.*-([a-z]{2,4})$/

# Extract region
/.*-(us|eu|asia)-.*/
```

### **4. Complex Combinations**
```regex
# Production apps, not test, in specific regions
/^.*-service.*-(us|eu)(?!.*-test).*/

# Version 2+ only
/.*(v[2-9]|v\d{2,})$/

# Specific format: app-env-region
/^[a-z]+-[a-z]+-[a-z]{2}$/
```

---

## 📝 Best Practices

### ✅ DO:
1. **Use variables** instead of hardcoding names
2. **Add regex filters** to exclude system/monitoring pods
3. **Enable "Include All"** for aggregate views
4. **Document regex patterns** (like this file!)
5. **Use multi-select** for pod/node filters

### ❌ DON'T:
1. Hardcode namespace names in queries
2. Show system namespaces to end users
3. Use overly complex regex (keep it readable)
4. Forget to set default values
5. Mix monitoring pods with app pods in dropdowns

---

## 🔄 Variable Dependencies

Variables have dependencies (cascading filters):

```
$DS_PROMETHEUS (independent)
    ↓
$namespace (independent)
    ↓
$app (filters by namespace - optional)
    ↓
$pod (filters by namespace + app)
    ↓
$rate (independent)
```

**Example Flow:**
1. Select namespace: `auth`, `user`, `product`, etc. (service-specific) or `monitoring` (for monitoring components)
2. App dropdown refreshes → shows: `auth`, `user`, `product`, etc.
3. Select app: `auth`
4. Pod dropdown refreshes → shows only auth pods
5. Queries update automatically

---

## 🛠️ Troubleshooting

### Variable shows no options
**Problem:** Dropdown is empty
**Solution:** 
- Check Prometheus is running
- Verify metric exists: `kube_pod_info`, `request_duration_seconds_count`
- Check namespace filter isn't too restrictive

### Regex not working
**Problem:** Pods/namespaces still showing when they shouldn't
**Solution:**
- Test regex at https://regex101.com
- Ensure format: `/pattern/` (with slashes)
- Check Grafana version (regex syntax varies)

### Multi-select not working
**Problem:** Can't select multiple pods
**Solution:**
- Check `"multi": true` in variable config
- Verify queries use `=~` not `=`

---

## 📚 References

- [Grafana Variables Docs](https://grafana.com/docs/grafana/latest/variables/)
- [Prometheus Query Basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Regex Quick Reference](https://regex101.com)

---

## 🚀 Quick Copy-Paste Patterns

### Exclude system namespaces:
```regex
/^(?!kube-|default$).*/
```

### Exclude monitoring pods:
```regex
/^(?!.*prometheus|.*grafana).*/
```

### Only service apps (if using -service suffix):
```regex
/^.*-service.*/
```

### Production only:
```regex
/.*-prod$/
```

### Version 2+:
```regex
/.*(v[2-9]|v\d{2,})$/
```

---

**Last Updated:** 2025-10-14
**Dashboard Version:** 1.0
**Author:** DevOps Team

