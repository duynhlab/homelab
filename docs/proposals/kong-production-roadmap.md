> ⚠️ **SUPERSEDED (2026-07-10).** This review predates the JWT migration — the
> opaque-token/GetMe ground truth it analyzes no longer exists. Superseded by
> **RFC-0009 Phase 4/5 (jwt-edge live, ADR-006)**. Kept for historical context only.

# Production-Grade Kong — Evaluation & Roadmap (read-only)

> **Status:** review / finding — **pre-RFC, nothing to implement here.** A deep,
> educational evaluation of how to take this platform's Kong usage toward what
> mature companies run, *honestly bounded by what Kong OSS can actually do*.
> Companion to [`auth-gateway-review.md`](auth-gateway-review.md).
>
> _Every item is a tradeoff — this doc names both sides and never silently picks._
> Reviewed 2026-06-30 (homelab `main` + service repos), grounded by 3 review
> agents + Kong's official plugin docs. External sources cited by name only.

---

## 0. TL;DR

- **Your current gateway is already a sound, "thin" production posture — not
  "just basic usage."** You deliberately keep Kong pass-through, validate auth in
  services (zero-trust), keep gRPC east-west only, fence `internal` with
  NetworkPolicy, run 2 replicas, and manage everything declaratively via Flux.
  Those are *exactly* the production-grade choices — and they avoid the classic
  gateway **anti-patterns** (business logic at the edge, sole-authz at the edge,
  perimeter trust). Don't mistake "few plugins" for "immature."
- **"Use Kong like big companies" is not simply 'turn on more plugins.'** Two
  hard walls stand in the way:
  1. **You run Kong OSS (`plugins: "bundled"`)** — the marquee enterprise plugins
     (**OpenID Connect, oauth2-introspection, mTLS-auth, OPA, request-validator,
     canary, all `-advanced`**) are **not in the OSS binary at all**.
  2. **Your tokens are opaque + ADR-003 keeps auth in services** — so OSS edge
     auth (`jwt`) doesn't even apply (there's no signed JWT to verify).
- **So the roadmap splits cleanly into:** (A) **quick OSS wins you can do now**
  with no architectural change, and (B) **decision-gated moves** that need an
  RFC/ADR (token model, edge auth, authz, mTLS, Enterprise-vs-alternative).
- **The single most concrete gap is security, not features:** your
  monitoring/infra/MCP ingresses (**Grafana, OpenBAO UI, Postgres UI, Flux UI,
  RustFS, the MCP endpoints**) are exposed with **no auth, no rate-limit, no IP
  allowlist** — only the global plugins. Fixing that is Phase 0.

---

## 1. Where you already match production best-practice (keep these)

| Production principle | This platform | Verdict |
|---|---|---|
| Gateway is **thin** (route/protect/observe, no business logic) | Kong pass-through, `strip-path:false`, aggregation done server-side | ✅ correct |
| **Zero-trust**: services re-validate, don't trust the perimeter | `pkg/authmw` validates every `/private/` via `auth.GetMe`; fail-closed | ✅ correct |
| `internal` fenced by **network policy**, not "absence of a route" | NetworkPolicy authored (caveat: kindnet doesn't enforce it) | ✅ posture right, enforcement gap |
| **Declarative / GitOps** config, not hand-edited admin API | Admin API disabled; KongPlugin/Ingress CRDs via Flux | ✅ correct |
| **HA** gateway | 2 replicas + PDB | ✅ correct |
| **TLS termination** with managed certs | cert-manager LE wildcard `kong-proxy-tls` | ✅ correct |
| gRPC kept **east-west only**, HTTP/JSON north-south | hard rule in `grpc-internal-comms.md` | ✅ correct (a deliberate, defensible choice) |
| **No `:latest`**, resource limits, fingerprint suppression | enforced | ✅ correct |

You are not "yếu kém" here — this is a better baseline than many real teams ship.
The growth is in **observability propagation, edge security on admin surfaces,
resilience, and a few deliberate architectural decisions** — below.

---

## 2. The two walls (read before wishing for plugins)

### Wall 1 — OSS `bundled` vs Enterprise

`plugins: "bundled"` (your `helmrelease.yaml:37`) ships the OSS set only. Enterprise
plugins **fail to load** in this binary. The split that matters:

| Capability | OSS (you have it) | Enterprise-only (you don't) | OSS workaround |
|---|---|---|---|
| AuthN | key-auth, **jwt**, basic-auth, hmac-auth, ldap-auth, session(cookie), acl | **openid-connect, oauth2-introspection, mtls-auth, ldap-auth-advanced, jwt-signer** | app-side OIDC / front with Keycloak; `jwt` if you adopt signed JWTs |
| AuthZ | acl (consumer groups) | **opa**, request-validator | in-app authz / OPA sidecar you run yourself |
| Rate limit | rate-limiting (`local`/`redis`), response-ratelimiting | **rate-limiting-advanced** (sliding window, namespaces) | `redis` policy with the Valkey you already run |
| Caching | proxy-cache (in-memory, per-node) | **proxy-cache-advanced** (Redis-backed) | in-memory proxy-cache (fine for public GETs) |
| Transform | request/response-transformer (static) | **`-advanced`** (regex/templating) | static transforms |
| Traffic split | weighted upstream **targets** (core) | **canary**, route-by-header | weighted targets, or Argo Rollouts / Flagger at deploy layer; Route `headers` matching (core) |
| Security | ip-restriction, bot-detection, cors, request-size-limiting, acme | (full WAF) | external WAF / CDN, or a Coraza/ModSecurity sidecar |
| Observability | **prometheus, opentelemetry, zipkin**, http/file-log, datadog, statsd | — | already OSS-complete |
| Routing/LB | upstreams, targets, active+passive health checks (core) | — | core |

### Wall 2 — opaque tokens + ADR-003

Edge authentication on OSS Kong means the **`jwt` plugin verifying a signed
JWT**. Your auth-service issues **opaque** session tokens (no signature) validated
by a stateful `auth.GetMe` lookup. Therefore:

- OSS `jwt` plugin **cannot** validate your token (nothing to verify).
- The "introspect the opaque token at the edge" option = Kong's
  **`oauth2-introspection`** plugin = **Enterprise-only**.
- So **edge auth is currently impossible on OSS for your token model** — which is
  *fine*, because ADR-003 deliberately keeps auth in the services anyway.

> **The central architectural fork** (Phase 2): if you want edge auth "like the
> tutorials," you must first pick a token model — keep opaque (then edge auth
> needs Kong Enterprise or an external IdP), or migrate to **signed JWT** (then
> OSS `jwt` works, but you trade instant revocation for statelessness and take on
> key management). This is a token/IdP decision, not a Kong toggle.

### DB-less landmines (you run `database: "off"`)

- **Never use the `cluster` rate-limit policy** (needs a datastore) → use `local`
  (per-node, approximate) or **`redis`** (accurate, needs Valkey on the hot path).
- **`oauth2` (Kong-as-authorization-server) doesn't work** DB-less (can't persist
  tokens) — don't try to make Kong your IdP.
- **Consumers + credentials must be declared in the decK/config**, not created at
  runtime. So any consumer-based plugin (key-auth, acl, per-consumer rate tiers)
  means managing consumer entities in Git.
- **proxy-cache & health-check state are per-node** (no shared store) in OSS.

---

## 3. Use-case → plugin map, applied to *this* platform

Production capability, the Kong mechanism, OSS feasibility, and whether it fits
*your* conventions. (Capabilities you already avoid-as-anti-pattern are marked.)

| Use-case | Kong mechanism | OSS? | Fits here? | Tradeoff / note |
|---|---|---|---|---|
| TLS termination | core + cert-manager | ✅ | **have it** | cleartext on internal hop → drives mTLS question |
| Routing / discovery | Ingress→Service (KIC) | ✅ | **have it** | K8s DNS; no Consul needed |
| Rate limit (basic) | rate-limiting | ✅ | **have it (api-* only)** | extend to admin/mon ingresses; move to `redis` for true cluster-wide count |
| Request-size cap | request-size-limiting | ✅ | **have it** | — |
| CORS / sec-headers / correlation-id | cors, response-transformer, correlation-id | ✅ | **have it** | — |
| **Distributed tracing propagation** | **opentelemetry** | ✅ | **gap — high value** | Kong emits no spans today → edge→service trace gap; OSS plugin feeds your Tempo/OTel; cost = sampling/cardinality |
| **IP allowlist on admin UIs** | ip-restriction | ✅ | **gap — highest security value** | OpenBAO/pgui/Flux/MCP exposed with no control; brittle with dynamic IPs but cheap first fence |
| Edge caching (public GETs) | proxy-cache (in-mem) | ✅ | **fits — public only** | per-node cache, lost on restart; **never cache `/private/`** (cross-user leak); invalidation is the hard part |
| Maintenance / kill-switch | request-termination | ✅ | **fits — easy win** | emit your `{error,code}` envelope for consistency |
| Active health-checks + retries + timeouts | core Upstream/Target | ✅ | **gap — resilience** | needs net-new `KongUpstream` CRDs; state per-node; retries only on idempotent methods (storm risk) |
| Header-based routing | core Route `headers` | ✅ | optional | the OSS substitute for the Enterprise route-by-header |
| Weighted canary | upstream targets weights | ✅ (basic) | optional | overlaps your Flux/GitOps deploy; per-request canary needs mesh/Enterprise; consider Argo Rollouts/Flagger instead |
| Request transformation (headers) | request/response-transformer | ✅ | fits (minimal) | body/path rewrite would **break pass-through** — don't |
| **Edge authentication** | jwt / openid-connect / oauth2-introspection | jwt OSS; OIDC+introspection **Ent** | **conflicts (Wall 2 + ADR-003)** | opaque token ⇒ no OSS edge auth; needs token-model or Enterprise decision |
| **Edge authorization (RBAC)** | acl / opa | acl OSS; opa **Ent** | **conflicts (no authz anywhere)** | needs a platform-wide authz model first; gateway-only authz is an anti-pattern anyway |
| Request schema validation | request-validator | **Ent** | low value | services already validate + own the error envelope; edge schema drifts |
| mTLS to upstream | mtls-auth / mesh | **Ent** / mesh | **defer** | couple to RFC-0002 (east-west mTLS); don't duplicate PKI in Kong |
| WAF | (none bundled) | **needs external** | future | use a CDN/edge WAF or Coraza sidecar; full WAF in-gateway adds latency/ops |
| gRPC at edge (transcode/grpc-web) | grpc-gateway / grpc-web | ✅ | **N/A by design** | gRPC is east-west only here; no north-south gRPC use case |
| API versioning | path `/v1/` (service-owned) | ✅ | **have it** | pass-through already supports `/v2` alongside |
| Metrics | prometheus | ✅ | **have it** | watch label cardinality |
| Structured access logs | http-log/file-log (or current stdout→Vector) | ✅ | **have it** (stdout→Vector→VictoriaLogs) | sampling/PII redaction at scale |

---

## 4. Concrete gaps in *this* platform (ranked)

1. **🔴 Admin/observability/MCP surfaces exposed with no auth/limit.** Grafana,
   **OpenBAO UI**, **Postgres operator UI**, Flux UI, RustFS console, and the MCP
   endpoints are reachable through Kong with only global plugins — no auth, no
   rate-limit, no IP allowlist. This is the biggest real risk.
2. **🟠 Edge→service trace gap.** Kong emits no spans / doesn't propagate W3C
   `traceparent`, so distributed traces start at the service, not the edge — a
   blind first hop despite a full Tempo/OTel/Jaeger stack.
3. **🟠 No authorization anywhere.** AuthN only; `auth.GetMe` returns no roles.
   Every authenticated user can call any `/private/` route they reach.
4. **🟡 Rate-limit coverage + accuracy.** Only `api-*` ingresses are limited
   (mon/infra/MCP are not), and `policy: local` under-counts ×replicas.
5. **🟡 No edge resilience.** No active health-checks / retries / timeouts /
   circuit-breaking at the gateway (north-south); routing is plain Ingress→Service.
6. **🟡 Doc accuracy (from the auth review).** Docs say "JWT"; tokens are opaque
   — fix terminology + supersede ADR-003's rationale.

---

## 5. Phased roadmap (options, not commitments)

### Phase 0 — Quick OSS wins, no architecture change (config PRs)
| Move | Plugin | Value | Tradeoff |
|---|---|---|---|
| Lock down admin/mon/MCP ingresses | **ip-restriction** (+ rate-limit) | closes the #1 risk | brittle with dynamic IPs; pair with a real auth story later |
| Close the trace gap | **opentelemetry** (W3C, OTLP→collector) | end-to-end traces | sampling + cardinality cost |
| Cache public reads | **proxy-cache** on `/…/public/` GETs only | latency + upstream load | per-node, restart-cold; never on `/private/` |
| Maintenance switch | **request-termination** (with `{error,code}` body) | safe sunset/maintenance | — |
| Accurate, broader rate-limit | rate-limiting **`redis`** (Valkey) + apply to mon/infra | true cluster-wide limits everywhere | Valkey on the hot path (availability coupling) |

### Phase 1 — Resilience & hygiene (small net-new config)
| Move | Mechanism | Tradeoff |
|---|---|---|
| Active+passive health-checks, retries, timeouts | core `KongUpstream`/targets | net-new CRDs; per-node state; retry storms if unbounded |
| Tighten `trusted_ips` from `0.0.0.0/0` | Kong config | correctness vs convenience behind port-forward |
| Fix doc terminology JWT→opaque + supersede ADR-003 | docs + new ADR | (from the auth review) |

### Phase 2 — Architectural decisions (need an RFC/ADR; pick consciously)
| Fork | Options (each a tradeoff) |
|---|---|
| **Token model** | keep **opaque** (revocable, stateful, no OSS edge auth) **vs** signed **JWT** (stateless edge verify via OSS `jwt`, harder revocation + key mgmt) |
| **Edge auth** | none (current, valid) **vs** OSS `jwt` (needs JWT model) **vs** Kong **Enterprise** OIDC/introspection **vs** front with **Keycloak/Auth0** as IdP |
| **Authorization** | in-service RBAC **vs** OPA sidecar (PDP) **vs** Enterprise `opa` plugin — gateway does coarse, service stays final authority |
| **East-west mTLS** | RFC-0002 (in-process, no mesh) **vs** a mesh (RFC-0006, deferred) — mTLS ≠ user auth |
| **Canary** | OSS weighted targets **vs** Argo Rollouts/Flagger **vs** Enterprise `canary` |
| **Kong tier** | stay **OSS** (+ OSS/external workarounds) **vs** **Enterprise/Konnect** (OIDC, advanced RL, OPA, canary, WAF-ish) — a cost/ops decision |

---

## 6. "Like big companies" — honest OSS-vs-Enterprise reality

Big-company Kong setups you've read about often assume **Kong Enterprise/Konnect**
(OIDC, oauth2-introspection, rate-limiting-advanced, OPA, canary, dev portal) or a
**dedicated edge/CDN tier** (WAF, bot, global rate-limit). On OSS you reach ~80% of
the value with deliberate substitutes:

| "Big company" feature | OSS path on this platform |
|---|---|
| OIDC SSO at the edge | front auth-service with **Keycloak** (OIDC IdP) and adopt **signed JWT** → OSS `jwt` plugin; or do OIDC app-side |
| Opaque-token introspection at edge | Enterprise `oauth2-introspection` **or** keep service-side `auth.GetMe` (you already do this) |
| Externalized authz (OPA) | run an **OPA sidecar** queried by services (PEP in service), not the Enterprise plugin |
| Advanced sliding-window rate limit | OSS `rate-limiting` + **`redis`** (good enough for most) |
| Canary / progressive delivery | **Argo Rollouts / Flagger** at the deploy layer (fits your GitOps better than gateway canary) |
| WAF | a **CDN/edge WAF** (Cloudflare etc.) or a **Coraza/ModSecurity** sidecar in front of Kong |
| mTLS east-west | **RFC-0002** in-process mTLS (no mesh) |

The lesson worth internalizing for interviews: **"production-grade" is about layering,
zero-trust, resilience, observability, and declarative ops — not the plugin count.**
A thin OSS Kong + strong service-side validation + a mesh/mTLS plan is a perfectly
defensible senior-level architecture; the *tradeoff* you accept is doing edge auth /
advanced RL / canary outside Kong (app/IdP/Argo) instead of via Enterprise plugins.

---

## 7. Key tradeoffs to reason about (the interview-grade core)

- **Edge auth vs service auth:** edge = less duplication + early rejection; service
  = zero-trust + domain context. Best practice is *both* (coarse at edge, final at
  service) — you have the service half; the edge half needs Wall-2 decisions.
- **Opaque vs JWT:** opaque = instant revocation, stateful, no edge verify; JWT =
  stateless edge verify, revocation is hard (denylist / short TTL + refresh).
- **`local` vs `redis` rate-limit:** local = no dependency, inaccurate ×N; redis =
  accurate, but a hot-path dependency that can degrade/relax on failure.
- **Edge cache:** cuts load/latency but invalidation + per-user-leak risk; public-only.
- **Retries:** improve transient resilience but cause retry storms without budgets;
  idempotent methods only.
- **Gateway canary vs Argo Rollouts:** gateway split is coarse and overlaps GitOps;
  Argo/Flagger fits your Flux model and gives metric-gated automated rollback.
- **OSS + workarounds vs Enterprise:** OSS = free, more moving parts you operate;
  Enterprise = integrated but license cost + lock-in.

---

## 8. Open questions (for you — no answer implied)

1. **Token model:** stay opaque, or move to **signed JWT**? (Gates edge auth, and
   most "big-company Kong" tutorials.)
2. **Edge auth:** do you actually want it, given services already validate? If yes
   → OSS `jwt` (needs JWT) / Enterprise OIDC / external IdP (Keycloak)?
3. **Authorization:** introduce RBAC/ABAC? Where — `auth.GetMe` returns roles +
   in-service checks, or an **OPA sidecar**? (This is the biggest functional gap.)
4. **Kong tier:** is adopting **Kong Enterprise/Konnect** on the table, or is
   "OSS + external tools (Keycloak/Argo/CDN-WAF/OPA-sidecar)" the intended path?
   (Decides half this roadmap.)
5. **Admin-surface security:** ip-restriction now, and/or real auth (OIDC) for
   Grafana/OpenBAO/pgui/Flux/MCP — which, and when?
6. **Rate-limit:** move to `redis` (Valkey) for cluster-wide accuracy, and extend
   limits to mon/infra/MCP ingresses?
7. **Observability:** add the `opentelemetry` plugin to close the edge trace gap?
   Sampling rate?
8. **Resilience:** introduce `KongUpstream` health-checks/retries/timeouts north-south?
9. **Caching:** proxy-cache on public GETs — worth it given services already
   Cache-Aside with Valkey internally?
10. **Canary:** gateway weighted-targets vs **Argo Rollouts/Flagger** (likely better
    fit for your GitOps)?
11. **mTLS / RFC-0002:** prioritize east-west mTLS independently of the gateway work?
12. **Docs/process:** which of the above is a config-PR vs a full RFC (then ADR)?
    A "production-grade gateway program" could itself be one umbrella RFC with
    phased ADRs.

---

## 9. Recommendations (options, not decisions)

- **Do now (config PRs, no convention change):** Phase 0 — ip-restriction on the
  exposed admin/mon/MCP ingresses (security), `opentelemetry` (trace gap),
  proxy-cache on public GETs, request-termination, and `redis` rate-limit extended
  to all ingresses. These are pure wins with named tradeoffs.
- **Then (small net-new):** Phase 1 — upstream health-checks/retries/timeouts;
  fix the JWT→opaque docs + a superseding ADR.
- **Decide deliberately (RFC → ADR):** Phase 2 — token model, edge auth, authz
  model, mTLS, canary tool, and **OSS-vs-Enterprise**. The cleanest framing is a
  single umbrella **RFC "Production-grade API gateway"** that lays out the forks,
  with one ADR per decision as you commit. (`rfc/README.md` lists *"Kong-JWT
  reconsideration"* in the backlog already — this is its natural home.)
- **Per proposals conventions:** this review is a **finding** (→ issue tracker /
  pre-RFC), not itself an RFC/ADR.

---

## Sources consulted (by name; not embedded in product docs)

- Kong official plugin docs (plugin hub + per-plugin pages) — for the OSS-vs-
  Enterprise split and DB-less constraints.
- Kong docs on rate-limiting (local/cluster/redis, consumer groups), health-checks
  & circuit breakers, proxy-cache, and the OpenTelemetry plugin (W3C `traceparent`).
- AWS Prescriptive Guidance (OPA design models: PEP at gateway *and* service),
  API7.ai / Curity (gateway-coarse vs service-fine authz, decouple policy via OPA).
- Industry practice on gateway layering, zero-trust, and anti-patterns; plus the
  two production-architecture blog posts you shared (high-level; gaps filled from
  the above).
- In-repo: current Kong config, `docs/api/*` conventions, ADR-003, RFC-0002/0006,
  and `auth-gateway-review.md`.

_(External material was used only to evaluate "what's standard," not copied into
the platform's product docs.)_
