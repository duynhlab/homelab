#!/usr/bin/env bash
# Demo data for a local Kind cluster, from the SAME images the cluster runs.
#
# local-stack has eight `command: ["seed"]` one-shot services (compose.yaml);
# the cluster has none, because seed data is not desired state — it is a
# one-time act. So this lives in scripts/, not in kubernetes/apps/: Flux would
# otherwise re-run it forever.
#
# Each Job is DERIVED FROM THE RUNNING DEPLOYMENT rather than hand-written, so
# it inherits the exact image, DB host, user, and password secretKeyRef the
# service itself uses. A hand-written Job would drift the moment the chart or a
# pin changes, and would seed the wrong database while looking correct.
#
# The DB identity comes from the `migrate` init container, not the service
# container: a seed writes as the migrator, directly to the primary (RFC-0029 —
# a converted service's runtime login cannot setval; its migrator is the owner
# at login, ADR-088). For a service not yet converted both containers carry the
# same login, so this changes only the host (primary instead of the pooler).
#
# ONE deliberate override: ENV. The services run with ENV=production (the
# ResourceSet sets it fleet-wide), and every seed refuses to run there —
# "seed refused in production — demo data is dev-only". That guard is right; a
# throwaway Kind cluster labelled production is the thing that is wrong. So the
# Job sets ENV=development, and the context guard below is what keeps this
# override from ever reaching a real cluster. Do not remove the guard.
#
# Usage: scripts/kind-seed.sh [service ...]     (default: all eight)
set -u

SERVICES=(user product cart order review shipping notification inventory)
TIMEOUT="${TIMEOUT:-300s}"

# ---- guard: local Kind only ------------------------------------------------
CTX=$(kubectl config current-context 2>/dev/null || echo "")
case "${CTX}" in
  kind-*) ;;
  *)
    echo "REFUSED - context '${CTX}' is not a Kind cluster." >&2
    echo "          This script overrides the production seed guard; it runs" >&2
    echo "          against local Kind and nothing else." >&2
    exit 1
    ;;
esac

[ "$#" -gt 0 ] && SERVICES=("$@")

STAMP=$(date +%s)
LAUNCHED=()

for svc in "${SERVICES[@]}"; do
  if ! kubectl -n "${svc}" get deploy "${svc}" >/dev/null 2>&1; then
    echo "SKIP  ${svc} - no deployment/${svc} in namespace ${svc}"
    continue
  fi

  job="${svc}-seed-${STAMP}"
  # Take image/args/env/resources/pullPolicy from container[0] and the DB_*
  # variables from the migrate init container; leave probes behind (a batch pod
  # serves no traffic and would fail readiness forever). The seed dials the
  # primary like migrate, so it also takes migrate's volume mounts (the CA its
  # PGSSLROOTCERT points at) and the pod volumes they name.
  if ! kubectl -n "${svc}" get deploy "${svc}" -o json |
    jq --arg job "${job}" --arg ns "${svc}" '
      .spec.template.spec.containers[0] as $c |
      ((.spec.template.spec.initContainers // []) | map(select(.name == "migrate")) | .[0]) as $mig |
      ($mig.env // []) as $m |
      ($m | map(.name)) as $mnames |
      ($mig.volumeMounts // []) as $mounts |
      ($mounts | map(.name)) as $mountnames |
      {
        apiVersion: "batch/v1",
        kind: "Job",
        metadata: { name: $job, namespace: $ns },
        spec: {
          backoffLimit: 1,
          ttlSecondsAfterFinished: 900,
          template: {
            metadata: { labels: { "platform.duynhlab.dev/seed": "true" } },
            spec: {
              restartPolicy: "Never",
              containers: [{
                name: "seed",
                image: $c.image,
                imagePullPolicy: $c.imagePullPolicy,
                args: ["seed"],
                resources: $c.resources,
                volumeMounts: $mounts,
                env: (([$c.env[] | select(.name as $n | ($mnames | index($n) | not) and $n != "PGSSLROOTCERT")] + $m) | map(
                  if .name == "ENV" then { name: "ENV", value: "development" }
                  elif .name == "PGAPPNAME" then { name: "PGAPPNAME", value: ($ns + "-seed") }
                  else . end
                ))
              }],
              volumes: [(.spec.template.spec.volumes // [])[] | select(.name as $v | $mountnames | index($v))]
            }
          }
        }
      }' | kubectl apply -f - >/dev/null; then
    echo "FAIL  ${svc} - could not create Job"
    continue
  fi
  LAUNCHED+=("${svc}:${job}")
  echo "START ${svc} - job/${job}"
done

[ "${#LAUNCHED[@]}" -eq 0 ] && { echo "nothing launched"; exit 1; }

echo
FAILED=0
for entry in "${LAUNCHED[@]}"; do
  svc="${entry%%:*}"; job="${entry##*:}"
  if kubectl -n "${svc}" wait --for=condition=complete "job/${job}" --timeout="${TIMEOUT}" >/dev/null 2>&1; then
    echo "OK    ${svc}"
  else
    FAILED=$((FAILED + 1))
    echo "FAIL  ${svc} - job/${job} did not complete within ${TIMEOUT}"
    kubectl -n "${svc}" logs "job/${job}" --tail=15 2>&1 | sed 's/^/        /'
  fi
done

echo
if [ "${FAILED}" -eq 0 ]; then
  echo "seeded ${#LAUNCHED[@]}/${#LAUNCHED[@]} services"
else
  echo "${FAILED} of ${#LAUNCHED[@]} seed jobs failed"
fi
exit "${FAILED}"
