# ClickHouse runtime audit evidence

Dated, sanitized evidence for claims that cannot be proved from manifests
alone.

| Quick facts | |
|---|---|
| **Scope** | ClickHouse, Keeper, OTel ingest, storage lifecycle, alert expressions |
| **Environment** | Fresh local Kind cluster with an isolated `KUBECONFIG` |
| **Raw output** | Temporary and untracked; secrets are redacted |
| **Durable record** | One Markdown summary per audit date and Git SHA |

## Evidence rules

- Record the source SHA, runtime versions, start/end time, and architecture.
- Separate manifest facts from live observations.
- Record every replica when the claim is replica-sensitive.
- Use `inconclusive` when a bounded observation window expires.
- Do not promote query compatibility to alert-firing evidence.
- Never record passwords, DSNs, Secret values, or complete environment dumps.

## Audits

- [2026-09-10 Kind audit](2026-09-10-kind.md) — rollout, seeded traffic,
  merge/TTL/cold-tier drills, 22 alert rules, runbook mapping, and PostgreSQL
  boundary checks.

## References

- [ClickHouse operations](../operations.md)
- [ClickHouse alert runbooks](../../runbooks/clickhouse/README.md)

---
_Last updated: 2026-09-10 — linked the first repeatable Kind evidence record._
