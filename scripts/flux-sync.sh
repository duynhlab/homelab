#!/usr/bin/env bash

set -o errexit

echo "Waiting for infrastructure sync to complete"
flux reconcile kustomization infrastructure-local --with-source

echo "Waiting for monitoring sync to complete"
flux reconcile kustomization monitoring-local --with-source

echo "Waiting for apm sync to complete"
flux reconcile kustomization apm-local --with-source

echo "Waiting for databases sync to complete"
flux reconcile kustomization databases-local --with-source

echo "Waiting for apps sync to complete"
flux reconcile kustomization apps-local --with-source

echo "Waiting for slo sync to complete"
flux reconcile kustomization slo-local --with-source

flux tree kustomization apps-local

echo "✔ Cluster is in sync"
