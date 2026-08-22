# Makefile for Flux Operator

SHELL := /usr/bin/env bash -o pipefail
.SHELLFLAGS := -ec

.DEFAULT_GOAL := help

##@ General

.PHONY: up
up: cluster-up flux-push flux-up ## Bootstrap complete environment
	@echo "✔ Environment ready — run 'make flux-status' to watch reconciliation"

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
flux-up: ## Bootstrap Flux Operator (OpenTofu)
	./scripts/flux-up.sh

.PHONY: tf-init
tf-init: ## OpenTofu init (terraform/)
	tofu -chdir=terraform init -input=false

.PHONY: tf-plan
tf-plan: ## OpenTofu plan (expect zero diff once bootstrapped)
	tofu -chdir=terraform plan -input=false

.PHONY: tf-apply
tf-apply: ## OpenTofu apply the Flux Operator bootstrap
	tofu -chdir=terraform apply -input=false

.PHONY: tf-destroy
tf-destroy: ## OpenTofu destroy the bootstrap resources
	tofu -chdir=terraform destroy -input=false

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

##@ End-to-end assertions

# GATE selects the target preset (compose | kind); every script reads it. These
# exit non-zero when a row fails, which is the point: the gates used to be
# read by eye.

.PHONY: e2e
e2e: e2e-smoke e2e-saga e2e-staff e2e-operator ## Run the k6 gate suite (set GATE=compose|kind)

.PHONY: e2e-smoke
e2e-smoke: ## Functional + telemetry rows as checks with thresholds
	GATE=$(or $(GATE),kind) k6 run scripts/k6/smoke.js

.PHONY: e2e-saga
e2e-saga: ## An order completes, Pinned, on the Current build id
	GATE=$(or $(GATE),kind) k6 run scripts/k6/saga.js

.PHONY: e2e-session
e2e-session: ## Refresh rotation, reuse detection, logout (compose A4/A5)
	GATE=$(or $(GATE),compose) k6 run scripts/k6/session.js

.PHONY: e2e-staff
e2e-staff: ## The /protected/ Backoffice surface (compose A17-A19, A21)
	GATE=$(or $(GATE),compose) k6 run scripts/k6/staff.js

.PHONY: e2e-operator
e2e-operator: ## Operator resolve of a parked order (compose A20)
	GATE=$(or $(GATE),compose) k6 run scripts/k6/operator.js

.PHONY: e2e-observability
e2e-observability: ## Datasources, dashboards, panel path, scrape targets (compose C17-C20)
	GATE=compose k6 run scripts/k6/observability.js

.PHONY: e2e-ratelimit
e2e-ratelimit: ## Drive under and over the edge ceiling; 429 must be well-formed
	GATE=$(or $(GATE),kind) k6 run scripts/k6/ratelimit.js

.PHONY: e2e-load
e2e-load: ## Order load; reports the Temporal backlog it built
	GATE=$(or $(GATE),kind) k6 run scripts/k6/load.js

##@ Utilities

.PHONY: prereqs
prereqs: ## Check prerequisites (flux, kubectl, kind, helm, docker, tofu)
	@for bin in flux kubectl kind helm docker tofu; do \
	  if command -v $$bin >/dev/null 2>&1; then echo "  OK   $$bin"; \
	  else echo "  MISS $$bin"; fi; \
	done

.PHONY: help
help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
