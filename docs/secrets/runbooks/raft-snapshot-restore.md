# OpenBAO Raft Snapshot And Restore

Use this before risky OpenBAO changes or when testing disaster recovery for the Raft data store.

```bash
# Take a snapshot (run before upgrades or on a weekly schedule)
kubectl exec -n openbao openbao-0 -- \
  bao operator raft snapshot save /tmp/openbao-$(date +%Y%m%d).snap

kubectl cp openbao/openbao-0:/tmp/openbao-$(date +%Y%m%d).snap \
  ./openbao-$(date +%Y%m%d).snap

# Restore from snapshot (disaster recovery)
kubectl exec -n openbao openbao-0 -- \
  bao operator raft snapshot restore -force /tmp/openbao-restore.snap
```

_Last updated: 2026-07-14 - Split from `docs/secrets/README.md` during the runbook refactor._
