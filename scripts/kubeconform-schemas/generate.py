#!/usr/bin/env python3
"""Turn a CRD version's openAPIV3Schema into a strict kubeconform schema.

Usage: generate.py <crd.yaml> <version> <out.json>

Like the datree CRDs-catalog generator, every object that lists properties gets
additionalProperties: false, so a misspelt field fails validation instead of
passing silently. Objects marked x-kubernetes-preserve-unknown-fields keep
accepting anything, as the API server does.
"""
import json
import subprocess
import sys


def strict(node):
    if isinstance(node, dict):
        if (node.get("type") == "object" and "properties" in node
                and not node.get("x-kubernetes-preserve-unknown-fields")
                and "additionalProperties" not in node):
            node["additionalProperties"] = False
        for value in node.values():
            strict(value)
    elif isinstance(node, list):
        for value in node:
            strict(value)
    return node


crd, version, out = sys.argv[1:4]
raw = subprocess.check_output(
    ["yq", "-o=json", f'.spec.versions[] | select(.name=="{version}") | .schema.openAPIV3Schema', crd])
with open(out, "w") as f:
    json.dump(strict(json.loads(raw)), f, separators=(",", ":"))
    f.write("\n")
