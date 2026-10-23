#!/usr/bin/env bash
# Run a promtool unit test against a PrometheusRule manifest. promtool reads
# plain rule files, so the CR's spec.groups is extracted to <name>.rules.yaml
# beside a copy of the test, which must list that file under rule_files.
#
#   scripts/promtool-test.sh <prometheusrule.yaml> <test.yaml>
set -euo pipefail
rule=$(realpath "$1"); test=$(realpath "$2")
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); yaml.safe_dump({"groups": d["spec"]["groups"]}, open(sys.argv[2],"w"), sort_keys=False)' \
  "$rule" "$tmp/$(basename "$rule" .yaml).rules.yaml"
cp "$test" "$tmp/"
chmod -R a+rX "$tmp"   # the image runs as nobody
docker run --rm -v "$tmp":/w -w /w --entrypoint promtool prom/prometheus:v3.5.0 \
  test rules "$(basename "$test")"
