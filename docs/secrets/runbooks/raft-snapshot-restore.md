# OpenBAO Raft Snapshot And Restore

Use this before risky OpenBAO changes or when testing disaster recovery for the Raft data store.

Snapshot commands are authenticated. The bootstrap Job revoked the root token
(the `root_token` copy in `openbao-init-keys` is inert) — the normal admin
path is a **staff OIDC login** ([ADR-062](../../proposals/adr/ADR-062-staff-groups-sso/)):
the `infra-team` policy (`path "*"` incl. `sudo`) covers
`sys/storage/raft/snapshot`. The recovery-key `generate-root` ceremony is the
**fallback for when Keycloak or the edge is down** (see
[add-secret-live-cluster.md](./add-secret-live-cluster.md)).

```bash
# 0. Log in as an infra-team member (opens a browser to Keycloak):
export BAO_ADDR=https://openbao.duynh.me   # or a port-forward to :8200
bao login -method=oidc
export BAO_TOKEN="$(bao print token)"
# Fallback (issuer down): generate-root ceremony per add-secret-live-cluster.md.

# 1. Take a snapshot inside openbao-0 (before upgrades or on a weekly schedule)
kubectl exec -n openbao openbao-0 -- env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="$BAO_TOKEN" \
  bao operator raft snapshot save /tmp/openbao-$(date +%Y%m%d).snap

kubectl cp openbao/openbao-0:/tmp/openbao-$(date +%Y%m%d).snap \
  ./openbao-$(date +%Y%m%d).snap

# 2. Restore from snapshot (disaster recovery)
kubectl exec -n openbao openbao-0 -- env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="$BAO_TOKEN" \
  bao operator raft snapshot restore -force /tmp/openbao-restore.snap

# 3. Revoke the token when done (mandatory for a ceremony-generated root;
#    good hygiene for an OIDC token too — otherwise it expires with its TTL)
kubectl exec -n openbao openbao-0 -- env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="$BAO_TOKEN" \
  bao token revoke -self
```

---

_Last updated: 2026-08-27 — step 0 is the ADR-062 staff OIDC login; the generate-root ceremony is demoted to the issuer-down fallback. 2026-08-19: ceremony step 0 + final revoke added._
