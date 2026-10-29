# PyroscopeDown

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | [Rule manifest](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/observability/pyroscope-alerts.yaml) |
| **Metrics** | `up{job=~".*pyroscope.*"} == 0` |
| **Status** | active in repository configuration |
| **Validation** | Static comparison to rule and HelmRelease, 2026-10-23; no new runtime test |
| **Dashboard** | Observability → Profiling |
| **Local-stack** | Pyroscope is present; inspect Compose targets independently |

## Meaning

A matching scrape target has returned `up == 0` for five minutes. Identify the
actual target before diagnosing ingestion: Go services push profiles directly
via their SDK; a failed scrape of Pyroscope's own metrics does not by itself
prove those pushes stopped. Missing targets are not detected by this expression.

## Impact

Profiling supports debugging and performance analysis. Application request
handling does not depend on it; losing profiles reduces the evidence available
for a performance investigation.

A delivery outage can leave gaps needed for later performance investigation.
Measure backend freshness and client export failures to establish its extent.

## Diagnosis

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=pyroscope
kubectl -n monitoring logs -l app.kubernetes.io/name=pyroscope --tail=80
```

```promql
up{job=~".*pyroscope.*"}
count(up{job=~".*pyroscope.*"})       # compare with actual scrape targets
```

Pyroscope is a StatefulSet with a PVC on `standard` — the same local-path story
as everything else, so disk pressure on its node is a plausible cause.

## Mitigation

1. **OOM or disk** → inspect memory, metastore PVC and object-store access.
   Do not shorten retention or delete state before establishing the cause.
2. **Config or chart failure** → it is a HelmRelease;
   [FluxHelmReleaseNotReady](../gitops/FluxHelmReleaseNotReady.md).
3. Restore the failed path through its owning GitOps configuration. During a
   performance incident, loss of profiles may need immediate attention.

## Recovery validation

Confirm scrape recovery for two evaluation intervals and recent profiles for a
known active service. Test reading both the new window and retained data; a
healthy metrics endpoint alone does not prove ingest or query recovery.

## Escalation

Warning, and rarely worth escalating on its own. Fix it during normal hours.

## Related

- [FluxHelmReleaseNotReady](../gitops/FluxHelmReleaseNotReady.md)
- [VMServiceDown](../victoriametrics/VMServiceDown.md) — same shape, far higher
  stakes.
