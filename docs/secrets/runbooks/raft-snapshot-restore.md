# OpenBAO Raft Snapshot And Restore

Use this before risky OpenBAO changes or when testing disaster recovery for the Raft data store.

Snapshot commands are authenticated, and no standing admin credential exists —
the bootstrap Job revoked the root token (the `root_token` copy in
`openbao-init-keys` is inert).

```bash
# 0. Obtain a short-lived root token via the generate-root ceremony
#    (steps 1–3 of ./add-secret-live-cluster.md, inside openbao-0),
#    then keep the shell open with:
#      export BAO_ADDR=http://127.0.0.1:8200
#      export BAO_TOKEN=<generated-root-token>

# 1. Take a snapshot inside openbao-0 (before upgrades or on a weekly schedule)
kubectl exec -n openbao openbao-0 -- env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="$BAO_TOKEN" \
  bao operator raft snapshot save /tmp/openbao-$(date +%Y%m%d).snap

kubectl cp openbao/openbao-0:/tmp/openbao-$(date +%Y%m%d).snap \
  ./openbao-$(date +%Y%m%d).snap

# 2. Restore from snapshot (disaster recovery)
kubectl exec -n openbao openbao-0 -- env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="$BAO_TOKEN" \
  bao operator raft snapshot restore -force /tmp/openbao-restore.snap

# 3. Revoke the temporary root token when done
kubectl exec -n openbao openbao-0 -- env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="$BAO_TOKEN" \
  bao token revoke -self
```

---

_Last updated: 2026-08-19 — Added the generate-root ceremony (step 0) and final revoke; bare `bao` commands were unrunnable after the bootstrap root revoke._
