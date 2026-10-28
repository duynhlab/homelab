# Entry modes

Four ways an operator arrives, and the authoritative document each starts at.
Pick the mode first; it decides which template and which owner applies.

## 1. Alert-led

You have a firing alert with an `alertname` label.

1. Grep the runbook tree for the exact name:
   `rg -l '<AlertName>' docs/observability/runbooks` or open
   `docs/observability/runbooks/<domain>/<AlertName>.md`.
2. Follow the per-alert runbook in the order of
   [`_TEMPLATE.md`](../../../../docs/observability/runbooks/_TEMPLATE.md):
   Meaning → Impact → Safety → Diagnosis (cheapest first) → Mitigation
   (most reversible first) → Recovery validation → Escalation.
3. No file for a real alert = a recorded gap. Use the
   [alert catalog](../../../../docs/observability/alerting/alert-catalog.md) for
   severity/impact and report the gap; do not invent steps.

SLO burn-rate pages are the exception: they have **no** per-alert tree. Route
through [slo-burn-rate-alerts.md](../../../../docs/observability/alerting/slo-burn-rate-alerts.md)
to the owning service, not a RED runbook.

## 2. Symptom-led

A user-visible symptom with no alert (or the alert is not trustworthy yet).

1. Match the symptom to a domain in the SKILL.md routing table.
2. Open that domain file's symptom hub (e.g. the edge symptom table, the DB
   symptom map, the Vector troubleshooting section).
3. Verify the signal chain before concluding
   ([evidence-correlation.md](evidence-correlation.md)) — a "service down" with
   a dead exporter is a telemetry incident, not an app incident.

## 3. Task-led

A known operational task (rotate a password, unseal OpenBAO, add a service DB,
promote DR). These are **procedural** runbooks, not alert runbooks — they do not
use `_TEMPLATE.md`.

- Databases: [databases/runbooks/README.md](../../../../docs/databases/runbooks/README.md).
- Secrets: [secrets/runbooks/README.md](../../../../docs/secrets/runbooks/README.md).

Confirm the current deployed state first — some documented features are planned,
not enabled locally.

## 4. Qualification

"Does it still work?" — pre-tag, post-fix, or regression proof. This is **not**
an incident path.

- [kind-e2e-audit](../../../../docs/platform/kind-e2e-audit.md) — the cluster gate (K0–K6).
- [local-stack e2e-audit](../../../../local-stack/docs/e2e-audit.md) — the Compose twin.
- [k6 assertion layer](../../../../docs/testing/k6.md) — `make e2e GATE=compose|kind`.
- [telemetry-kind-verification](../../../../docs/observability/runbooks/telemetry-kind-verification.md) — signal qualification.

Use qualification to **validate a recovery**, kept separate from the incident
triage itself.
