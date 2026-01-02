# Troubleshooting: Zalando Postgres Operator Issues

## Issue 1: Pod Labels Error

# Troubleshooting: Zalando Postgres Operator "Pod Labels Error"

## Problem

Error message:
```
could not create cluster: pod labels error: still failing after 200 retries
failed to create cluster: pod labels error: still failing after 200 retries
```

## Root Cause Analysis

### Investigation Findings

1. **Error Timing**: Error occurred during initial cluster creation (04:48:49)
2. **Operator Configuration**: 
   - `pod_label_wait_timeout: 10m` - Operator waits up to 10 minutes for pod labels
   - `cluster_labels: application: spilo` - Applied to all cluster objects
   - `cluster_name_label: cluster-name` - Label key for cluster name
   - `pod_role_label: spilo-role` - Label key for pod role (master/replica)

3. **Current Status**: 
   - Cluster eventually recovered and is now `Running`
   - All pods are `2/2 Ready` and running
   - Operator logs show "cluster has been synced"

### Root Cause

The "pod labels error: still failing after 200 retries" occurs when:

1. **Race Condition**: Operator tries to verify pod labels before StatefulSet controller has applied them
2. **Timeout Issue**: Operator's `pod_label_wait_timeout` (10m) may be insufficient during heavy cluster load
3. **Label Validation**: Operator validates that required labels (`spilo-role`, `cluster-name`, `application`) are present on pods, but there's a timing window where labels aren't set yet

## Resolution

### Automatic Recovery

The cluster typically recovers automatically:
- Operator retries label verification
- StatefulSet eventually applies all labels correctly
- Cluster reaches `Running` state

### Manual Intervention (if needed)

If cluster doesn't recover automatically:

```bash
# 1. Check cluster status
kubectl get postgresql auth-db -n auth

# 2. Check pod labels
kubectl get pods -n auth -l application=spilo --show-labels

# 3. Verify required labels are present:
# - application=spilo
# - cluster-name=auth-db
# - spilo-role=master (for leader) or missing (for replicas)
# - team=platform

# 4. If labels are missing, delete and recreate cluster
kubectl delete postgresql auth-db -n auth
kubectl wait --for=delete postgresql/auth-db -n auth --timeout=300s
kubectl apply -f k8s/postgres-operator/zalando/crds/auth-db.yaml
```

## Prevention

### Option 1: Increase Timeout (Recommended)

Update operator configuration to increase `pod_label_wait_timeout`:

```yaml
# k8s/postgres-operator/zalando/values.yaml
configTimeouts:
  pod_label_wait_timeout: 15m  # Increase from default 10m
```

Then upgrade operator:
```bash
helm upgrade postgres-operator postgres-operator/postgres-operator \
  -f k8s/postgres-operator/zalando/values.yaml \
  -n database
```

### Option 2: Verify Node Resources

Ensure nodes have sufficient resources to schedule pods quickly:

```bash
# Check node resources
kubectl top nodes

# Check if nodes are under pressure
kubectl describe nodes | grep -A 5 "Allocated resources"
```

### Option 3: Check for Label Conflicts

Verify no existing resources have conflicting labels:

```bash
# Check for existing StatefulSets with same labels
kubectl get statefulset -A -l cluster-name=auth-db

# Check for existing pods with same labels
kubectl get pods -A -l cluster-name=auth-db
```

## Related Configuration

### Operator Label Settings

From `k8s/postgres-operator/zalando/values.yaml`:

```yaml
configKubernetes:
  cluster_labels:
    application: spilo  # Applied to all cluster objects
  cluster_name_label: cluster-name  # Label key for cluster name
  pod_role_label: spilo-role  # Label key for pod role
```

### Required Pod Labels

Pods must have these labels:
- `application=spilo` (from `cluster_labels`)
- `cluster-name=<cluster-name>` (from `cluster_name_label`)
- `spilo-role=master` (for leader, from `pod_role_label`)
- `team=<teamId>` (from CRD `teamId` field)

## Monitoring

### Check Cluster Health

```bash
# Check cluster status
kubectl get postgresql -A

# Check pod status
kubectl get pods -n auth -l application=spilo

# Check operator logs for errors
kubectl logs -n database -l app.kubernetes.io/name=postgres-operator --tail=100 | grep -i error
```

### Check Replica Status

```bash
# Connect to leader pod
kubectl exec -it auth-db-0 -n auth -- /bin/bash

# Check Patroni status
patronictl list
```

---

## Issue 2: Replica Cannot Connect - "no pg_hba.conf entry for replication connection"

### Problem

Replicas fail to initialize with error:
```
pg_basebackup: error: connection to server at "10.244.1.5", port 5432 failed: FATAL:  no pg_hba.conf entry for replication connection from host "10.244.3.10", user "standby", no encryption
ERROR: failed to bootstrap from leader 'auth-db-0'
```

Cluster status shows:
- Leader: `running`
- Replicas: `creating replica` or `stopped` (stuck)

### Root Cause

**pg_hba.conf Missing Replication Entries:**

1. **Replication entries not configured**: CRD's `patroni.pg_hba` section missing replication entries for `standby` user
2. **Reject rule blocks replication**: `hostnossl all all all reject` rule blocks non-SSL replication connections (replicas need non-SSL for basebackup)
3. **Order matters**: Replication entries must come **BEFORE** reject rules in pg_hba.conf

### Resolution

**Fix pg_hba.conf in CRD:**

Update `k8s/postgres-operator/zalando/crds/auth-db.yaml`:

```yaml
patroni:
  pg_hba:
    # Local connections (required for Patroni)
    - local     all          all                        trust
    - local     replication  standby                    trust
    
    # Replication connections (MUST be before reject rules)
    # Allow non-SSL replication from pod network (required for basebackup)
    - host      replication  standby   10.244.0.0/16    md5
    - host      replication  standby   172.19.0.0/16    md5
    - host      replication  standby   10.0.0.0/8       md5
    # Allow SSL replication (preferred)
    - hostssl   replication  standby   all              md5
    
    # Application connections from internal network
    - host      all          all       10.0.0.0/8       trust
    - host      all          all       127.0.0.1/32     md5
    - host      all          all       ::1/128          md5
    
    # SSL connections (zalandos users use PAM)
    - hostssl   all          +zalandos 127.0.0.1/32     pam
    - hostssl   all          +zalandos ::1/128          pam
    - hostssl   all          +zalandos all              pam
    
    # Reject non-SSL connections (except those allowed above)
    - hostnossl all          all       all              reject
    
    # All other SSL connections require md5 password
    - hostssl   all          all       all              md5
```

**Apply the fix:**

```bash
# 1. Apply updated CRD
kubectl apply -f k8s/postgres-operator/zalando/crds/auth-db.yaml

# 2. Wait for operator to update Patroni config (check logs)
kubectl logs -n database -l app.kubernetes.io/name=postgres-operator --tail=50 | grep "patching Postgres config"

# 3. Trigger PostgreSQL reload (if needed)
kubectl exec -n auth auth-db-0 -- curl -s -X PATCH http://localhost:8008/config \
  -H "Content-Type: application/json" -d '{"postgresql": {"parameters": {}}}'

# 4. Monitor replica status
kubectl exec -n auth auth-db-0 -- patronictl list
```

**Note**: PostgreSQL will automatically reload pg_hba.conf when Patroni config is updated. If replicas still fail, wait a few minutes for retry.

### Prevention

**Always include replication entries in pg_hba.conf:**

1. **Local replication**: `local replication standby trust`
2. **Network replication (non-SSL)**: `host replication standby <CIDR> md5` (for basebackup)
3. **Network replication (SSL)**: `hostssl replication standby all md5` (preferred)
4. **Order**: Replication entries **MUST** come before `hostnossl ... reject` rule

**Example minimal pg_hba.conf for HA:**

```yaml
patroni:
  pg_hba:
    - local     all          all                        trust
    - local     replication  standby                    trust
    - host      replication  standby   10.244.0.0/16    md5  # Pod network
    - hostssl   replication  standby   all              md5  # SSL replication
    - host      all          all       10.0.0.0/8       trust
    - hostnossl all          all       all              reject
    - hostssl   all          all       all              md5
```

---

## Issue 3: Connection Pooler Memory Limit Warning

### Problem

Operator logs show warning:
```
memory limit of 100Mi for "connection-pooler" container is increased to match memory requests of 128Mi
```

### Root Cause

Connection pooler resources configuration has `requests.memory: 128Mi` but no `limits.memory`, causing operator to auto-increase limit and show warning.

### Resolution

**Fix connectionPooler resources in CRD:**

```yaml
connectionPooler:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 128Mi  # Set limit to match request to avoid warning
```

**Apply the fix:**

```bash
kubectl apply -f k8s/postgres-operator/zalando/crds/auth-db.yaml
```

The warning will disappear after operator syncs the cluster.

---

## References

- [Zalando Postgres Operator Documentation](https://github.com/zalando/postgres-operator)
- Operator Configuration: `k8s/postgres-operator/zalando/values.yaml`
- Cluster CRD: `k8s/postgres-operator/zalando/crds/auth-db.yaml`
- [PostgreSQL pg_hba.conf Documentation](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)