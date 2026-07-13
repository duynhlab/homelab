# ADR-002: Deploy Temporal via the alexandrevilain operator

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-06-15 | [RFC-0001](../../rfc/RFC-0001/) |

## Context

[ADR-001](../ADR-001-adopt-temporal-for-order-fulfillment/) commits us to running Temporal. We need
to deploy and operate a Temporal **server** (frontend/history/matching/worker services + Web UI +
schema management) in a Flux + Kustomize + OCI GitOps cluster, with persistence on our existing
CloudNativePG stack, scraped by VictoriaMetrics, and admitted by Kyverno (image-pin, probes,
resources, PSS). The platform is **operator-heavy** (CloudNativePG, Zalando, VictoriaMetrics,
Grafana, Sloth, Kyverno) — declarative CRDs reconciled by controllers.

## Decision

Deploy Temporal with the **[`alexandrevilain/temporal-operator`](https://github.com/alexandrevilain/temporal-operator)**,
installed as a Flux `HelmRepository` + `HelmRelease` (published chart `0.6.0`). Model the cluster as
a `TemporalCluster` CR and the namespace as a `TemporalNamespace` CR (`mop`). Persist to a dedicated
**CloudNativePG `temporal-db`** (default + `temporal_visibility` SQL stores), authenticating with the
**CNPG-generated `temporal-db-app`** secret via the CR's `passwordSecretRef`.

**Server version is pinned to `1.24.2`, with `1.27.x` as the target** (see Consequences).

## Alternatives considered

### Official `temporalio/helm-charts` `temporal` chart
- **Pros:** The canonical install; broad configuration surface; tracks the latest server.
- **Cons:** Helm-template config rather than a declarative CRD; doesn't fit the platform's
  operator-per-capability model; schema setup/upgrade is via Helm hooks (awkward under Flux,
  `useHelmHooks: false` needed). No CRD-level `TemporalCluster`/`TemporalNamespace` abstraction.
- **Rejected (kept as documented fallback):** The operator's declarative CRD model fits our GitOps
  better. The official chart is noted in the guide as the alternative if we ever outgrow the operator.

### Vendoring the operator's v0.22.0 release manifests
- **Pros:** Gets the newest operator (server range `<1.29.0`, i.e. supports 1.27.x) immediately.
- **Cons:** ≈5k lines of vendored CRDs committed to the repo; no Renovate tracking; manual re-vendor
  + Kyverno-patching on every upgrade.
- **Rejected:** Loses the clean Helm/Renovate upgrade path for a version we can reach later.

### `alexandrevilain/temporal-operator` via published Helm chart (chosen)
- **Pros:** Declarative CRDs, fits operator-heavy GitOps, cert-manager-issued webhook certs, emits a
  `ServiceMonitor`, Renovate-trackable `HelmRepository`, clean upgrades.
- **Cons:** The **published chart caps the operator at v0.20.0**, which supports Temporal server
  `>=1.14.0 <1.25.0` only — so we cannot run 1.27.x via the chart yet. No native auto-scaling or
  multi-cluster replication.
- **Accepted:** The GitOps fit + clean upgrade path outweigh running one minor server version behind.

## Consequences

- **Server pinned to `1.24.2`** (the operator's own postgres example version; satisfies the
  `<1.25.0` cap). **Target `1.27.x`** — unblocked when the operator **re-publishes its Helm chart for
  v0.22.0** (server range extends to `<1.29.0`); Renovate watches the `HelmRepository` and will
  surface it. This is a one-line `version:` bump when it lands.
- **Accepted gaps** (fine for a single-cluster homelab): no operator-native auto-scaling of the
  Temporal services; no multi-cluster replication.
- **Persistence** is a dedicated CNPG `temporal-db` (single instance for now; HA + Barman backups are
  a follow-up). Credentials are the CNPG-generated `temporal-db-app` secret — no hand-managed
  password, nothing in Git.
- **Kyverno** is satisfied by setting resources on every operator-created pod (services/ui/admintools/
  schema-jobs) in the CR; probes are operator-managed.
- Manifests live in `kubernetes/infra/{controllers,configs}/temporal/`; see the
  [implementation guide §6](../../../api/temporal-order-fulfillment.md#6-infrastructure).

---
_Last updated: 2026-06-26_
