#!/usr/bin/env bash
# Copyright 2025 Stefan Prodan
# SPDX-License-Identifier: AGPL-3.0

set -o errexit

echo "Opening Flux Web UI on http://localhost:9080"
echo "Press Ctrl+C to stop"

kubectl port-forward -n flux-system svc/flux-operator 9080:9080
