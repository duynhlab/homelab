# Triage and safety

Evidence-first diagnosis, and the gate between reading and changing state.

## Scope first

Before any command, pin the scope from the alert labels or the symptom report:

- **Service / workload**, **namespace**, **cluster** (local Kind vs prod).
- **Time window** — `startsAt`, when the symptom began, recent deploys.
- **Blast radius** — one pod, one wave, one domain, or the whole edge.

A command without a namespace and an expected result is noise. Name both.

## Command classes

| Class | Examples | Rule |
|-------|----------|------|
| **Read-only** | `kubectl get/describe`, `kubectl logs --tail`, PromQL/LogsQL, `kubectl cnpg status`, read-only SQL with timeouts | Default. Always bound output and add timeouts/limits. |
| **Reversible (Kind only)** | `flux reconcile`, scaling a UI deployment, uniquely named temporary test objects | State the rollback and use unique names. Not on prod without approval. |
| **Destructive / incident-only** | HA failover, DR promotion, PITR, drop replication slot, PVC delete, credential revoke | Explicit user approval. Route through the owning runbook. Never run as a documentation test. |
| **Secrets** | root token use, KV writes, compromise revoke | Never echo secret values. Prefer staff-OIDC paths over root/ceremony. |
| **Git / cluster delivery** | `make flux-push`, manifest edits | Diagnosis-first skill; implementation follows platform-engineer gates + `make validate`. |

## Approval gates

Pause and get explicit approval before:

- **Database state changes** — failover, promote DR replica, PITR, or editing a
  CNPG `Cluster`. Availability and integrity incidents diverge: HA/DR
  **replicates** a bad write, so only PITR undoes corruption. Start at
  [emergency-recovery.md](../../../../docs/databases/runbooks/emergency-recovery.md);
  the IC owns the go/no-go, not the first responder.
- **Live non-GitOps edits** — never `kubectl apply`/`edit` over a
  Flux-owned object. It is reverted on the next reconcile and leaves the
  cluster disagreeing with Git. Fix in Git → `make validate` → `make flux-push`
  → `flux reconcile`. If you must edit live mid-incident, `flux suspend` the
  owning Kustomization first and reconcile the commit afterwards.
- **Secret material** — rotation, revocation, or writing KV. Follow
  [secrets/runbooks](../../../../docs/secrets/runbooks/README.md); do not copy
  local floci/recovery-key practices to prod.

## PostgreSQL interactive-session header

Start any read-only diagnosis session with the bounded header from
[databases/observability-and-troubleshooting.md](../../../../docs/databases/observability-and-troubleshooting.md#safe-session-header):

```sql
SET application_name = 'sre-readonly-diagnosis';
SET statement_timeout = '5s';
SET lock_timeout = '1s';
SET idle_in_transaction_session_timeout = '30s';
```

Read-only catalog queries still consume CPU and locks. Filter by database,
schema, relation, state, or time, and limit the result.

## Flux-specific traps

- `gotk_resource_info` carries `True` / `False` / `Unknown`. A *progressing*
  wave sits at `Unknown` and never pages. Confirm with the object, not silence:
  `kubectl get kustomization -A | grep -v ' True '`.
- A `dependency '<x>' is not ready` message means the problem is upstream —
  follow the chain to its head before touching the symptom wave.
- A cold bring-up produces transient `False` that clears on retry; that is
  bring-up noise, not an incident. Persisting across retries is real.

## Recovery criteria

- The original user/operator symptom is gone, not only the alert predicate.
- Backlogs, replica lag, and queues are **draining**, not flat at an
  instantaneous zero.
- Roles are as expected (primary/replicas, worker versions).
- The rule is inactive for two evaluation intervals.
- Any temporary diagnostic object, schema, or session is removed.

## Escalation evidence

Capture Git SHA, component versions, labels, timeline, the bounded queries and
their output, and sanitized logs. Never attach credentials, full connection
strings, Secret objects, or unbounded query text from other tenants.
