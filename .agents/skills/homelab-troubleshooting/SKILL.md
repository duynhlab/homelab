---
name: homelab-troubleshooting
description: >-
  Diagnose and recover homelab platform incidents and clean up stray
  debug/troubleshooting notes in the docs. Routes a symptom or firing alert to
  the owning runbook, enforces evidence-first read-only diagnosis before any
  state change, and consolidates durable findings into their authoritative home
  without erasing historical evidence. Use when a homelab alert fires, a
  Kustomization or HelmRelease is NotReady, a service returns 5xx or is slow, a
  database/pod/edge/secret is failing, or when asked to tidy, audit, or
  consolidate debug notes, troubleshooting notes, or known-issue scribbles in
  docs. Not for application code (owned by service repos) or new runbook alerts
  without a backing rule.
---

# Homelab troubleshooting

Route a homelab symptom to its **owning runbook**, diagnose from cheapest
evidence first, and keep what you learn in the one place that already owns it.
This skill does not reproduce procedures — it points at them and guards the
boundaries.

Read [platform-engineer](../platform-engineer/SKILL.md) first for repo scope and
the `make validate` gate. Application code lives in service repos; `docs/api/`
is the API source of truth.

## Pick the entry mode

| You have | Mode | Start at |
|----------|------|----------|
| A firing alert with an `alertname` | **Alert-led** | grep `docs/observability/runbooks/**/<AlertName>.md`; else [runbook index](../../../docs/observability/runbooks/README.md) |
| A user-visible symptom, no alert | **Symptom-led** | the domain row below → its symptom hub |
| A known task (rotate, unseal, add DB, promote) | **Task-led** | [databases/runbooks](../../../docs/databases/runbooks/README.md) or [secrets/runbooks](../../../docs/secrets/runbooks/README.md) |
| "Does it still work?" (pre-tag, regression) | **Qualification** | [kind-e2e-audit](../../../docs/platform/kind-e2e-audit.md), [k6](../../../docs/testing/k6.md) — not an incident |
| Messy debug notes in docs | **Cleanup** | [references/docs-hygiene.md](references/docs-hygiene.md) |

## Non-negotiables

1. **Evidence before action.** Default to read-only. Establish scope (service,
   namespace, cluster, time window) and gather signal before changing anything.
   Full rules: [references/triage-and-safety.md](references/triage-and-safety.md).
2. **Stop at state changes.** Failover, DR promotion, PITR, destructive SQL,
   credential revocation, and any live non-GitOps edit need explicit approval
   and route through the owning runbook — never a first reflex.
3. **Never `kubectl apply` over Flux.** Fix in Git, `make validate`,
   `make flux-push`, then reconcile. A live edit is reverted on next reconcile.
4. **An empty vector is not a healthy zero.** Confirm the signal exists and its
   labels are current before tuning a threshold ([evidence-correlation](references/evidence-correlation.md)).
5. **Don't invent a procedure.** A missing `runbook_url` or index row is a
   recorded gap. Report it ([docs-hygiene](references/docs-hygiene.md)); do not
   fabricate steps.
6. **Current vs historical.** Envoy Gateway and VictoriaTraces/ClickHouse are
   current; Kong, Tempo, and Jaeger docs are historical — ignore them unless the
   request is explicitly about migration history.

## Domain routing

One incident has one primary domain. Open the matching file for authoritative
docs, manifests, safe commands, and the escalation boundary.

| Domain | Entry signals | Routing file |
|--------|---------------|--------------|
| GitOps / delivery | `Flux*`, wave NotReady, nothing converging | [references/domains/gitops-delivery.md](references/domains/gitops-delivery.md) |
| Alerts / SLO | any `alertname`, burn-rate page | [references/domains/observability-alerts.md](references/domains/observability-alerts.md) |
| Telemetry pipeline | missing metrics/logs/traces, collector/Vector | [references/domains/observability-pipeline.md](references/domains/observability-pipeline.md) |
| Edge / identity | `Edge*`, `EnvoyGateway*`, `Keycloak*`, 401/404/429 | [references/domains/edge-and-identity.md](references/domains/edge-and-identity.md) |
| Applications | `Microservice*`, 5xx, slow, saga/outbox | [references/domains/applications.md](references/domains/applications.md) |
| PostgreSQL / CNPG | `CNPG*`, `PgDog*`, outage, corruption | [references/domains/data-postgresql.md](references/domains/data-postgresql.md) |
| CDC / analytics / cache | CDC freshness, `Valkey*`, `ClickHouse*` | [references/domains/data-cdc-analytics.md](references/domains/data-cdc-analytics.md) |
| Secrets / TLS | ExternalSecret NotReady, cert issuance | [references/domains/secrets-tls.md](references/domains/secrets-tls.md) |
| Security / admission / net | `Kyverno*`, admission deny, blocked despite healthy pods | [references/domains/security-admission-net.md](references/domains/security-admission-net.md) |
| Kubernetes substrate | `Kube*`, CrashLoop, OOM, PVC | [references/domains/kubernetes-infra.md](references/domains/kubernetes-infra.md) |
| Temporal / KEDA | `Temporal*`, `Keda*`, stuck workflow | [references/domains/applications.md](references/domains/applications.md#temporal--keda) |

## Workflow

1. **Intake** — read the alert/symptom; capture labels, value, time window.
2. **Route** — pick the mode and domain above; open the owning doc.
3. **Verify signal** — series fresh, labels current, impact real
   ([evidence-correlation](references/evidence-correlation.md)).
4. **Diagnose** — bounded PromQL/LogsQL/kubectl/SQL, cheapest first, each with a
   namespace and an expected result.
5. **Mitigate** — most reversible first; destructive steps need approval and
   their runbook ([triage-and-safety](references/triage-and-safety.md)).
6. **Verify recovery** — alert predicate false for two intervals **and** the
   user symptom gone (drain/replica/queue checks, not just an instantaneous 0).
7. **Record** — put durable findings in their owning runbook/hub; keep dated
   evidence with its record ([docs-hygiene](references/docs-hygiene.md)).

For a fix that edits manifests, follow [platform-engineer's gates](../platform-engineer/SKILL.md#verification-and-release)
and [git-commits](../git-commits/SKILL.md). Diagrams stay Mermaid (AGENTS.md).

## References

- [references/triage-and-safety.md](references/triage-and-safety.md) — command classes, approval gates, SQL/Flux/DR guardrails.
- [references/domain-routing.md](references/domain-routing.md) — the four entry modes in depth and how to choose.
- [references/evidence-correlation.md](references/evidence-correlation.md) — metrics → traces → logs → profiles, the manual `trace_id` pivot.
- [references/docs-hygiene.md](references/docs-hygiene.md) — retain / promote / move / remove disposition for debug notes.
