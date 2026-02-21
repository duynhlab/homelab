# Grafana Dashboard Variables & Regex Patterns

## Quick Summary

**Objectives:**
- Understand Grafana dashboard variables and their configuration
- Learn regex patterns for filtering and transforming variable values
- Configure dynamic filtering for multi-service dashboards

**Learning Outcomes:**
- Dashboard variable types (datasource, query, custom)
- Regex patterns for variable transformation
- Multi-select and include-all options
- Label value extraction from Prometheus metrics

**Keywords:**
Grafana Variables, Dashboard Variables, Regex Patterns, Label Values, Multi-select, Filtering, Dynamic Dashboards

**Technologies:**
- Grafana (dashboard variables)
- PromQL (label extraction)
- Regular Expressions

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
Query: label_values(request_duration_seconds_count{namespace=~"$namespace"}, app)
Purpose: Filter by application name
Default: All
Include All: true
Multi-select: true
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
  - (auto-discover new apps)
```

**Label Source (v0.5.0+):**
> **Note**: The `app` label is automatically added by Prometheus during scrape from the pod's `app` label via ServiceMonitor relabel_configs. Applications do not emit this label themselves.

**Usage in queries:**
```promql
# Example: RPS
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$rate]))

# When "All" selected: app=~".*", namespace=~".*"
# When specific app: app=~"auth", namespace=~"auth"
# Multi-select: app=~"auth|user", namespace=~"auth|user"
```

---

### 3️⃣ **$namespace** (Namespace Filter)
```yaml
Type: query
Query: label_values(request_duration_seconds_count, namespace)
Purpose: Filter by Kubernetes namespace
Default: All (service namespaces: auth, user, product, etc., and monitoring)
Include All: true
Multi-select: true
Regex: /^(?!kube-|default$).*/

Options:
  - auth
  - user
  - product
  - monitoring
  - (any user namespaces, excluding system ones)
```

**Label Source (v0.5.0+):**
> **Note**: The `namespace` label is automatically added by Prometheus during scrape from the pod's namespace via ServiceMonitor relabel_configs. Applications do not emit this label themselves.

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

### 4️⃣ **$rate** (Rate Interval)
```yaml
Type: custom
Values: 1m, 2m, 3m, 5m, 10m, 30m, 1h, 2h, 4h, 8h, 16h, 1d, 2d, 3d, 5d, 7d
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
/^monitoring-.*/

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
2. **Add regex filters** to exclude system namespaces
3. **Enable "Include All"** for aggregate views
4. **Document regex patterns** (like this file!)
5. **Use multi-select** for namespace and app filters when needed

### ❌ DON'T:
1. Hardcode namespace names in queries
2. Show system namespaces to end users
3. Use overly complex regex (keep it readable)
4. Forget to set default values
5. Forget that $app cascades from $namespace selection

---

## 🔄 Variable Dependencies

Variables have dependencies (cascading filters):

```
$DS_PROMETHEUS (independent)
    ↓
$namespace (independent)
    ↓
$app (filters by namespace - cascades from $namespace)
    ↓
$rate (independent)
```

**Example Flow:**
1. Select namespace: `auth`, `user`, `product`, etc. (service-specific) or `monitoring` (for monitoring components)
2. App dropdown refreshes → shows: `auth`, `user`, `product`, etc. (filtered by selected namespace)
3. Select app(s): `auth` (can select multiple apps)
4. Queries update automatically with selected namespace and app filters

---

## 🛠️ Troubleshooting

### Variable shows no options
**Problem:** Dropdown is empty
**Solution:** 
- Check Prometheus is running
- Verify metric exists: `request_duration_seconds_count`
- Check namespace filter isn't too restrictive
- Verify namespace variable is set correctly (affects app variable)

### Regex not working
**Problem:** Namespaces still showing when they shouldn't
**Solution:**
- Test regex at https://regex101.com
- Ensure format: `/pattern/` (with slashes)
- Check Grafana version (regex syntax varies)

### Multi-select not working
**Problem:** Can't select multiple namespaces/apps
**Solution:**
- Check `"multi": true` in variable config
- Verify queries use `=~` not `=`
- Ensure `includeAll: true` is set for proper "All" option

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

### Exclude monitoring namespaces (if needed):
```regex
/^(?!.*monitoring|.*prometheus).*/
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

**Last Updated:** 2026-01-05
**Dashboard Version:** 1.0
**Author:** DevOps Team

