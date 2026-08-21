#!/usr/bin/env bash
# Stage the next versioned Temporal worker build (ADR-030), without retyping it.
#
# A build bump changes exactly SIX values in a 232-line HelmRelease. Measured,
# not estimated: `git show fdad929a` holds the 1-12-0 → 1-13-0 cutover, and
# comments stripped, the two files differ by those six lines and nothing else.
# The other 134 body lines get retyped byte-identically every time, and the
# 41-line header gets rewritten from scratch. That is where the mistakes come
# from — the recorded one being ORDER_RECONCILER_ENABLED left `true` on all
# three builds at once, three judges sharing one scan (see the note in the
# manifest).
#
# So this script does the copying. It does NOT remove the copy-paste — the file
# is still duplicated — it removes the human performing it. Templating the
# duplication away needs a worker ResourceSet plus a render step in
# flux-validate (kustomize does not expand ResourceSets), and the Temporal
# Worker Controller would replace all of it, so that work is deliberately
# deferred rather than built twice.
#
# What it does NOT do, on purpose:
#   - delete the outgoing build. ADR-030 keeps it side by side until Temporal
#     reports its version DRAINED; that is a decision with a machine-checkable
#     answer, and it belongs to a human reading `describe-version`.
#   - activate the new version. Also a decision, also deliberate — see the
#     printed next steps.
#
# Usage: scripts/new-worker-build.sh <build-id>          e.g. 2.4.0
set -u

BUILD_ID="${1:-}"
if [ -z "${BUILD_ID}" ]; then
  echo "usage: $0 <build-id>        e.g. $0 2.4.0" >&2
  exit 1
fi

# The tag is also the Build ID and also part of the filename, so it must survive
# a `.` → `-` transform unambiguously. Reject anything that would not round-trip.
if ! printf '%s' "${BUILD_ID}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "ERROR - build id '${BUILD_ID}' is not X.Y.Z. The build id is the image" >&2
  echo "        tag AND the filename AND TEMPORAL_WORKER_BUILD_ID; anything else" >&2
  echo "        breaks the equality scripts/flux-validate.sh enforces." >&2
  exit 1
fi

APPS="kubernetes/apps"
CUTOVER="kubernetes/infra/controllers/temporal/worker-set-current-version-cronjob.yaml"
DASHED="${BUILD_ID//./-}"
NEW_FILE="${APPS}/order-worker-${DASHED}.yaml"

[ -f "${CUTOVER}" ] || { echo "ERROR - ${CUTOVER} not found; run from the repo root" >&2; exit 1; }
[ -e "${NEW_FILE}" ] && { echo "ERROR - ${NEW_FILE} already exists" >&2; exit 1; }

# Newest existing build wins as the source, so this works whether one or several
# builds are currently staged.
CURRENT=""
for f in "${APPS}"/order-worker-*.yaml; do [ -f "${f}" ] && CURRENT="${f}"; done
[ -n "${CURRENT}" ] || { echo "ERROR - no ${APPS}/order-worker-*.yaml to copy from" >&2; exit 1; }

OLD_TAG=$(yq '.spec.values.image.tag' "${CURRENT}")
[ -n "${OLD_TAG}" ] && [ "${OLD_TAG}" != "null" ] || { echo "ERROR - cannot read image.tag from ${CURRENT}" >&2; exit 1; }
OLD_DASHED="${OLD_TAG//./-}"

echo "source : ${CURRENT}  (build ${OLD_TAG})"
echo "target : ${NEW_FILE}  (build ${BUILD_ID})"
echo

cp "${CURRENT}" "${NEW_FILE}"

# The six values, each anchored so a near-miss fails loudly instead of silently
# editing the wrong line.
subst() {  # file, sed-expression, human description
  local before after
  before=$(md5 -q "$1" 2>/dev/null || md5sum "$1" | cut -d' ' -f1)
  sed -i '' -e "$2" "$1" 2>/dev/null || sed -i -e "$2" "$1"
  after=$(md5 -q "$1" 2>/dev/null || md5sum "$1" | cut -d' ' -f1)
  if [ "${before}" = "${after}" ]; then
    echo "ERROR - no change for: $3" >&2
    echo "        ${CURRENT} does not have the shape this script expects." >&2
    echo "        Read the file and fix the script rather than hand-editing," >&2
    echo "        or the next bump hits the same wall." >&2
    exit 1
  fi
  echo "  ok  $3"
}

subst "${NEW_FILE}" "s|order-worker-${OLD_DASHED}|order-worker-${DASHED}|g" \
  "metadata.name / releaseName / values.name"
subst "${NEW_FILE}" "s|^      tag: \"${OLD_TAG}\"|      tag: \"${BUILD_ID}\"|" \
  "image.tag"
subst "${NEW_FILE}" "s|service\.version=${OLD_TAG}|service.version=${BUILD_ID}|" \
  "OTEL_RESOURCE_ATTRIBUTES service.version"
subst "${NEW_FILE}" "/TEMPORAL_WORKER_BUILD_ID/{n;s|value: \"${OLD_TAG}\"|value: \"${BUILD_ID}\"|;}" \
  "TEMPORAL_WORKER_BUILD_ID"

# The reconciler is a single-judge role: flux-validate enforces exactly one build
# with it true. The new build takes it; the draining one gives it up.
subst "${CURRENT}" "/ORDER_RECONCILER_ENABLED/{n;s|value: \"true\"|value: \"false\"|;}" \
  "ORDER_RECONCILER_ENABLED false on ${OLD_TAG} (draining)"
subst "${CUTOVER}" "s|^                - \"${OLD_TAG}\"|                - \"${BUILD_ID}\"|" \
  "cutover CronJob --build-id"

cat <<NEXT

Staged. Three things this script deliberately left to you:

  1. The header of ${NEW_FILE} still describes build ${OLD_TAG}.
     Rewrite what it REPLACES and why — that prose is the only record of a
     cutover's reasoning, and copying it forward unread is how it goes stale.

  2. make validate
     Proves the filename ↔ image.tag ↔ TEMPORAL_WORKER_BUILD_ID ↔ CronJob
     equality still holds, and that exactly one build owns the reconciler.

  3. After it reconciles, ACTIVATE — the new version receives nothing until
     then, and nothing fails while it waits:
       kubectl -n temporal create job "order-set-current-\$(date +%s)" \\
         --from=cronjob/temporal-worker-set-current-version

  Then, and only once Temporal says so, retire ${OLD_TAG}:
       temporal worker deployment describe --name order-fulfillment
     Delete ${CURRENT} when its version reports DRAINED. Do not infer that
     from the age of the orders.
NEXT
