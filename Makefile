# Makefile for Flux Operator Local Development
SHELL := /usr/bin/env bash -o pipefail
.SHELLFLAGS := -ec

# Configuration
CLUSTER_NAME := mop
REGISTRY_HOST := localhost:5050
REGISTRY_NAME := $(CLUSTER_NAME)-registry
REGISTRY_IMAGE := registry:3

# Git information
GIT_SOURCE := $(shell git config --get remote.origin.url 2>/dev/null || echo "local")
GIT_REVISION := $(shell git rev-parse HEAD 2>/dev/null || echo "unknown")

# Colors for output
COLOR_RESET := \033[0m
COLOR_BOLD := \033[1m
COLOR_GREEN := \033[32m
COLOR_YELLOW := \033[33m
COLOR_BLUE := \033[34m

.DEFAULT_GOAL := help

##@ General

.PHONY: help
help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make $(COLOR_BLUE)<target>$(COLOR_RESET)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(COLOR_BLUE)%-20s$(COLOR_RESET) %s\n", $$1, $$2 } /^##@/ { printf "\n$(COLOR_BOLD)%s$(COLOR_RESET)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Flux Operations

.PHONY: flux-up
flux-up: cluster-check registry-up flux-install ## Bootstrap Flux Operator (full setup)
	@echo "$(COLOR_GREEN)✓ Flux Operator is ready!$(COLOR_RESET)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Push manifests: make flux-push"
	@echo "  2. Verify: make flux-ls"
	@echo "  3. Access Web UI: make flux-ui"

.PHONY: flux-install
flux-install: ## Install Flux Operator via Helm and apply FluxInstance
	@echo "$(COLOR_YELLOW)→ Installing Flux Operator via Helm...$(COLOR_RESET)"
	@helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
		--namespace flux-system \
		--create-namespace \
		--wait
	@echo "$(COLOR_YELLOW)→ Waiting for Flux Operator to be ready...$(COLOR_RESET)"
	@kubectl wait --for=condition=available --timeout=300s deployment/flux-operator -n flux-system
	@echo "$(COLOR_YELLOW)→ Applying FluxInstance CRD...$(COLOR_RESET)"
	@kubectl apply -k kubernetes/clusters/local/flux-system/
	@echo "$(COLOR_YELLOW)→ Waiting for Flux controllers to be ready...$(COLOR_RESET)"
	@kubectl wait --for=condition=ready --timeout=300s pod -l app.kubernetes.io/part-of=flux -n flux-system 2>/dev/null || true
	@echo "$(COLOR_GREEN)✓ Flux Operator installed via Helm$(COLOR_RESET)"

.PHONY: flux-push
flux-push: ## Push Kubernetes manifests to OCI registry
	@echo "$(COLOR_YELLOW)→ Pushing manifests to $(REGISTRY_HOST)...$(COLOR_RESET)"
	@if [ -d kubernetes/clusters/local ]; then \
		echo "  • Pushing cluster-sync..."; \
		flux push artifact oci://$(REGISTRY_HOST)/flux-cluster-sync:latest \
			--path=kubernetes/clusters/local \
			--source="$(GIT_SOURCE)" \
			--revision="$(GIT_REVISION)"; \
	fi
	@if [ -d kubernetes/overlays/local/infrastructure ]; then \
		echo "  • Pushing infra-sync..."; \
		flux push artifact oci://$(REGISTRY_HOST)/flux-infra-sync:latest \
			--path=kubernetes/overlays/local/infrastructure \
			--source="$(GIT_SOURCE)" \
			--revision="$(GIT_REVISION)"; \
	fi
	@if [ -d kubernetes/overlays/local/apps ]; then \
		echo "  • Pushing apps-sync..."; \
		flux push artifact oci://$(REGISTRY_HOST)/flux-apps-sync:latest \
			--path=kubernetes/overlays/local/apps \
			--source="$(GIT_SOURCE)" \
			--revision="$(GIT_REVISION)"; \
	fi
	@echo "$(COLOR_GREEN)✓ Manifests pushed to OCI registry$(COLOR_RESET)"

.PHONY: flux-sync
flux-sync: flux-push ## Push manifests and trigger reconciliation
	@echo "$(COLOR_YELLOW)→ Triggering reconciliation...$(COLOR_RESET)"
	@if kubectl get kustomization infrastructure-local -n flux-system >/dev/null 2>&1; then \
		echo "  • Reconciling infrastructure..."; \
		flux reconcile kustomization infrastructure-local --with-source; \
	fi
	@if kubectl get kustomization apps-local -n flux-system >/dev/null 2>&1; then \
		echo "  • Reconciling apps..."; \
		flux reconcile kustomization apps-local --with-source; \
	fi
	@echo "$(COLOR_GREEN)✓ Reconciliation triggered$(COLOR_RESET)"

.PHONY: flux-ls
flux-ls: ## List all Flux resources
	@echo "$(COLOR_BOLD)Flux Kustomizations:$(COLOR_RESET)"
	@flux get kustomizations -A || echo "No kustomizations found"
	@echo ""
	@echo "$(COLOR_BOLD)Flux Sources:$(COLOR_RESET)"
	@flux get sources all -A || echo "No sources found"

.PHONY: flux-status
flux-status: ## Show Flux reconciliation status
	@echo "$(COLOR_BOLD)Flux System Status:$(COLOR_RESET)"
	@kubectl get pods -n flux-system
	@echo ""
	@flux get all -A

.PHONY: flux-ui
flux-ui: ## Open Flux Web UI (port-forward to localhost:9080)
	@echo "$(COLOR_YELLOW)→ Port-forwarding Flux Web UI to http://localhost:9080$(COLOR_RESET)"
	@echo "$(COLOR_YELLOW)→ Press Ctrl+C to stop$(COLOR_RESET)"
	@kubectl port-forward -n flux-system svc/flux-operator 9080:9080

.PHONY: flux-logs
flux-logs: ## Show Flux controller logs
	@echo "$(COLOR_BOLD)Recent Flux logs:$(COLOR_RESET)"
	@flux logs --all-namespaces --since=10m

.PHONY: flux-down
flux-down: ## Delete Flux Operator (keeps cluster and registry)
	@echo "$(COLOR_YELLOW)→ Deleting Flux resources...$(COLOR_RESET)"
	@kubectl delete namespace flux-system --ignore-not-found
	@kubectl delete namespace flux-operator-system --ignore-not-found
	@echo "$(COLOR_GREEN)✓ Flux Operator removed$(COLOR_RESET)"

##@ Cluster Operations

.PHONY: cluster-check
cluster-check: ## Check if Kind cluster is running
	@if ! kind get clusters | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "$(COLOR_YELLOW)⚠ Kind cluster '$(CLUSTER_NAME)' not found$(COLOR_RESET)"; \
		echo "Run: ./scripts/01-create-kind-cluster.sh"; \
		exit 1; \
	fi
	@echo "$(COLOR_GREEN)✓ Kind cluster '$(CLUSTER_NAME)' is running$(COLOR_RESET)"

.PHONY: cluster-up
cluster-up: ## Create Kind cluster (if not exists)
	@if ! kind get clusters | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "$(COLOR_YELLOW)→ Creating Kind cluster...$(COLOR_RESET)"; \
		./scripts/01-create-kind-cluster.sh; \
	else \
		echo "$(COLOR_GREEN)✓ Kind cluster already exists$(COLOR_RESET)"; \
	fi

##@ Registry Operations

.PHONY: registry-up
registry-up: ## Start local OCI registry (if not exists)
	@if [ "$$(docker inspect -f '{{.State.Running}}' $(REGISTRY_NAME) 2>/dev/null)" != "true" ]; then \
		echo "$(COLOR_YELLOW)→ Starting local OCI registry on $(REGISTRY_HOST)...$(COLOR_RESET)"; \
		docker run -d --restart=always \
			-p 127.0.0.1:5050:5000 \
			--name $(REGISTRY_NAME) \
			$(REGISTRY_IMAGE); \
		docker network connect kind $(REGISTRY_NAME) 2>/dev/null || true; \
		echo "$(COLOR_GREEN)✓ OCI registry started$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_GREEN)✓ OCI registry already running$(COLOR_RESET)"; \
	fi

.PHONY: registry-down
registry-down: ## Stop and remove local OCI registry
	@if docker ps -a | grep -q $(REGISTRY_NAME); then \
		echo "$(COLOR_YELLOW)→ Stopping OCI registry...$(COLOR_RESET)"; \
		docker stop $(REGISTRY_NAME) 2>/dev/null || true; \
		docker rm $(REGISTRY_NAME) 2>/dev/null || true; \
		echo "$(COLOR_GREEN)✓ OCI registry removed$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_GREEN)✓ OCI registry not running$(COLOR_RESET)"; \
	fi

.PHONY: registry-status
registry-status: ## Check OCI registry status
	@if [ "$$(docker inspect -f '{{.State.Running}}' $(REGISTRY_NAME) 2>/dev/null)" = "true" ]; then \
		echo "$(COLOR_GREEN)✓ OCI registry is running on $(REGISTRY_HOST)$(COLOR_RESET)"; \
		docker ps --filter name=$(REGISTRY_NAME) --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"; \
	else \
		echo "$(COLOR_YELLOW)⚠ OCI registry is not running$(COLOR_RESET)"; \
	fi

##@ Development

.PHONY: kustomize-build-infra
kustomize-build-infra: ## Build infrastructure Kustomize overlay locally
	@kubectl kustomize kubernetes/overlays/local/infrastructure

.PHONY: kustomize-build-apps
kustomize-build-apps: ## Build apps Kustomize overlay locally
	@kubectl kustomize kubernetes/overlays/local/apps

.PHONY: validate
validate: ## Validate all Kubernetes manifests
	@echo "$(COLOR_YELLOW)→ Validating Kubernetes manifests...$(COLOR_RESET)"
	@if [ -d kubernetes/clusters/local ]; then \
		kubectl kustomize kubernetes/clusters/local/flux-system/ > /dev/null && echo "  $(COLOR_GREEN)✓ flux-system$(COLOR_RESET)" || echo "  $(COLOR_RED)✗ flux-system$(COLOR_RESET)"; \
	fi
	@if [ -d kubernetes/overlays/local/infrastructure ]; then \
		kubectl kustomize kubernetes/overlays/local/infrastructure > /dev/null && echo "  $(COLOR_GREEN)✓ infrastructure$(COLOR_RESET)" || echo "  $(COLOR_RED)✗ infrastructure$(COLOR_RESET)"; \
	fi
	@if [ -d kubernetes/overlays/local/apps ]; then \
		kubectl kustomize kubernetes/overlays/local/apps > /dev/null && echo "  $(COLOR_GREEN)✓ apps$(COLOR_RESET)" || echo "  $(COLOR_RED)✗ apps$(COLOR_RESET)"; \
	fi

##@ Cleanup

.PHONY: clean
clean: flux-down registry-down ## Clean up Flux and registry (keeps cluster)
	@echo "$(COLOR_GREEN)✓ Cleanup complete$(COLOR_RESET)"

.PHONY: clean-all
clean-all: clean ## Clean up everything (cluster, Flux, registry)
	@if kind get clusters | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "$(COLOR_YELLOW)→ Deleting Kind cluster...$(COLOR_RESET)"; \
		kind delete cluster --name $(CLUSTER_NAME); \
		echo "$(COLOR_GREEN)✓ Kind cluster deleted$(COLOR_RESET)"; \
	fi

##@ Utilities

.PHONY: prereqs
prereqs: ## Check prerequisites (flux CLI, kubectl, kind, docker)
	@echo "$(COLOR_BOLD)Checking prerequisites:$(COLOR_RESET)"
	@which flux >/dev/null 2>&1 && echo "  $(COLOR_GREEN)✓ flux CLI$(COLOR_RESET)" || echo "  $(COLOR_YELLOW)✗ flux CLI (install: brew install fluxcd/tap/flux)$(COLOR_RESET)"
	@which kubectl >/dev/null 2>&1 && echo "  $(COLOR_GREEN)✓ kubectl$(COLOR_RESET)" || echo "  $(COLOR_YELLOW)✗ kubectl$(COLOR_RESET)"
	@which kind >/dev/null 2>&1 && echo "  $(COLOR_GREEN)✓ kind$(COLOR_RESET)" || echo "  $(COLOR_YELLOW)✗ kind$(COLOR_RESET)"
	@which docker >/dev/null 2>&1 && echo "  $(COLOR_GREEN)✓ docker$(COLOR_RESET)" || echo "  $(COLOR_YELLOW)✗ docker$(COLOR_RESET)"
	@which kustomize >/dev/null 2>&1 && echo "  $(COLOR_GREEN)✓ kustomize (standalone)$(COLOR_RESET)" || echo "  $(COLOR_BLUE)ℹ kustomize (using kubectl kustomize)$(COLOR_RESET)"

.PHONY: info
info: ## Show current configuration
	@echo "$(COLOR_BOLD)Configuration:$(COLOR_RESET)"
	@echo "  Cluster: $(CLUSTER_NAME)"
	@echo "  Registry: $(REGISTRY_HOST)"
	@echo "  Git Source: $(GIT_SOURCE)"
	@echo "  Git Revision: $(GIT_REVISION)"
