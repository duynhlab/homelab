# Makefile for Flux Operator

SHELL := /usr/bin/env bash -o pipefail
.SHELLFLAGS := -ec

.DEFAULT_GOAL := help

##@ General

.PHONY: all
all: up ## Create cluster, install Flux, deploy everything

.PHONY: up
up: cluster-up flux-up flux-push ## Bootstrap complete environment

.PHONY: down
down: cluster-down ## Delete cluster and registry

.PHONY: sync
sync: flux-push flux-sync ## Push and reconcile manifests

##@ Cluster

.PHONY: cluster-up
cluster-up: ## Create Kind cluster and local registry
	./scripts/kind-up.sh

.PHONY: cluster-down
cluster-down: ## Delete Kind cluster and registry
	./scripts/kind-down.sh

##@ Flux Operations

.PHONY: flux-up
flux-up: ## Bootstrap Flux Operator
	./scripts/flux-up.sh

.PHONY: flux-push
flux-push: ## Push manifests to OCI registry
	./scripts/flux-push.sh

.PHONY: flux-sync
flux-sync: ## Trigger Flux reconciliation
	./scripts/flux-sync.sh

.PHONY: flux-ui
flux-ui: ## Port-forward Flux UI, Grafana, VictoriaMetrics, VMAlert, Karma, Jaeger, Tempo, …
	./scripts/flux-ui.sh

.PHONY: flux-logs
flux-logs: ## Show Flux logs (last 10 minutes)
	flux logs --all-namespaces --since=10m

.PHONY: flux-status
flux-status: ## Show Flux status (all resources)
	flux get all -A

##@ Development

.PHONY: validate
validate: ## Validate Kubernetes manifests (Kustomize)
	./scripts/flux-validate.sh

.PHONY: postgres-alert-audit
postgres-alert-audit: ## Run PostgreSQL alert audit checks
	./scripts/postgres-alert-audit.sh

##@ Utilities

.PHONY: prereqs
prereqs: ## Check prerequisites (flux, kubectl, kind, docker)
	@echo "Checking prerequisites:"
	@which flux >/dev/null 2>&1 && echo "  ✓ flux" || echo "  ✗ flux (install: brew install fluxcd/tap/flux)"
	@which kubectl >/dev/null 2>&1 && echo "  ✓ kubectl" || echo "  ✗ kubectl"
	@which kind >/dev/null 2>&1 && echo "  ✓ kind" || echo "  ✗ kind"
	@which helm >/dev/null 2>&1 && echo "  ✓ helm" || echo "  ✗ helm"

.PHONY: help
help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
