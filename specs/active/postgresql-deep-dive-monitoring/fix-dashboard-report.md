# Dashboard Remediation Report

**Date:** 2026-01-29

## 1. Dashboard: PostgreSQL Queries Overview
**File:** `kubernetes/infra/configs/monitoring/grafana/dashboards/pg-query-overview.json`

We identified and resolved three distinct classes of errors preventing this dashboard from displaying data for CloudNativePG and Zalando clusters.

### A. PromQL Syntax Error (Invalid Range Vector)
**Panel:** "Time spent in queries in last hour (top 50)"
*   **Issue:** The `increase()` function was applied *after* `sum()`. This is syntactically invalid because `sum()` returns an instant vector, while `increase()` expects a range vector.
*   **Error:** `bad_data: invalid parameter "query": 1:200: parse error: ranges only allowed for vector selectors`
*   **Fix Applied:** Reordered the functions to apply `increase` before `sum`.
    ```diff
    - increase(sum(pg_stat_statements_time_milliseconds{...}) by (query,queryid,user)[1h])
    + sum by (query,queryid,user) (increase(pg_stat_statements_time_milliseconds{...}[1h]))
    ```

### B. LogQL "Empty Matcher" Error
**Panel:** "Latest logs with long running queries"
*   **Issue:** When dashboard variables (like `$Pod`) selected all values, the resulting query filter effectively became empty, which Loki rejects for performance safety.
*   **Error:** `queries require at least one regexp or equality matcher that does not have an empty-compatible value`
*   **Fix Applied:** Added a non-empty matcher (`container!=""`) and ensured regex matching (`=~`) is used correctly.
    ```diff
    - {namespace="$namespace",pod="$Pod"}
    + {namespace=~"$namespace",pod=~"$Pod",container!=""}
    ```

### C. Missing Data due to Selector Mismatch
**Panels:** "Top Shared Blocks Dirtied", "Top Shared Blocks Read", "Top Shared Blocks Written", "Top Shared Block Cache Hits"
*   **Issue:** These panels used `instance="$host"` as a selector. The `$host` variable (IP:Port) often fails to align with Prometheus series labels in Kubernetes. Other working panels used pod names.
*   **Fix Applied:** Standardized selectors to match the rest of the dashboard.
    ```diff
    - instance="$host"
    + kubernetes_namespace="$namespace",kubernetes_pod_name="$Pod"
    ```

---

## 2. Dashboard: PostgreSQL Query Drill-Down
**File:** `kubernetes/infra/configs/monitoring/grafana/dashboards/pg-query-drilldown.json`

We audited this dashboard following user reports of "only numbers" being displayed and concerns about validity.

### A. Metric Validity (Confirmed)
*   **Status:** ✅ Valid
*   **Verification:** We manually executed the underlying SQL queries (from `monitoring-queries.yaml`) in the `auth-db` pod.
*   **Result:** Data is returned correctly with all expected columns (`queryid`, `query`, `calls`, `total_exec_time`). The dashboard uses standard `pg_stat_statements` metrics compatible with PostgreSQL 16.

### B. "Only Numbers" Visualization (Explained)
*   **Observation:** The "Query Calls" panel legend displays numbers (e.g., `5057477...`) instead of query names.
*   **Explanation:** This is a deliberate design choice in the dashboard configuration:
    *   `"legendFormat": "{{queryid}} - {{datname}}"`
*   **Context:** Displaying full SQL queries in a graph legend would render it unreadable. The "numbers" are the **Query IDs** (hashes). The full query text is available in the **"Queries overview"** dropdown or the text panel at the top of the dashboard.

---

## 3. Post-Mortem and Verification: PostgreSQL Dashboard Fixes

### 3.1 Overview of Issues
We identified multiple critical issues preventing the Grafana dashboards from displaying data correctly:
- **PromQL Syntax Errors**: `increase()` was used incorrectly after `sum()`, causing parse errors.
- **LogQL Regex Errors**: Empty matchers in LogQL queries caused failures when variables were set to "All".
- **Selector Mismatches**: Queries relied on `instance="$host"`, which does not align with our Kubernetes-based metric labels (`kubernetes_namespace`, `kubernetes_pod_name`).
- **Missing Variables**: The Drill-Down dashboard lacked `namespace` and `Pod` variables, making it impossible to filter by cluster or pod properly.
- **JSON Corruption**: During the fix process, we encountered and resolved duplicate key errors in the dashboard JSON file.

### 3.2 Changes Implemented

#### PostgreSQL Queries Overview Dashboard (`pg-query-overview.json`)
- **Fixed PromQL**: Reordered `sum(increase(...))` to `sum(rate(...))` or `increase(sum(...))` where appropriate (actually `sum by ... (increase(...))` is generally safer, but we fixed the syntax specific to the error `ranges only allowed for vector selectors`).
- **Fixed LogQL**: Updated query to use regex matching `~= "$variable"` and added `container!=""` to avoid empty matchers.
- **Selector Update**: Replaced `instance` selectors with `kubernetes_namespace="$namespace",kubernetes_pod_name="$Pod"` across key panels.

#### PostgreSQL Query Drill-Down Dashboard (`pg-query-drilldown.json`)
- **Variable Injection**: Injected `namespace` and `Pod` variables into the `templating` section.
- **Variable Chaining**: Configured `Pod` to depend on `namespace`, and `queryid` to depend on `namespace` + `Pod`.
- **Panel Updates**: Replaced all 20+ occurrences of `instance="$host"` and `instance=~"$host"` with `kubernetes_namespace="$namespace",kubernetes_pod_name="$Pod"` (and regex variants).
- **JSON Cleanup**: Removed duplicate variable definitions that were causing lint errors.

### 3.3 Verification Steps

#### Automated Checks
- **JSON Linting**: The final files are valid JSON.
- **Selector Verification**: A grep search confirms `kubernetes_namespace` is present in all target panels.

#### Manual Verification Required (User Action)
To fully verify the fix, please perform the following in the Grafana UI:
1.  **Navigate to "PostgreSQL Queries Overview"**:
    *   Select a **Namespace** (e.g., `default` or `monitoring`).
    *   Select a **Pod** (e.g., `product-db-1`).
    *   Verify data appears in "Most time consuming queries".
2.  **Navigate to "PostgreSQL Query Drill-Down"**:
    *   Select the same **Namespace** and **Pod**.
    *   Select a **Query ID** from the dropdown (it should now populate).
    *   Verify charts like "Query Execution Time" and "Shared Blocks" show data.
3.  **Check Logs Panel**: Ensure the "Latest logs" panel is showing logs without "parse error".

### 3.4 Conclusion
The dashboards are now aligned with the underlying metric labels provided by the `postgres_exporter` and `CloudNativePG` setup. The variables are correctly chained, ensuring a smooth drill-down experience.
