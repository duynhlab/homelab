# Verify telemetry on Linux Kind

Hand this checklist to the Linux operator to turn the
[2026-10-23 static audit](../audits/2026-10-23-telemetry-implementation.md)
into runtime evidence. It supplements the canonical
[Kind K0–K6 gate](../../platform/kind-e2e-audit.md); it does not replace its
commands or the Compose release prerequisite.

| Item | Requirement |
|---|---|
| Environment | Disposable Linux Kind, Docker, bash; use the repository's tool prerequisites |
| Baseline | Record homelab SHA, manifest pins, pod image IDs and worker versions |
| Outcome | Baseline gate result plus per-finding observations; reproducing a defect is not a healthy PASS |
| Safety | Run baseline before fault injection; use synthetic data only; collect evidence before teardown |
| Status | Procedure reviewed statically on 2026-10-23; this document records no new runtime pass |

## 1. Establish the candidate and machine

- [ ] Transfer/check out the agreed homelab revision including these docs. Record
  dirty state; a local report in another machine's worktree is not automatically
  available on Linux. Do not silently upgrade pins while testing.
- [ ] Run K0 fully: Docker, tool versions, free ports, DNS/hosts, egress and image
  architecture. Use actual active manifests for counts, not historical prose.
- [ ] Confirm the cluster is disposable. For an existing `homelab` cluster,
  `make down` deletes the cluster **and registry**; preserve required evidence
  first. Use a fresh cluster for release qualification.

Run in bash from the repository root. These commands only capture the starting
state and validate manifests; output goes outside the checkout:

```bash
set -o pipefail
EVIDENCE_DIR="$(mktemp -d /tmp/homelab-telemetry-kind.XXXXXX)"
printf '%s\n' "$EVIDENCE_DIR"
git rev-parse HEAD > "$EVIDENCE_DIR/homelab-sha.txt"
git status --short > "$EVIDENCE_DIR/git-status.txt"
uname -a > "$EVIDENCE_DIR/host.txt"
make prereqs 2>&1 | tee "$EVIDENCE_DIR/prereqs.log"
make validate 2>&1 | tee "$EVIDENCE_DIR/validate.log"
```

**Expected:** both make commands exit zero. Stop on failure. `make prereqs`
does not cover every validation/browser tool; K0 is still required. Never enable
shell tracing around tokens, credentials or bootstrap secrets.

## 2. Bring up and prove delivery

- [ ] Run `make up` following K1. Flux bootstrap goes through OpenTofu.
- [ ] Check all intended Kustomizations, HelmReleases, workloads and dependencies
  are Ready. Count resources from the active Kustomize tree.
- [ ] Run `scripts/kind-seed.sh`; verify seed results and the K1 inventory stock
  prerequisite. Inspect both WorkerDeployments' Current/Target state; do not
  manually activate a worker version that the controller owns.
- [ ] Complete K2 image↔pin comparison for APIs, workers, mockpay and frontends.
  Record `.status.containerStatuses[].imageID` as well as configured image tags.
  A source tag does not attest the binary inside an image.
- [ ] Complete K3 admission, secrets and isolation, then K4 real TLS edge and
  browser flows. A direct ClusterIP request does not qualify the edge gate.

Capture safe resource summaries after bring-up:

```bash
kubectl config current-context > "$EVIDENCE_DIR/context.txt"
kubectl get nodes -o wide > "$EVIDENCE_DIR/nodes.txt"
flux get kustomizations -A > "$EVIDENCE_DIR/flux.txt"
kubectl get pods -A -o json | jq '[.items[] | {
  namespace: .metadata.namespace, pod: .metadata.name,
  containers: [.status.containerStatuses[]? | {
    name, image, imageID, ready, restartCount
  }]
}]' > "$EVIDENCE_DIR/images.json"
```

**Expected:** intended versions match pins, workers receive work, no unexplained
CrashLoop/OOM or missing Ready condition. F06 must be evaluated against these
actual images, not the service repository's latest main.

## 3. Run the baseline and inspect all signals

After K1–K4 prerequisites and seed, run the suite in its existing order (saga
before smoke produces the telemetry smoke expects):

```bash
make e2e GATE=kind 2>&1 | tee "$EVIDENCE_DIR/e2e.log"
make e2e-ratelimit GATE=kind 2>&1 | tee "$EVIDENCE_DIR/ratelimit.log"
cp -R scripts/k6/out "$EVIDENCE_DIR/k6-out"
```

- [ ] Preserve exit codes and each failed assertion; do not hide an initial
  failure with only the final retry's result.
- [ ] Complete K5's manual rows too: edge-root traces and downstream parenting,
  all intended producers, both log paths and correlation, API/worker identity,
  metrics freshness, profiles and actual dashboard panel queries.
- [ ] Record one synthetic journey's UTC window and trace ID. Verify the same
  trace in VictoriaTraces and ClickHouse; correlate application logs in
  VictoriaLogs and ClickHouse. Edge access logs are ClickHouse-only.
- [ ] Verify profile lookup by service/time; do not expect a Tempo-style
  one-click trace-to-profile button from the VictoriaTraces datasource.
- [ ] Inspect Collector config acceptance, restarts, memory, scrape health,
  export counters and loaded alert rules. Capture query text and result, not
  only a screenshot of a green dashboard.

**Expected:** every applicable mandatory K0–K6 row passes for an eligible full
Kind gate. If the Compose prerequisite was not run on the same candidate,
report a diagnostic Kind run, not release eligibility. Intentional test errors
may fire real alerts: record their causal test/window and recovery.

## 4. Verify audit findings separately

The following rows add focused evidence. Use the existing service API contracts
for routes and auth; do not invent endpoints. Fault scenarios run only on the
disposable cluster, after baseline capture. Before each fault, record the target,
original setting, maximum duration, stop condition and restoration command;
Flux reconciliation must be accounted for. Do not improvise database corruption
to trigger an application branch.

| Row | Scenario | Healthy acceptance | Evidence / current limitation |
|---|---|---|---|
| T01 / F01 | Cause a controlled unexpected dependency failure in a real logic operation; also exercise an expected business rejection | Unexpected manual span is Error with bounded type; expected rejection has outcome, not infrastructure Error | Trace JSON + operation/error class; HTTP 500 alone proves neither |
| T02 / F02 | Controlled provider fixture returns an error containing a unique synthetic secret marker | Marker absent from span/event/status and both log stores; safe class remains | Fixture payload and sanitized query results; requires a reviewed provider fixture, otherwise NOT RUN |
| T03 / F03 | Fail checkout idempotency Finish once after successful order creation, then retry same key | One order; one confirmed increment for that completion | Requires targeted test harness; ordinary repeated successful requests do not exercise this branch. Keep unit repro as evidence if NOT RUN on Kind |
| T04 / F04 | Send synthetic baggage through real gateway to a controlled outbound receiver | Unapproved baggage absent at external boundary; approved trace context retained | Edge acceptance plus receiver capture; never send marker to a real external provider |
| T05 / F05 | Invoke user GetUser through its actual instrumented entry point | Repository/DB child parent is the logic span | Exported parent IDs, not just a shared trace ID |
| T06 / F06 | Terminate API and worker while bounded work drains | Stop record precedes flush; independent telemetry budget; exit within grace | Actual image digest, termination settings and timestamps; old pins may reproduce known defect |
| T07 / F07–F08 | Product enrichment dependency failure; controlled mockpay callback | One decision error log; degraded outcome classified; callback parent or link | Application logs separately from access logs; callback trace relationship |
| T08 / F09,F13 | Short, controlled sink outage then restoration | Export/queue behavior observable; alert behavior matches loaded rules; backlog recovery measured | Time series before/during/after, known sent/received counts; no durability claim from an empty queue alone |
| T09 / F12 | Probe OTLP/debug access from designated allowed and denied namespaces | Behavior matches a recorded trust policy; permissions verified | Current broad lab boundary is a finding, not a newly enforced deny policy |
| T10 / F15,F17 | Inventory gRPC and Backoffice requests | Scope follows contract; Backoffice emits HTTP span/RED if fixed | Current release is expected to retain the documented HTTP gap |
| T11 / F14 | Inspect conformance report and required producers | Exact producer/attribute coverage and exclusions stated | Compose C22 is a separate gate; do not run its compose-only target and call it Kind evidence |

F10 is CI policy evidence and F11 is Compose configuration; Kind cannot close
those findings. Mark tests without an executable fixture **NOT RUN** with the
missing prerequisite. A reproducible known defect is **REPRODUCED**, not PASS.

## 5. Restore and return evidence

- [ ] Restore every temporary fault and confirm Flux convergence, traffic and
  telemetry recovery before taking the final snapshot.
- [ ] Fill K6's canonical evidence block. Add this table for the focused audit:

| Row | UTC window | Candidate / image digest | Result | Query, trace or artifact | Cleanup / remaining gap |
|---|---|---|---|---|---|
| T01–T11 (one row each) | | | PASS / FAIL / REPRODUCED / NOT RUN | | |

- [ ] Include the SHA, image table, exact commands/exit codes, k6 output, Collector
  startup/config errors, relevant sanitized traces/logs/metrics and unresolved
  failures. Do not export Secret objects, bearer tokens or raw sensitive logs.
- [ ] Keep the evidence directory outside the cluster. When investigation is
  finished, perform K6 teardown with `make down`; report whether it was done.

The recipient should be able to distinguish: what ran, which binary ran it,
what was observed, what remains untested, and whether the cluster was restored.
