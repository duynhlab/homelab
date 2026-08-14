# ADR-050: Separate workforce identity from customer identity in a staff realm

> **Decision summary:** We will move operator identity out of the `duynhlab`
> customer realm into a new **`duynhlab-staff`** realm on the same Keycloak —
> its own user store, login surface, and security posture (no
> self-registration, brute-force protection, short workforce sessions) —
> because customers and staff are different identity populations with
> different threat models, and the industry pattern (CIAM vs workforce IAM)
> separates them at the store, not at a role. We accept a second realm to
> operate, a second issuer for the edge and services to trust on `/protected/`
> routes, and a config split in the Admin Portal, in exchange for customer
> tokens being structurally unable to reach operator surfaces and operator
> accounts never appearing in the customer login flow.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-08-13 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | Where operator (workforce) identities live and which issuer privileged surfaces trust. Role names, the protected-route conventions (ADR-047), and the portal stack (ADR-049) are unchanged. |
| **Affected components** | Keycloak realm twins (cluster ConfigMap + local import), Envoy Gateway SecurityPolicies on `/protected/` routes (both config sets), `pkg/authmw` config of services carrying protected groups (inventory first), Admin Portal (`admin-service`) realm config, e2e audit A17 |
| **Related RFC** | [RFC-0022](../../rfc/RFC-0022/) (amended), [RFC-0023](../../rfc/RFC-0023/) (amended) |
| **Related research** | Keycloak server administration — realms as the isolation boundary for users, credentials, roles, and sessions; multiple realms per deployment for *"separate realms for employees and customers"* (verified via Context7, 2026-08-13) |
| **Related ADR** | [ADR-041](../ADR-041-keycloak-platform-idp/) (Keycloak stays the IdP — this record narrows its single-realm reading to *customer* identity), [ADR-047](../ADR-047-protected-apis-on-owning-services/) (the role gate these tokens pass), [ADR-049](../ADR-049-admin-portal-tanstack-spa/) (the portal that logs into this realm) |
| **Supersedes** | — (narrows ADR-041's scope; does not replace it) |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0023 program — identity-split train |
| **Adoption** | Partial — both realm twins carry the split: `duynhlab-staff` holds the operator, the `backoffice_admin` role, and the `admin-portal` client with the staff posture; the customer realm holds customers only. Every `/protected/` route verifies the staff issuer, so a customer token fails at the edge as wrong-issuer (audit A17/A18). Verified in local-stack; the cluster realm import is unverified until the Kind gate |

## Context

RFC-0022 established one realm (`duynhlab`) as the platform's identity store,
and RFC-0023's role gate rode it: `backoffice_admin` is a realm role, and the
seeded **customer** demo account `alice` was given that role as the test
operator. That shortcut surfaced the real question when the owner met it in
practice: the shopper who logs into the store at `:3001` and the operator who
administers stock at `:3009` were literally the same account.

One realm means one user store, one login page, one session space, and one
password policy for two populations with different threat models:

- **Customers (CIAM)**: self-service, potentially many, low individual blast
  radius, convenience-weighted posture (remember-me, long SSO).
- **Operators (workforce)**: few, hand-provisioned, every account is
  privileged, security-weighted posture (no registration path at all,
  brute-force lockout, short sessions).

Keycloak's own administration guide names realm separation for exactly this
split: realms isolate users, credentials, roles, and sessions, and a single
deployment hosts multiple realms — *"such as having separate realms for
employees and customers."* The industry equivalent is the standing CIAM vs
workforce-IAM division.

## Scope

### In scope

- A second realm `duynhlab-staff` on the existing Keycloak: operator users
  (first: `duyne`), the `backoffice_admin` role, and the `admin-portal` client.
- `/protected/` surfaces (edge SecurityPolicy + in-service verifier) trusting
  the staff issuer instead of the customer issuer.
- The customer realm keeping only customer identity (role and client removed;
  `alice` returns to a pure customer).

### Out of scope

- A separate IdP product or Keycloak instance for workforce identity.
- Fine-grained operator roles, MFA/TOTP enforcement, maker-checker — future
  hardening on this foundation.
- Any change to customer-facing auth (`customer-spa`, private routes).

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Population isolation | Operator accounts must not exist in the store customers log into, and vice versa |
| 2 | Structural denial | A customer token should fail privileged surfaces at the **issuer** level, not depend on a role claim check alone |
| 3 | Posture divergence | Registration-off, brute-force-on, short sessions for staff without touching customer UX |
| 4 | Standard alignment | CIAM vs workforce is the documented Keycloak pattern and the industry default |

## Decision

We will create realm **`duynhlab-staff`** beside `duynhlab` on the same
Keycloak deployment and make it the only identity store for Backoffice
operators.

- Staff realm: `registrationAllowed=false`, brute-force protection on,
  SSO idle 30m / max 10h (the workforce posture that previously lived as
  client attributes), realm role `backoffice_admin`, client `admin-portal`
  (public, PKCE S256), seeded operator `duyne` (dev-only placeholder password,
  never a committed production value).
- `/protected/` routes verify the **staff issuer** end to end: the edge
  SecurityPolicy's JWT provider points at the staff realm's JWKS, and the
  owning service's authmw verifier for the protected group expects the staff
  issuer. Customer-realm tokens are rejected at the edge as wrong-issuer —
  before any role logic runs.
- Customer realm: `admin-portal` client and `backoffice_admin` role are
  removed; `alice` holds only `customer`.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Ownership** | Operator identities exist only in `duynhlab-staff`; customer identities only in `duynhlab` |
| **Issuer** | Every `/protected/` surface (edge + service) trusts the staff issuer exclusively; `/public/`, `/private/` keep the customer issuer |
| **Role gate** | `MiddlewareRequireRole("backoffice_admin")` stays (ADR-047) — the realm split adds a fence, it does not replace the gate |
| **Provisioning** | No self-registration in the staff realm, ever; operators are seeded or admin-created |
| **Boundary** | No user exists in both realms; no client is shared across realms |
| **Compatibility** | Customer-facing auth is untouched — the split is invisible to the store |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Staff realm on the same Keycloak** | Store-level isolation; issuer-level denial; posture per population; documented Keycloak pattern | Second realm to operate; second issuer wired at edge + services; portal config split | **Selected** |
| **B — One realm, dedicated operator user** | Smallest change; personas separated at the account level | Same store, login surface, session space, and password policy for both populations; privileged access still hinges on one claim | Rejected — half-measure once the question is asked |
| **C — Status quo (alice dual-role)** | Zero work | A customer demo account is a privileged operator | Rejected — the trigger for this record |
| **D — Separate IdP for workforce** | Full product-level separation (the big-company end state) | A second identity product for a one-operator homelab | Rejected — realm gives the isolation at right-sized cost |

### Why the selected option won

Drivers 1–3 are all store-level properties; only a realm (or a separate IdP)
provides them, and the realm does it without new infrastructure. The
wrong-issuer rejection at the edge (driver 2) is the qualitative jump over B:
a leaked or over-privileged customer token cannot even reach the role check.

### Why the closest alternative lost

Option B separates *who* but not *where*: both populations keep sharing a
login surface, session space, and password policy, and privileged access still
rests entirely on one role claim inside a customer-population token. It also
re-does none of the posture work — registration and brute-force settings are
realm-wide.

## Consequences

### Positive consequences

- Customer tokens are structurally invalid on operator surfaces (issuer
  mismatch at the edge), and operator accounts are invisible to the customer
  login flow.
- Staff posture (no registration, lockout, short sessions) hardens without
  touching customer UX.
- The platform's identity story now matches the documented CIAM/workforce
  pattern it set out to learn.

### Negative consequences and accepted trade-offs

- Two realms to keep converged in the twins (cluster ConfigMap + local
  import); realm drift is now possible in two places.
- Services with protected groups carry a second verifier configuration
  (`OIDC_STAFF_*`), and the edge carries a second JWT provider.
- The e2e audit's identity rows split by persona (customer rows vs A17).

### Neutral consequences

- The `duynhlab-platform` audience stays shared — the audience names the
  platform, the issuer names the population.
- Demo credentials remain dev-only placeholders in both realms.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Staff realm in both realm twins; customer realm cleaned | homelab | identity-split train | Clean rebuild imports both realms; alice has no admin role |
| Edge SecurityPolicy per issuer on `/protected/` (both config sets) | homelab | identity-split train | Customer token → 401 wrong-issuer at the edge (audit A17) |
| Staff verifier in inventory's protected group (`OIDC_STAFF_*`) | inventory-service | identity-split train | Protected routes accept staff tokens only |
| Admin Portal targets the staff realm | admin-service | identity-split train | duyne logs in at `:3009`; alice cannot |
| Audit A17 rewritten for the split | homelab | identity-split train | Full compose audit green |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Issuer fence | Audit A17: customer-realm token → 401 at the edge on `/protected/`; staff token passes |
| Store isolation | Realm JSONs: no shared users or clients; staff realm has `registrationAllowed=false` |
| Role gate intact | Web-layer tests: staff token without `backoffice_admin` → 403 `FORBIDDEN` |
| Customer UX untouched | Audit B rows (customer SPA) pass unchanged |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- Operator headcount or compliance needs demand MFA policy, audit trails, or
  lifecycle tooling beyond what a seeded realm reasonably carries.
- A real workforce IdP (SSO with an employer directory) enters the picture —
  option D's territory.
- Keycloak realm count starts hurting upgrade or operations work.

A review does not automatically reverse the decision. A changed architectural
decision requires a new ADR that supersedes this one.

## References

- [RFC-0022](../../rfc/RFC-0022/) · [RFC-0023](../../rfc/RFC-0023/)
- [ADR-041](../ADR-041-keycloak-platform-idp/) · [ADR-047](../ADR-047-protected-apis-on-owning-services/) · [ADR-049](../ADR-049-admin-portal-tanstack-spa/)
- Keycloak Server Administration Guide — Configuring realms (realms as the
  user/credential/session isolation boundary; separate realms for employees
  and customers)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-08-13 | Accepted / Not started | Owner decision after meeting the alice dual-role seed in practice; Keycloak realm-separation pattern verified via Context7 |

---
_Last updated: 2026-08-13_
