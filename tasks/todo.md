# RFC-0030 Phase 0 implementation handoff

- [x] Create homelab branch from origin/main and clone analytics-service.
- [x] Pin and inspect PeerDB/chart/PostgreSQL/RustFS artifacts.
- [x] Add PostgreSQL pg_cron image recipes and verify local builds.
- [x] Add opt-in Compose stack and preflighted source/mirror bootstrap.
- [x] Qualify CDC, access, PII, freshness and recovery: 14/14 PASS.
- [x] Qualify explicit DDL resnapshot and slot removal: 3/3 PASS.
- [x] Run unit tests, manifest validation, diagram and documentation checks.
- [x] Attempt clean full-stack regression and reproduce its blocker without
      the analytics overlay; preserve the database privilege policy.
- [x] Review changes and document pending Linux qualification.

The Mac implementation is ready for review, not cluster rollout or release.
Full local-stack API/browser/telemetry regression is blocked by review-service's
migration-role wiring. CNPG lifecycle, failover, supply-chain and performance
gates remain pending. See [qualification and evidence](../docs/proposals/rfc/RFC-0030/phase0.md).

Branches: homelab `feat/rfc0030-phase0`, images `feat/rfc0030-pg-cron`.
No analytics API or Admin UI was implemented, and no image/tag was published.
Future UI work must use admin-service/.claude/skills/product-design.
