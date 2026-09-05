# TemporalServerDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | workflow |
| **Source** | `kubernetes/infra/configs/temporal/prometheusrule.yaml` |
| **Metrics** | `up{job=~".*temporal.*"} == 0` |
| **Status** | active |
| **Dashboard** | Temporal → Server · Temporal Web (`temporal.duynh.me`) |
| **Local-stack** | present |

## Meaning

A Temporal server component has been unscraped for 5 minutes. The regex matches
exactly **four headless jobs**, all of them server roles:

| Job | Role |
|---|---|
| `temporal-frontend-headless` | The gRPC entry point every worker and client talks to |
| `temporal-history-headless` | Owns the 512 history shards and all workflow state |
| `temporal-matching-headless` | Task queues; also registers worker deployment versions |
| `temporal-worker-headless` | Temporal's **own system worker**, not an application worker |

The application workers (`checkout-worker`, `order-worker`) are deliberately
**not** matched — their metrics arrive by OTLP without a `temporal-*` job label —
so this alert is about the server, exactly as its name says.

## Impact

Depends entirely on which component, and they are not equivalent:

- **frontend** — nothing can reach Temporal. Workers cannot poll, `checkout` and
  `order` cannot start workflows.
- **history** — workflow state is unavailable; running workflows stall. The most
  damaging of the four.
- **matching** — task dispatch stops; workers poll into silence.
- **worker** (system) — Temporal's internal maintenance stops. Least urgent, and
  easy to misread as an application worker outage.

Workflows are durable: a component returning restores progress rather than
losing it. What is lost is time, and any activity that times out meanwhile.

## Diagnosis

```bash
kubectl get pods -n temporal -o wide
kubectl describe pod -n temporal <pod> | tail -30
kubectl logs -n temporal <pod> --previous --tail=50
```

### The failure this platform actually sees on a cold bring-up

Every component crashlooping at once with:

```
sql schema version compatibility check failed:
  pq: relation "schema_version" does not exist
```

is **not** an outage. The services start before the `temporal-schema` Job has
created the schema and exit 1; they succeed on retry once it completes. Expect 2
to 4 restarts on each of frontend, history, matching and worker during a cold
`make up`. Confirm with `reason: Error` and `exitCode: 1` — not `OOMKilled`:

```bash
kubectl get pods -n temporal -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.containerStatuses[0].lastState}{"\n"}{end}'
```

### PromQL

```promql
up{job=~".*temporal.*"} == 0
count(up{job=~".*temporal.*"})        # should be 4
```

## Mitigation

1. **Cold bring-up, schema race** → wait for `temporal-schema` to complete. No
   action needed.
2. **Crashloop with another reason** → read the log; check
   [FluxHelmReleaseNotReady](../gitops/FluxHelmReleaseNotReady.md), since Temporal
   is a HelmRelease.
3. **Pod running but unscraped** → this is a monitoring failure, not an outage.
   Check the ServiceMonitor and whether the pod's metrics port answers.
4. **history specifically** → give it room. It carries all 512 shards and is
   sized differently from its siblings for that reason; the others sit at a
   fraction of the same memory limit.

## Escalation

Critical. Name the component when you escalate — "Temporal is down" is four
different incidents with different urgencies, and history is the one that
matters most.

## Related

- [TemporalServiceErrorRateHigh](TemporalServiceErrorRateHigh.md) — degraded
  rather than absent.
- [TemporalPersistenceErrorRateHigh](TemporalPersistenceErrorRateHigh.md) — the
  database-facing cause that often precedes a component failing.
- [FluxHelmReleaseNotReady](../gitops/FluxHelmReleaseNotReady.md)

---
_Last updated: 2026-09-05 — created; the temporal alert group had no runbooks at all_
