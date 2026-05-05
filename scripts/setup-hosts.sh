#!/usr/bin/env bash
# scripts/setup-hosts.sh
# Adds local.duynh.me + *.duynh.me entries to /etc/hosts so the Kind cluster
# is reachable through the same hostnames the TLS certificate is issued for.
#
# Idempotent: safe to re-run. Replaces any existing block managed by this
# script (markers below). Does NOT touch unrelated /etc/hosts content.
#
# Usage:
#   sudo scripts/setup-hosts.sh        # apply
#   sudo scripts/setup-hosts.sh remove # remove the managed block

set -euo pipefail

MARK_BEGIN="# >>> duynhlab homelab — managed by scripts/setup-hosts.sh"
MARK_END="# <<< duynhlab homelab"
HOSTS_FILE="/etc/hosts"

HOSTS=(
  duynh.me
  local.duynh.me
  gateway.duynh.me
  grafana.duynh.me
  vmui.duynh.me
  vmalert.duynh.me
  karma.duynh.me
  jaeger.duynh.me
  tempo.duynh.me
  pyroscope.duynh.me
  logs.duynh.me
  ui.duynh.me
  source.duynh.me
  openbao.duynh.me
  pgui.duynh.me
  vm-mcp.duynh.me
  vl-mcp.duynh.me
  flux-mcp.duynh.me
  slo.duynh.me
)

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: must run as root (sudo)" >&2
  exit 1
fi

# Strip any previously managed block
tmp=$(mktemp)
awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
  $0 == b { skip=1; next }
  $0 == e { skip=0; next }
  !skip { print }
' "$HOSTS_FILE" > "$tmp"

if [[ "${1:-apply}" == "remove" ]]; then
  install -m 0644 "$tmp" "$HOSTS_FILE"
  rm -f "$tmp"
  echo "removed managed block from $HOSTS_FILE"
  exit 0
fi

{
  echo "$MARK_BEGIN"
  for h in "${HOSTS[@]}"; do
    printf "127.0.0.1\t%s\n" "$h"
  done
  echo "$MARK_END"
} >> "$tmp"

install -m 0644 "$tmp" "$HOSTS_FILE"
rm -f "$tmp"

echo "wrote ${#HOSTS[@]} entries to $HOSTS_FILE"
