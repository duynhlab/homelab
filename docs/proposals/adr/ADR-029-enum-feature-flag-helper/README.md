# ADR-029: Adopt `pkg/flagx` as the platform feature-flag helper

Adopt a shared, startup-validated env-flag helper (`pkg/flagx`) for runtime
rollout gates instead of per-service `os.Getenv` parsing.

| Status | Date | Related RFC | Related research |
|--------|------|-------------|------------------|
| Accepted | 2026-07-24 | [RFC-0021](../../rfc/RFC-0021/) | [RFC-0021 research.md](../../rfc/RFC-0021/research.md) |

## Context

RFC-0021 migrates stock authority from product-service to a new inventory-service
through reversible, flag-gated steps: a read-path selector
(`CHECKOUT_AVAILABILITY_SOURCE` = `product|shadow|inventory`), a shadow sampling
percentage, and later a write-path participant (`ORDER_STOCK_PARTICIPANT`). Each
gate must be **reversible by a one-line manifest edit** and **fail loudly on a bad
value** — a typo'd rollout flag silently defaulting to the wrong mode is exactly
the failure a migration cannot afford.

Before this, services read runtime toggles with raw `os.Getenv`: no validation
(an unknown value falls through to a default or an empty string), the parsing is
copy-pasted per service, and an operator typo (`shaddow`) surfaces as wrong
behavior in production rather than a startup error. The platform also runs
everything as plain env in Flux-managed manifests (GitOps), so flags are already
version-controlled and rolled back by PR — what was missing was a validated,
uniform way to read them.

## Decision

We will use **`pkg/flagx`** as the single feature-flag helper for all services.
It provides:

- `Enum(name, def, allowed…)` / `MustEnum(…)` — an env value constrained to a
  fixed set; the `Must` variant `log.Fatal`s at startup on an invalid value.
- `Percent(name, def)` / `MustPercent(…)` — an integer `0..100` for sampling
  (e.g. shadow-traffic percentage), same fail-fast contract.

Flags are read once at startup into config and passed into the logic layer; a
validated enum is a **bounded value by construction**, so it is safe to use as a
metric label without cardinality risk. The first runtime consumers are
checkout-service's `CHECKOUT_AVAILABILITY_SOURCE` and
`CHECKOUT_AVAILABILITY_SHADOW_PCT` (RFC-0021 P2-4); future phases add
`ORDER_STOCK_PARTICIPANT` (P3) on the same helper.

## Alternatives considered

- **Per-service `os.Getenv` parsing (status quo).** Pros: no shared dependency.
  Cons: no validation (typos default silently), duplicated logic, inconsistent
  fail behavior, unbounded values leaking into metric labels. Rejected — the
  migration's whole safety story rests on flags failing loud and reversing
  cleanly.
- **A dynamic feature-flag service/SDK (LaunchDarkly, Unleash, OpenFeature).**
  Pros: runtime flips without restart, targeting rules, audit UI. Cons: a new
  external dependency and control plane, flags no longer live in the GitOps
  manifest (rollback stops being "revert the PR"), and it is far more than a
  handful of migration gates need. Rejected as overkill for this platform's
  restart-to-apply, manifest-as-source-of-truth posture.

## Consequences

- Rollout gates are uniform: one-line manifest env change to flip, `git revert`
  to roll back, and a mis-typed value crashes the pod at startup instead of
  running the wrong path.
- Validated enums double as safe (bounded) metric labels — e.g.
  `inventory_shadow_compare_total{result}` needs no allow-listing.
- **Trade-off:** flags are read at process startup, so a change requires a pod
  restart (rolling restart via Flux) — there is no dynamic in-process flip. This
  is acceptable for coarse rollout gates and keeps the manifest the single source
  of truth. **Revisit trigger:** if a future need arises for per-request or
  no-restart dynamic flags, reopen this ADR toward a dynamic flag provider
  (OpenFeature) for that specific use case.
- `pkg/flagx` becomes a supported shared package; new flags across services
  should use it rather than re-introducing raw `os.Getenv` parsing for toggles.

---

_Last updated: 2026-07-24_
