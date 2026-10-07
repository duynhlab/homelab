# ADR-004: Enable OpenBAO audit logging

Enable an OpenBAO audit device so every secret access is recorded and queryable.

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-06-29 | — |

## Context

The secrets tier underpins database, backup, and TLS credentials, so "who read
which secret, when?" must be answerable for forensics and for compliance-style
controls (SOC2/HIPAA expect an audit trail of secret access). OpenBAO supports
**audit devices** that emit one structured record per authenticated
request/response, with sensitive values HMAC-hashed by default. The platform
already ships container stdout to **VictoriaLogs** via the cluster-wide Vector
DaemonSet, so an audit stream can ride that existing pipeline with no new
infrastructure.

## Decision

We enable a **`file` audit device writing to `stdout`** in the OpenBAO bootstrap
(`bao audit enable file file_path=stdout`). The records are collected by Vector
and stored in VictoriaLogs, queryable in Grafana alongside every other log. This
gives an immediate, searchable audit trail using infrastructure we already run.

## Alternatives considered

- **Durable file device backed by an `auditStorage` PVC** — survives pod loss
  independently of the log pipeline. *Deferred:* heavier for a homelab; the
  stdout→VictoriaLogs path is enough today. Revisit for production.
- **Socket / syslog audit device** — streams to an external SIEM. *Rejected for
  now:* more moving parts and an external dependency we don't have locally.
- **No audit logging** — *Rejected:* leaves secret access unobservable, a
  forensics and compliance gap.

## Consequences

- Secret access is auditable in VictoriaLogs/Grafana; values are HMAC-hashed.
- **Known limitation (honest):** enablement is currently **best-effort** in the
  bootstrap — the command's failure is swallowed (`… 2>/dev/null || echo …`) and
  `auditStorage` is disabled, so a silently-absent audit device would not fail the
  bootstrap or alert. Making audit **fail-closed** and durable is a production
  hardening item tracked in the production-secrets-hardening RFC.
- **Revisit trigger:** moving to a production cluster, or any compliance
  requirement for guaranteed, tamper-evident, durable audit storage.

---

<!-- Append-only: supersede with a new ADR rather than rewriting this one. -->
