# RFC-0030 Phase 0

Implement an opt-in commerce CDC qualification stack on the latest homelab
main baseline. PostgreSQL remains authoritative. No analytics API, Admin page,
Flux rollout, image publication, or release tag is part of this increment.

1. Lock upstream artifacts and inspect the released chart against the chosen
   images; document licensing and compatibility evidence.
2. Prepare PostgreSQL 18.6 + pg_cron recipes (Compose and CNPG separately).
3. Bootstrap three allowlisted publications, heartbeat jobs and PeerDB mirrors
   using real service migrations and disposable fixture data.
4. Add a bounded gate with machine-readable and Markdown evidence; run it and
   the existing local-stack regression gates when the runtime is available.
5. Hand Linux the same pins and explicit pending CNPG, restore, failover and
   native performance gates. Never promote static/Compose evidence to those gates.

Use Compose project rfc0030-phase0. Cleanup is scoped to that project. Credentials
are disposable local values; reports must not contain them. AMD64 emulation on
Mac is allowed for functional checks, not performance qualification.

Canonical qualification record: ../docs/proposals/rfc/RFC-0030/phase0.md.

Future Admin UI work must first read the user's selected
`admin-service/.claude/skills/product-design` skill. No UI is built in Phase 0.
