# KyvernoControllerDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | availability |
| **Source** | [`kyverno/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/kyverno/alerts.yaml) |
| **Metrics** | `up{job=~"kyverno-.*-metrics\|kyverno-svc-metrics"}`, `kyverno_info` — from the chart's per-controller ServiceMonitors ([`kyverno/helmrelease.yaml`](../../../../kubernetes/infra/controllers/kyverno/helmrelease.yaml)) |
| **Status** | active |
| **Dashboard** | GitOps → Kyverno |
| **Local-stack** | not present — no Kubernetes admission layer in the compose stack |

## Meaning

One of Kyverno's four controllers has been unreachable for 5 minutes, or the
whole `kyverno_*` scrape is absent. The `absent(kyverno_info)` half is not
redundant: it is the only thing that catches the scrape **disappearing**, which
is a real regression mode here. Until 2026-08-21 this repo set
`metricsService` / `serviceMonitor` at the **top level** of the Kyverno values,
where chart 3.8.2 has no such keys — Helm accepted them, ignored them, and the
cluster ran with zero ServiceMonitors while the manifest read as if metrics were
solved. `up == 0` cannot see a target that was never created.

Four jobs exist, one per controller: `kyverno-svc-metrics` (admission),
`kyverno-background-controller-metrics`, `kyverno-cleanup-controller-metrics`,
`kyverno-reports-controller-metrics`. Which one is down changes the impact
completely — read `{{ $labels.job }}` first.

## Impact

Depends on the controller:

- **Admission** (`kyverno-svc-metrics`) is the serious one.
  `disallow-default-namespace` runs `validationFailureAction: Enforce` with
  `failurePolicy: Fail`, so a dead admission webhook does not merely stop
  policing — the API server can **refuse** admission for covered resources.
  `config.resourceFilters` and `excludeKyvernoNamespace` keep `kube-system`,
  `flux-system`, `cert-manager` and `external-secrets-system` out of the
  webhook, which is what stops this from wedging the platform outright.
- **Background** — `generate` and mutate-existing rules stop reconciling, so
  `default-deny-networkpolicy` will not seed NetworkPolicies into new
  namespaces. Silent until someone creates a namespace.
- **Reports** — PolicyReports go stale. Audit findings simply stop updating,
  which looks exactly like compliance.
- **Cleanup** — `cleanup-completed-pods` stops, so finished Pods accumulate.

## Diagnosis

### PromQL

```promql
up{job=~"kyverno-.*-metrics|kyverno-svc-metrics"} == 0 or absent(kyverno_info)

# Which controllers are scraped at all — should be 4
count(up{job=~"kyverno-.*-metrics|kyverno-svc-metrics"})

# Is it the pod or the scrape? kyverno_info carries the version per job
count by (job) (kyverno_info)
```

If `count(up{...})` is **less than 4**, suspect the scrape objects before the
pods.

### Grafana

- **GitOps → Kyverno** — the chart-provisioned board; the admission panels go
  flat rather than red when the controller is gone.

### kubectl / logs

```bash
JOB="<from the alert's job label>"

kubectl -n kyverno get pods
kubectl -n kyverno get svc | grep metrics          # four -metrics Services, :8000
kubectl -n kyverno get servicemonitor              # four, one per controller
kubectl get vmservicescrape -n kyverno             # the converted form VMAgent reads

# If the Services and ServiceMonitors exist but no series arrive, the scrape is
# failing rather than missing:
kubectl -n monitoring port-forward svc/vmagent-victoria-metrics 18429:8429 &
curl -s localhost:18429/api/v1/targets | jq '.data.activeTargets[]
  | select(.labels.job | test("kyverno")) | {job: .labels.job, health, lastError}'

kubectl -n kyverno logs -l app.kubernetes.io/component=admission-controller --tail=100
kubectl -n kyverno describe pod -l app.kubernetes.io/component=admission-controller | tail -30
```

### VictoriaLogs / traces

```logsql
_time:30m namespace:"kyverno" level:~"error|ERROR" | limit 50
```

## Mitigation

1. **Confirm whether admission is actually being refused** before touching
   anything — a background/reports/cleanup outage needs no urgency:
   ```bash
   kubectl -n kyverno get pods
   kubectl auth can-i create pods -n product     # then try a harmless dry-run apply
   ```
2. If a controller is `CrashLoopBackOff`, read why. During the 2026-08-21 disk
   incident the webhook was **healthy** and merely slow — the symptom was
   `context deadline exceeded` on the API server side, not a dead pod. Check
   node disk and `DiskPressure` before blaming Kyverno.
3. Let Flux restore it: `flux reconcile kustomization controllers-local`.
4. If the scrape is missing rather than the pod, check the values nesting —
   `serviceMonitor` belongs under each of the four controllers, never at the top
   level. `yq '.spec.values.admissionController.serviceMonitor' …` must not be
   `null`.

**Do not** delete the `MutatingWebhookConfiguration` or
`ValidatingWebhookConfiguration` to "unblock" an apply. The other runbooks say
the same thing ([`KubeAPIServerHighLatency`](../kubernetes/KubeAPIServerHighLatency.md)):
it removes the guardrail cluster-wide, Flux recreates it minutes later, and
whatever landed in the gap is unpoliced.

## Escalation

**Page** when the job is `kyverno-svc-metrics` and applies are being refused —
that is an admission outage on the write path. **Ticket** for background,
reports or cleanup, and for a missing scrape with healthy pods (no signal is
not an outage, but it is how outages get missed).

If `KubeAPIServerHighLatency` or a disk alert co-fires, Kyverno is the
**symptom**: fix the platform first. That ordering is not theoretical — it is
exactly what happened on 2026-08-21.

## Related

```bash
git log --oneline -5 -- kubernetes/infra/controllers/kyverno/helmrelease.yaml
```

- [KyvernoAdmissionLatencyHigh](./KyvernoAdmissionLatencyHigh.md) — the slow
  form of this failure, and the one that actually happened.
- [KyvernoAdmissionDenying](./KyvernoAdmissionDenying.md) — the webhook is up
  and refusing on purpose.
