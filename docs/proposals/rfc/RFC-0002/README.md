# RFC-0002 East-west mTLS for internal gRPC

| Status | Scope | Created | Last updated |
|--------|-------|---------|--------------|
| superseded | platform-wide | 2026-06-26 | 2026-07-21 |

> **Superseded (2026-07-21).** This RFC's substance has been split and re-homed to
> remove the overlap between the east-west mTLS docs:
>
> - **In-process gRPC mTLS on `homelab-ca` (the near-term "what we do")** is now one tier of
>   **[RFC-0020 — Internal TLS everywhere on the `homelab-ca` root](../RFC-0020/research.md)**.
> - **The future service-mesh option** (Istio Ambient vs Linkerd vs mesh-less) lives in
>   **[RFC-0006 — Service mesh evaluation](../RFC-0006/README.md)**.
>
> This file is retained as a pointer so existing links resolve and the decision history stays
> intact.

## What it decided

RFC-0002 proposed authenticating and encrypting every east-west gRPC hop (and the Temporal
worker↔frontend link) with **mutual TLS**, using leaf certificates issued by the existing
`homelab-ca` cert-manager ClusterIssuer and distributed by trust-manager — wired **in-process**
through `pkg/grpcx` + `pkg/temporalx`, replacing today's `insecure.NewCredentials()`. It
recommended the in-process approach over a service mesh (deferred) and over SPIFFE/SPIRE
(rejected as disproportionate), with a callee-first, permissive→strict rollout.

That design was never implemented. It is preserved in this file's git history and will be
re-specified, as the east-west tier, in **RFC-0020**'s decision document (README) when the
RFC-0020 research gate passes.

## Related

- **[RFC-0020](../RFC-0020/research.md)** — owner of internal TLS on `homelab-ca`, including the
  east-west gRPC mTLS tier that was this RFC.
- **[RFC-0006](../RFC-0006/README.md)** — the future service-mesh evaluation (the alternative
  path to east-west mTLS).

---
_Last updated: 2026-07-21 (superseded; split into RFC-0020 + RFC-0006)._
