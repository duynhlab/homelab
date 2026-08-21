# Kyverno Admission Alert Runbooks

Per-alert investigation guides for the policy engine. Four files cover four
alerts — the first signals Kyverno has ever had on this platform. Before
2026-08-21 the admission webhook that sits on the write path of every apply had
**no scrape, no dashboard, no alert and no runbook**, and the manifest read as if
metrics were solved: `metricsService` and `serviceMonitor` were set at the top
level of the Kyverno values, where chart 3.8.2 has no such keys. Helm accepted
them and ignored them.

| Quick facts | |
|---|---|
| Alert rules | [`prometheusrules/kyverno/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/kyverno/alerts.yaml) |
| Scrape | chart-native, one `serviceMonitor` per controller in [`kyverno/helmrelease.yaml`](../../../../kubernetes/infra/controllers/kyverno/helmrelease.yaml) — four jobs, `:8000` |
| Dashboard | chart-native `GrafanaDashboard` CR (`grafana.grafanaDashboard.create`) → **GitOps → Kyverno** |
| Policies | [`configs/kyverno/cluster-policies/`](../../../../kubernetes/infra/configs/kyverno/cluster-policies/) |
| Policy fixtures | [`configs/kyverno/tests/`](../../../../kubernetes/infra/configs/kyverno/tests/) — run by `make validate` |
| Alert catalog | [§ Kyverno admission](../../alerting/alert-catalog.md) |
| Policy catalog | [`security/policy-catalog.md`](../../../security/policy-catalog.md) |
| Exceptions | [`security/policy-exceptions.md`](../../../security/policy-exceptions.md) |

## Four controllers, four jobs, four different impacts

Read `{{ $labels.job }}` before anything else — the controllers fail
independently and only one of them can stop an apply:

| Job | Controller | What breaks when it stops |
|---|---|---|
| `kyverno-svc-metrics` | admission | **Can refuse admission.** `disallow-default-namespace` is `Enforce` + `failurePolicy: Fail` |
| `kyverno-background-controller-metrics` | background | `generate` rules stop — `default-deny-networkpolicy` no longer seeds new namespaces. Silent until a namespace is created |
| `kyverno-reports-controller-metrics` | reports | PolicyReports go stale. Findings stop updating, which looks like compliance |
| `kyverno-cleanup-controller-metrics` | cleanup | `cleanup-completed-pods` stops; finished Pods accumulate |

## Domain specifics

- **An `error` is not a verdict.** Four of the five validate policies run in
  `Audit`, where a `fail` is a report entry — and so is an `error`. On a
  dashboard the two are not distinguishable from a compliant resource unless you
  split by `rule_result`. This is why
  [KyvernoPolicyRuleErrors](./KyvernoPolicyRuleErrors.md) exists as its own
  alert rather than being folded into a failure-rate rule.
- **Kyverno is usually the symptom, not the cause.** It sits on the write path,
  so platform-level slowness reaches an operator as webhook timeouts, Flux
  dry-run `InternalError`s, and a chain of `dependency ... is not ready`
  messages that never mention admission. Check node disk and API-server latency
  before Kyverno itself — see
  [KyvernoAdmissionLatencyHigh](./KyvernoAdmissionLatencyHigh.md) for the
  2026-08-21 walkthrough of exactly that sequence.
- **Reproduce offline first.** `kyverno apply <policy> --resource <resource>` and
  the fixtures under `configs/kyverno/tests/` answer most questions in seconds
  without touching the cluster, and a fix that does not come with a fixture will
  regress.
- **`config.resourceFilters` is blast-radius control, not tuning.**
  `kube-system`, `flux-system`, `cert-manager` and `external-secrets-system` are
  excluded so a Kyverno failure cannot wedge Flux. Widening it to shed load
  silently removes policy coverage.

## Runbooks

| Alert(s) | Runbook | The question it answers |
|---|---|---|
| KyvernoControllerDown | [KyvernoControllerDown](./KyvernoControllerDown.md) | Which controller is gone, and can applies still land? |
| KyvernoAdmissionDenying | [KyvernoAdmissionDenying](./KyvernoAdmissionDenying.md) | What is being refused, and is the refusal correct? |
| KyvernoAdmissionLatencyHigh | [KyvernoAdmissionLatencyHigh](./KyvernoAdmissionLatencyHigh.md) | Is Kyverno slow, or waiting on something slower? |
| KyvernoPolicyRuleErrors | [KyvernoPolicyRuleErrors](./KyvernoPolicyRuleErrors.md) | Which rule stopped deciding, and what is now unprotected? |

_Last updated: 2026-08-21 — domain created with Kyverno's first alerts, scrape and dashboard._
