#!/usr/bin/env bash
# RFC-0029 authorization lab: the PG-01..08 and CNPG-01..07 experiments as a
# repeatable gate. Re-run on every PostgreSQL major and every CNPG minor/major.
#
#   scripts/pg-authz-lab/run.sh pg     # throwaway postgres container, no cluster
#   scripts/pg-authz-lab/run.sh cnpg   # Kind platform-db, lab_* objects only
#   scripts/pg-authz-lab/run.sh all
#
# Exit 0 iff every experiment passes. Both modes clean up after themselves.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PG_IMAGE="${PG_IMAGE:-postgres:18-alpine}"
FAIL=0
declare -a ROWS=()

row() { ROWS+=("| $1 | $2 | $3 |"); [ "$2" = PASS ] || FAIL=1; }

run_pg() {
  local name="pg-authz-lab-$$"
  docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=lab "$PG_IMAGE" >/dev/null || { row "PG-*" FAIL "cannot start $PG_IMAGE"; return; }
  trap 'docker rm -f "$name" >/dev/null 2>&1' RETURN
  local i
  for i in $(seq 1 60); do
    docker exec "$name" pg_isready -q -U postgres 2>/dev/null && docker exec "$name" psql -qAt -U postgres -c 'select 1' >/dev/null 2>&1 && break
    sleep 1
  done
  local psql=(docker exec -i "$name" psql -q -X -v ON_ERROR_STOP=1 -U postgres)
  "${psql[@]}" -d template1 <"$HERE/pg/00-helpers.sql" >/dev/null || { row "PG-*" FAIL "helpers did not load"; return; }
  local ver; ver="$(docker exec "$name" psql -qAt -U postgres -c 'show server_version')"
  echo "PostgreSQL $ver ($PG_IMAGE)"
  local f id db out
  for f in "$HERE"/pg/PG-*.sql; do
    id="$(basename "$f" .sql)"; db="lab_${id//-/}"; db="${db,,}"
    "${psql[@]}" -d postgres -c "CREATE DATABASE $db" >/dev/null
    if out="$("${psql[@]}" -d "$db" <"$f" 2>&1)"; then
      row "$id" PASS "$(sed -n '1s/^-- //p' "$f")"
    else
      row "$id" FAIL "$(grep -m1 -o 'LAB FAIL: .*\|ERROR: .*' <<<"$out")"
    fi
  done
}

# shellcheck source=cnpg/lib.sh
run_cnpg() { source "$HERE/cnpg/lib.sh"; cnpg_main; }

case "${1:-}" in
  pg) run_pg ;;
  cnpg) run_cnpg ;;
  all) run_pg; run_cnpg ;;
  *) echo "usage: $0 pg|cnpg|all" >&2; exit 2 ;;
esac

echo
echo "| Experiment | Result | What |"
echo "|---|---|---|"
printf '%s\n' "${ROWS[@]}"
exit "$FAIL"
