# ADR-014: PgDog pooler credentials via Flux valuesFrom targetPath

Remove the four inline cleartext user passwords from the `pgdog-cnpg`
HelmRelease and inject each one at reconcile time from the per-service ESO
basic-auth Secret, using Flux `valuesFrom` with a list-indexed `targetPath`
(`users[N].password`).

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-07-08 | [RFC-0012](../../rfc/RFC-0012/) |

> **Don't forget: every decision is a tradeoff.** Record what you gave up, not just
> what you gained.

## Context

RFC-0012's stated goal is *zero database credentials in Git*, and its debt
inventory named `instance.yaml`'s `postInitSQL`. The audit for P2 found a
second, wider leak the RFC had missed: the PgDog HelmRelease
(`clusters/cnpg-db/poolers/helmrelease.yaml`) carried **all four** service
passwords inline in `values.users[]` — product and payment included, not just
cart/order. A comment demanded they be kept manually in sync with PostgreSQL
and the OpenBAO seed: a three-way sync-by-hand.

This also coupled to P2's password rotation: rotating any password in OpenBAO
without touching the pooler values would leave PgDog authenticating upstream
with a dead password — every pooled service breaks on its next new connection.
The pooler had to move to a secret-sourced mechanism *before or with* the
rotation, and the pgdog chart (v0.39) has no `passwordFromSecret`-style values
of its own.

Flux's helm-controller offers `spec.valuesFrom`: entries reference a
Secret/ConfigMap key and can place that single value at an arbitrary path in
the rendered values using Helm strvals notation — which supports list indices
(`users[1].password`). The referenced Secrets must live in the HelmRelease's
namespace; all four ESO basic-auth Secrets and the HelmRelease share
`product`. One caveat: helm-controller reads `valuesFrom` content at
reconcile time only — it does not watch the Secrets — so a rotation must be
followed by an explicit `flux reconcile helmrelease pgdog-cnpg`.

## Decision

We will strip `password` from every entry in `values.users[]` and add four
`spec.valuesFrom` entries, one per service, each pulling the `password` key
of that service's ESO basic-auth Secret into `users[N].password`:

```yaml
valuesFrom:
  - { kind: Secret, name: cnpg-db-secret,         valuesKey: password, targetPath: "users[0].password" }
  - { kind: Secret, name: cnpg-db-cart-secret,    valuesKey: password, targetPath: "users[1].password" }
  - { kind: Secret, name: cnpg-db-order-secret,   valuesKey: password, targetPath: "users[2].password" }
  - { kind: Secret, name: cnpg-db-payment-secret, valuesKey: password, targetPath: "users[3].password" }
```

Indices are positional against `values.users[]`; both lists carry a comment
pinning the order (product, cart, order, payment). These are the same Secrets
the `DatabaseRole`s consume (ADR-013), so pooler and PostgreSQL can only ever
disagree between a rotation and the next HelmRelease reconcile — a window the
rotation runbook closes explicitly
([rotate-cnpg-service-password](../../../databases/runbooks/rotate-cnpg-service-password.md)).

The change lands *with* the P2 rotation PR but is a behavioral no-op at merge
time: the Secrets still hold the old passwords until the OpenBAO seed re-runs,
so `valuesFrom` renders values identical to the removed inline ones.

## Alternatives considered

- **Keep inline values, update them in the rotation PR** — preserves the
  status quo mechanics but re-commits the new passwords to Git, failing the
  RFC's core goal; and the three-way manual sync remains. Rejected.
- **Wait for upstream chart support (`passwordFromSecret`)** — the clean
  long-term shape (pgdog reads Secrets natively, no reconcile-time coupling),
  but it does not exist in v0.39 and rotation could not wait. Revisit trigger
  below. Rejected for now.
- **Single aggregate Secret (`pgdog-cnpg-credentials`) templating the whole
  `users` block** — one `valuesFrom` without `targetPath`, but it duplicates
  the per-service passwords into a second OpenBAO entry (two sources of truth
  per credential) and ESO templating of a YAML-structured values fragment is
  brittle. Rejected.
- **PgDog auth passthrough / trust between pooler and PostgreSQL** — removes
  pooler credentials entirely but weakens the auth story (the pooler becomes
  a credential-less bypass) and conflicts with P4's per-pair `pg_hba`
  SCRAM rules. Rejected.

## Consequences

- No database credential remains in any HelmRelease value; the pooler follows
  OpenBAO automatically at each reconcile.
- **Rotation gains one mandatory step:** `flux reconcile helmrelease
  pgdog-cnpg -n product` after the Secrets update — helm-controller does not
  watch `valuesFrom` sources. Encoded in the runbook; forgetting it leaves
  PgDog on the old password until the next 10m interval reconcile.
- **Positional coupling:** inserting a user mid-list without renumbering the
  `targetPath` indices mis-assigns passwords. Mitigated by the pinned-order
  comments; the add-a-service recipe (P3) appends at the end.
- The stale `pgdog-cnpg-credentials` ESO Secret (admin creds the chart never
  consumed) is now clearly dead — removed in P3 cleanup.
- **Revisit trigger:** pgdog chart shipping native Secret-sourced user
  passwords; move to it and drop `valuesFrom`.
