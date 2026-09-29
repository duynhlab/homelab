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
e2e: e2e-saga e2e-smoke e2e-staff e2e-operator ## Run the k6 gate suite (set GATE=compose|kind)
# Order matters: saga runs FIRST. smoke's C6/K5.2 asserts all ten services have
# spans, and checkout/payment only emit once the saga drives the funnel. Both gates
# mandate a from-scratch stack, so smoke-before-saga fails that row every first run
# (measured on compose AND Kind, 2026-08-25).

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

.PHONY: e2e-conformance
e2e-conformance: ## Row C22: stop Weaver's live-check, save its report, fail on a violation (needs compose.weaver.yaml)
	@cd local-stack && curl -sf -X POST localhost:4320/stop -o .weaver-live-check.json \
	  && { docker compose -f compose.yaml -f compose.weaver.yaml wait weaver >/dev/null 2>&1 || true; }; \
	  code=$$(docker inspect -f '{{.State.ExitCode}}' local-stack-weaver-1); \
	  python3 -c "import json;s=json.load(open('.weaver-live-check.json'))['statistics'];print('C22 advice:',s.get('advice_level_counts'))"; \
	  if [ "$$code" = 0 ]; then echo 'C22 OK: every emitted name is in the registry'; else echo "C22 FAIL: weaver exit $$code — see local-stack/.weaver-live-check.json"; exit 1; fi

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
	GATE=compose k6 run scripts/k6/observability.js

.PHONY: e2e-ratelimit
e2e-ratelimit: ## Drive under and over the edge ceiling; 429 must be well-formed
	GATE=$(or $(GATE),kind) k6 run scripts/k6/ratelimit.js

.PHONY: e2e-load
e2e-load: ## Order load; reports the Temporal backlog it built
	GATE=$(or $(GATE),kind) k6 run scripts/k6/load.js

.PHONY: e2e-restock
e2e-restock: ## Top demo stock back up to the seed baseline (kind-seed.sh cannot -- ON CONFLICT DO NOTHING)
	GATE=$(or $(GATE),kind) k6 run scripts/k6/restock.js

##@ ClickHouse DDL image (ADR-077)

# The schema Job mounts this image as a volume. The digest in job.yaml must be
# what the SQL builds to, so every build here pins BuildKit and strips time:
# the same SQL gives the same digest on any machine and in CI
# (.github/workflows/clickhouse-ddl.yml uses the same three values).
DDL_DIR       := images/clickhouse-ddl
DDL_IMAGE     := ghcr.io/duynhlab/homelab/clickhouse-ddl
DDL_BUILDKIT  := moby/buildkit:v0.33.0@sha256:6c2fa84a6b61ccd72899dde4239f8d5717f05f9a8ca6f3cad185fb1a95a94de3
DDL_PLATFORMS := linux/amd64,linux/arm64
DDL_BUILDER   := clickhouse-ddl
DDL_OUT       := $(DDL_DIR)/.out/clickhouse-ddl.oci.tar
# Tag = hash of the SQL itself, so it names the content without depending on BuildKit.
DDL_TAG        = sql-$(shell cd $(DDL_DIR)/sql && sha256sum *.sql | sha256sum | cut -c1-12)

.PHONY: ddl-image
ddl-image: ## Build the DDL image reproducibly into an OCI tarball
	@docker buildx inspect $(DDL_BUILDER) >/dev/null 2>&1 || \
	  docker buildx create --name $(DDL_BUILDER) --driver docker-container \
	    --driver-opt image=$(DDL_BUILDKIT) >/dev/null
	@mkdir -p $(dir $(DDL_OUT))
	@SOURCE_DATE_EPOCH=0 docker buildx build --builder $(DDL_BUILDER) \
	  --platform $(DDL_PLATFORMS) --provenance=false --sbom=false \
	  --output type=oci,dest=$(DDL_OUT),rewrite-timestamp=true,name=$(DDL_IMAGE):$(DDL_TAG) \
	  --quiet $(DDL_DIR) >/dev/null

.PHONY: ddl-digest
ddl-digest: ddl-image ## Print the DDL image reference (tag@digest) for job.yaml
	@echo "$(DDL_IMAGE):$(DDL_TAG)@$$(tar -xOf $(DDL_OUT) index.json | jq -r '.manifests[0].digest')"

.PHONY: ddl-load
ddl-load: ddl-image ## Import the DDL image into every Kind node (pre-merge testing)
	@# Streamed over stdin: /tmp in a Kind node is a tmpfs, so a `docker cp` into
	@# it lands under the mount where ctr cannot see it.
	@# The digest name matters too: the kubelet resolves a tag@digest reference by
	@# its repo@digest form, and an import only creates the tag name -- without
	@# the second name IfNotPresent still pulls, from a registry that may not
	@# have the image yet.
	@digest=$$(tar -xOf $(DDL_OUT) index.json | jq -r '.manifests[0].digest'); \
	for n in $$(kind get nodes --name $${CLUSTER_NAME:-homelab}); do \
	  docker exec -i $$n ctr -n k8s.io images import --all-platforms - < $(DDL_OUT) >/dev/null && \
	  docker exec $$n ctr -n k8s.io images tag --force $(DDL_IMAGE):$(DDL_TAG) $(DDL_IMAGE)@$$digest >/dev/null && \
	  echo "  loaded into $$n ($$digest)"; \
	done

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
