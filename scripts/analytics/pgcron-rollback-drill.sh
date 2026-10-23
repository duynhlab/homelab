#!/usr/bin/env bash
# G2.5 (RFC-0030 / ADR-068): product-db can leave the postgresql-cron operand
# and come back. The order matters and is the point of the drill: drop pg_cron
# from shared_preload_libraries FIRST (the stock operand has no pg_cron.so, so
# a preload that names it would not start), THEN switch to the stock image.
# Flux is suspended for the drill and resumed at the end, which reapplies the
# catalog and the preload (two more rolling restarts). Every step must leave
# 3/3 instances healthy; the heartbeats stop while pg_cron is not loaded and
# must be fresh again at the end. Forward is the mirror image: catalog image
# first (removing imageName by hand), then the preload.
#
#   scripts/analytics/pgcron-rollback-drill.sh
set -uo pipefail
NS=product
STOCK=ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie
fail=0
healthy() { # wait until the cluster is healthy with every instance on $1
  for _ in $(seq 1 90); do
    ph="$(kubectl -n $NS get cluster product-db -o jsonpath='{.status.phase}')"
    imgs="$(kubectl -n $NS get pods -l cnpg.io/cluster=product-db,cnpg.io/podRole=instance -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' | grep -c "$1")"
    [ "$ph" = "Cluster in healthy state" ] && [ "$imgs" = 3 ] && return 0
    sleep 10
  done
  return 1
}
preload() { kubectl -n $NS exec "$(kubectl -n $NS get cluster product-db -o jsonpath='{.status.currentPrimary}')" -c postgres -- psql -XAtq -c "SHOW shared_preload_libraries"; }
step() { echo "== $* ($(date -u +%T))"; }
trap 'flux resume kustomization databases-local -n flux-system >/dev/null 2>&1' EXIT

step "suspend databases-local"
flux suspend kustomization databases-local -n flux-system >/dev/null

step "1/2 drop pg_cron from the preload"
libs="$(kubectl -n $NS get cluster product-db -o json | python3 -c "import json,sys;l=json.load(sys.stdin)['spec']['postgresql']['shared_preload_libraries'];print(json.dumps([x for x in l if x!='pg_cron']))")"
kubectl -n $NS patch cluster product-db --type=json -p "[{\"op\":\"replace\",\"path\":\"/spec/postgresql/shared_preload_libraries\",\"value\":$libs}]" >/dev/null
sleep 30
if healthy postgresql-cron && ! preload | grep -q pg_cron; then echo "PASS  G2.5 preload without pg_cron: 3/3 healthy ($(preload))"; else echo "FAIL  G2.5 after preload removal"; fail=1; fi

step "2/2 switch to the stock operand"
kubectl -n $NS patch cluster product-db --type=json -p "[{\"op\":\"remove\",\"path\":\"/spec/imageCatalogRef\"},{\"op\":\"add\",\"path\":\"/spec/imageName\",\"value\":\"$STOCK\"}]" >/dev/null
sleep 30
if healthy "$STOCK"; then echo "PASS  G2.5 stock operand: 3/3 healthy on $STOCK"; else echo "FAIL  G2.5 stock operand did not settle"; fail=1; fi

step "forward: back to the catalog, then resume databases-local (reapplies the preload)"
# Flux never owned imageName (this script's patch did), so server-side apply
# would keep it, and CNPG rejects imageName next to imageCatalogRef. Return
# the image first; the preload follows once the operand has pg_cron again.
kubectl -n $NS patch cluster product-db --type=json -p '[{"op":"remove","path":"/spec/imageName"},{"op":"add","path":"/spec/imageCatalogRef","value":{"apiGroup":"postgresql.cnpg.io","kind":"ImageCatalog","name":"postgresql-cron","major":18}}]' >/dev/null
sleep 30
healthy postgresql-cron || { echo "FAIL  G2.5 catalog image did not settle"; fail=1; }
flux resume kustomization databases-local -n flux-system --timeout=20m >/dev/null 2>&1
trap - EXIT
sleep 30
if healthy postgresql-cron && preload | grep -q pg_cron; then echo "PASS  G2.5 forward again: 3/3 on postgresql-cron, pg_cron preloaded"; else echo "FAIL  G2.5 forward roll"; fail=1; fi

step "heartbeats"
P="$(kubectl -n $NS get cluster product-db -o jsonpath='{.status.currentPrimary}')"
for _ in $(seq 1 12); do
  ages="$(for db in order checkout payment; do kubectl -n $NS exec "$P" -c postgres -- psql -XAtq -d $db -c "SELECT extract(epoch FROM clock_timestamp()-emitted_at)::int FROM analytics_cdc_heartbeat"; done | tr '\n' ' ')"
  max="$(echo $ages | tr ' ' '\n' | sort -n | tail -1)"; [ "${max:-999}" -le 60 ] 2>/dev/null && break; sleep 10
done
[ "${max:-999}" -le 60 ] 2>/dev/null && echo "PASS  G2.5 heartbeats fresh again (ages: $ages s)" || { echo "FAIL  G2.5 heartbeats stale ($ages)"; fail=1; }
[ $fail -eq 0 ] && echo "pg_cron rollback drill: PASS" || { echo "pg_cron rollback drill: FAIL"; exit 1; }
