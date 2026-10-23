#!/usr/bin/env bash
# G1.3 (RFC-0030): a product-db backup restores onto the postgresql-cron
# operand. A throwaway one-instance Cluster bootstraps by recovery from
# product-db's Barman object store with the ImageCatalog the cluster runs, no
# preload and no WAL archiving of its own; the check asserts pg_cron 1.6.8 is
# available and the restored data reads, then deletes the Cluster and its PVC.
#
#   scripts/analytics/pgcron-restore-check.sh
set -uo pipefail
NAME=pgcron-restore-check
NS=product
fail=0
cleanup() { kubectl -n $NS delete cluster $NAME --ignore-not-found --wait=false >/dev/null 2>&1; }
trap cleanup EXIT

kubectl apply -f - >/dev/null <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: $NAME
  namespace: $NS
  labels:
    app.kubernetes.io/component: restore-check
spec:
  instances: 1
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ImageCatalog
    name: postgresql-cron
    major: 18
  bootstrap:
    recovery:
      source: product-db-backup
      database: product
      owner: product
  externalClusters:
    - name: product-db-backup
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: product-db-backup-store
          serverName: product-db-cluster
  # product-db uses 64 MiB WAL segments (walSegmentSize: 64), and PostgreSQL
  # refuses min_wal_size below two segments; CNPG aligns the recovery-critical
  # settings from pg_controldata but not these two.
  postgresql:
    parameters:
      min_wal_size: "2GB"
      max_wal_size: "8GB"
  storage:
    size: 2Gi
  resources:
    requests: {cpu: 50m, memory: 256Mi}
    limits: {memory: 512Mi}
EOF
echo "restoring $NAME from product-db-backup-store at $(date -u +%T)"
for _ in $(seq 1 60); do
  ph="$(kubectl -n $NS get cluster $NAME -o jsonpath='{.status.phase}' 2>/dev/null)"
  [ "$ph" = "Cluster in healthy state" ] && break
  sleep 10
done
echo "phase: $ph at $(date -u +%T)"
[ "$ph" = "Cluster in healthy state" ] || { echo "FAIL  G1.3 restore never became healthy"; exit 1; }
pod="$(kubectl -n $NS get cluster $NAME -o jsonpath='{.status.currentPrimary}')"
q() { kubectl -n $NS exec "$pod" -c postgres -- psql -XAtq -d "$1" -c "$2" 2>&1; }
img="$(kubectl -n $NS get pod "$pod" -o jsonpath='{.spec.containers[0].image}')"
case "$img" in *postgresql-cron*) echo "PASS  G1.3 restored instance runs $img";; *) echo "FAIL  G1.3 image $img"; fail=1;; esac
v="$(q postgres "SELECT default_version FROM pg_available_extensions WHERE name='pg_cron'")"
[ "$v" = 1.6 ] && echo "PASS  G1.3 pg_cron available (control default_version $v)" || { echo "FAIL  G1.3 pg_cron available: '$v'"; fail=1; }
f="$(q postgres "SELECT count(*) FROM pg_proc WHERE proname='schedule_in_database'")"
echo "      cron schema restored from WAL: $f schedule_in_database function(s)"
n="$(q order "SELECT count(*) FROM orders")"
[[ "$n" =~ ^[0-9]+$ ]] && echo "PASS  G1.3 restored data reads (order.orders = $n rows)" || { echo "FAIL  G1.3 read: $n"; fail=1; }
[ $fail -eq 0 ] && echo "pg_cron restore check: PASS" || { echo "pg_cron restore check: FAIL"; exit 1; }
