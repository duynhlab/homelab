# Makefile for Flux Operator

SHELL := /usr/bin/env bash -o pipefail
.SHELLFLAGS := -ec

.DEFAULT_GOAL := help

# Oldest Kind CLI that can create the node image pinned in scripts/kind-up.sh
# (RFC-0032). Kind publishes node images per CLI release.
KIND_MIN_VERSION := v0.33.0

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
cluster-up: kind-floor ## Create Kind cluster and local registry
	./scripts/kind-up.sh

.PHONY: kind-floor
kind-floor: ## Fail if the Kind CLI is older than KIND_MIN_VERSION
	@v=$$(kind version | awk '{print $$2}'); \
	if [ "$$(printf '%s\n' "$(KIND_MIN_VERSION)" "$$v" | sort -V | head -1)" != "$(KIND_MIN_VERSION)" ]; then \
	  echo "  FAIL kind $$v is older than $(KIND_MIN_VERSION), which the pinned node image needs"; exit 1; \
	fi; \
	echo "  OK   kind $$v (>= $(KIND_MIN_VERSION))"

.PHONY: cluster-down
cluster-down: ## Delete Kind cluster and registry
	./scripts/kind-down.sh

.PHONY: hosts
hosts: ## Map *.duynh.me to 127.0.0.1 in /etc/hosts (sudo; ARGS=remove undoes it)
	sudo ./scripts/setup-hosts.sh $(ARGS)

.PHONY: seed
seed: ## Seed demo data into the Kind cluster (ARGS=<service ...> for a subset)
	./scripts/kind-seed.sh $(ARGS)

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
# GATE has no default: the targets used to default to different stacks, so a
# bare `make e2e` ran saga and smoke against Kind and staff and operator against
# compose. Expanded only when a recipe runs, so other targets are unaffected.
E2E_GATE = $(if $(filter compose kind,$(GATE)),$(GATE),$(error set GATE=compose or GATE=kind))

.PHONY: e2e-analytics
e2e-analytics: ## Qualify RFC-0030 on the disposable Compose project
	@test "$(or $(GATE),compose)" = compose || { echo "Analytics CNPG gates require the Linux runbook"; exit 2; }
	python3 local-stack/analytics/control.py gate

.PHONY: e2e-analytics-ddl
e2e-analytics-ddl: ## Exercise explicit CDC resnapshot on a disposable schema copy
	@test "$(or $(GATE),compose)" = compose || exit 2
	python3 local-stack/analytics/ddl.py

.PHONY: e2e
e2e: e2e-saga e2e-smoke e2e-staff e2e-operator ## Run the k6 gate suite (set GATE=compose|kind)
# Order matters: saga runs FIRST. smoke's C6/K5.2 asserts all ten services have
# spans, and checkout/payment only emit once the saga drives the funnel. Both gates
# mandate a from-scratch stack, so smoke-before-saga fails that row every first run
# (measured on compose AND Kind, 2026-08-25).

.PHONY: e2e-smoke
e2e-smoke: ## Functional + telemetry rows as checks with thresholds
	@mkdir -p scripts/k6/out
	GATE=$(E2E_GATE) k6 run scripts/k6/smoke.js

.PHONY: e2e-saga
e2e-saga: ## An order completes, Pinned, on the Current build id
	@mkdir -p scripts/k6/out
	GATE=$(E2E_GATE) k6 run scripts/k6/saga.js

.PHONY: e2e-session
e2e-session: ## Refresh rotation, reuse detection, logout (compose A4/A5)
	@mkdir -p scripts/k6/out
	GATE=$(E2E_GATE) k6 run scripts/k6/session.js

.PHONY: e2e-staff
e2e-staff: ## The /protected/ Backoffice surface (compose A17-A19, A21)
	@mkdir -p scripts/k6/out
	GATE=$(E2E_GATE) k6 run scripts/k6/staff.js

.PHONY: e2e-operator
e2e-operator: ## Operator resolve of a parked order (compose A20)
	@mkdir -p scripts/k6/out
	GATE=$(E2E_GATE) k6 run scripts/k6/operator.js

.PHONY: e2e-analytics-api
e2e-analytics-api: ## The analytics protected surface: guard chain + contract (compose A25, kind K4.12/K4.13)
	@mkdir -p scripts/k6/out
	GATE=$(E2E_GATE) k6 run scripts/k6/analytics.js

.PHONY: e2e-conformance
e2e-conformance: ## Row C22: stop Weaver's live-check, save its report, fail on a violation (needs compose.weaver.yaml)
	@# Weaver >= 0.27 over HTTP: POST /stop waits for the report, GET /report
	@# reads it, POST /shutdown ends the process. Shutdown runs even when a step
	@# fails, and every call is bounded; the verdict needs both a zero exit code
	@# and zero violations in the saved report.
	@cd local-stack && rc=0; \
	  curl -fsS --max-time 300 -X POST localhost:4320/stop >/dev/null \
	    && curl -fsS --max-time 120 localhost:4320/report -o .weaver-live-check.json \
	    || { rc=1; echo 'C22 FAIL: could not stop Weaver or read its report'; }; \
	  if curl -fsS --max-time 30 -X POST localhost:4320/shutdown >/dev/null; then \
	    docker compose -f compose.yaml -f compose.weaver.yaml wait weaver >/dev/null 2>&1 || true; \
	  else rc=1; echo 'C22 FAIL: Weaver did not accept /shutdown; stopping it'; \
	    docker compose -f compose.yaml -f compose.weaver.yaml stop -t 10 weaver >/dev/null 2>&1 || true; fi; \
	  [ "$$rc" = 0 ] || exit 1; \
	  code=$$(docker inspect -f '{{.State.ExitCode}}' local-stack-weaver-1); \
	  python3 -c "import json,sys;c=json.load(open('.weaver-live-check.json'))['statistics'].get('advice_level_counts') or {};print('C22 advice:',c);sys.exit(1 if c.get('violation',0) else 0)" || code=violations; \
	  if [ "$$code" = 0 ]; then echo 'C22 OK: every emitted name is in the registry'; else echo "C22 FAIL: weaver exit/verdict $$code — see local-stack/.weaver-live-check.json"; exit 1; fi

# The registry lives in duynhlab/pkg; pin the commit whose catalog logs.md is
# held to, and bump it in the same change that updates the table.
SEMCONV_PKG_REF ?= 7032b6b

.PHONY: semconv-catalog-refresh
semconv-catalog-refresh: ## Vendor the registry's generated event catalog from pkg at SEMCONV_PKG_REF
	gh api "repos/duynhlab/pkg/contents/semconv/docs/event-catalog.md?ref=$(SEMCONV_PKG_REF)" \
	  -H 'Accept: application/vnd.github.raw' > docs/api/event-catalog.generated.md
	sed -i '1s|$$| pkg @ $(SEMCONV_PKG_REF) — refresh with make semconv-catalog-refresh -->|;1s|-- do not edit; run make semconv-generate -->||' docs/api/event-catalog.generated.md

.PHONY: semconv-catalog-check
semconv-catalog-check: ## docs/api/logs.md event catalog == the registry's (names, classes, attributes, owners)
	python3 scripts/semconv-catalog-check.py

.PHONY: e2e-observability
e2e-observability: ## Datasources, dashboards, panel path, scrape targets (compose C17-C20)
	@mkdir -p scripts/k6/out
	GATE=compose k6 run scripts/k6/observability.js

.PHONY: e2e-ratelimit
e2e-ratelimit: ## Drive under and over the edge ceiling; 429 must be well-formed
	@mkdir -p scripts/k6/out
	GATE=$(E2E_GATE) k6 run scripts/k6/ratelimit.js

.PHONY: e2e-load
e2e-load: ## Order load; reports the Temporal backlog it built
	@mkdir -p scripts/k6/out
	GATE=$(E2E_GATE) k6 run scripts/k6/load.js

.PHONY: e2e-restock
e2e-restock: ## Top demo stock back up to the seed baseline (make seed cannot -- ON CONFLICT DO NOTHING)
	@mkdir -p scripts/k6/out
	GATE=$(E2E_GATE) k6 run scripts/k6/restock.js

.PHONY: db-isolation
db-isolation: ## pg_hba isolation sweep against the live databases (RFC-0012 P4)
	./scripts/db-isolation-sweep.sh

.PHONY: db-tls
db-tls: ## DB hops verify the server and refuse plaintext (ADR-089)
	./scripts/db-tls-check.sh

.PHONY: edge-isolation
edge-isolation: ## Edge NetworkPolicy allow-list sweep (ARGS=--live probes the cluster)
	./scripts/edge-isolation-sweep.sh $(ARGS)

##@ Utilities

.PHONY: prereqs
prereqs: ## Check prerequisites (flux, kubectl, kind, helm, docker, tofu)
	@for bin in flux kubectl kind helm docker tofu; do \
	  if command -v $$bin >/dev/null 2>&1; then echo "  OK   $$bin"; \
	  else echo "  MISS $$bin"; fi; \
	done
	@$(MAKE) --no-print-directory kind-floor

.PHONY: help
help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
