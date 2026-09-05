# TemporalServiceErrorRateHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | workflow |
| **Source** | `kubernetes/infra/configs/temporal/prometheusrule.yaml` |
| **Metrics** | `service_error_with_type`, `service_requests` — Temporal server RPC layer |
| **Status** | active |
| **Dashboard** | Temporal → Server |
| **Local-stack** | present |

## Meaning

```promql
sum(rate(service_error_with_type[5m]))
  / clamp_min(sum(rate(service_requests[5m])), 1) > 0.05
```

More than 5% of Temporal's **RPC** calls are returning errors. This is the
service layer — frontend to history, history to matching, and clients to
frontend — as distinct from
[TemporalPersistenceErrorRateHigh](TemporalPersistenceErrorRateHigh.md), which is
the database layer beneath it.

The metric name is `service_error_with_type`. An earlier version of this rule
named `service_errors`, which returns no series; it was corrected on 2026-08-18
after being live-verified. Do not "simplify" it back.

## Impact

Callers retry, so low rates are absorbed. Sustained, it means workflow starts,
signals and queries intermittently fail, and the services that own them
(`checkout`, `order`) surface it as their own errors.

## Diagnosis

Split the ratio before doing anything else — the error type usually names the
cause:

```promql
topk(10, sum by (operation, error_type) (rate(service_error_with_type[5m])))
sum by (error_type) (rate(service_error_with_type[5m]))
```

Two error families to recognise:

| `error_type` | Meaning |
|---|---|
| `ResourceExhausted` with `BusyWorkflow` | A single workflow is being hammered — usually one hot workflow ID, not a server problem |
| `Unavailable`, `DeadlineExceeded` | Downstream trouble. Go to history and persistence |

```bash
kubectl logs -n temporal deploy/temporal-frontend --since=5m | grep -iE 'error|slow gRPC' | tail -20
kubectl logs -n temporal deploy/temporal-history  --since=2m | grep -c '"level":"error"'
```

A frontend log full of `history client encountered error` means the frontend is
healthy and reporting someone else's failure.

## Mitigation

1. `Unavailable` / `DeadlineExceeded` → work
   [TemporalPersistenceErrorRateHigh](TemporalPersistenceErrorRateHigh.md); this
   layer is reporting, not causing.
2. `BusyWorkflow` → find the workflow ID and ask why it is being driven so hard.
   That is an application question, in `checkout-service` or `order-service`.
3. A component missing entirely → [TemporalServerDown](TemporalServerDown.md).

## Escalation

Warning. Escalate together with persistence if both are firing — they are one
incident seen from two layers, and reporting them separately wastes the
responder's time.

## Related

- [TemporalPersistenceErrorRateHigh](TemporalPersistenceErrorRateHigh.md)
- [TemporalServerDown](TemporalServerDown.md)
- [TemporalWorkerRequestErrorRateHigh](TemporalWorkerRequestErrorRateHigh.md)

---
_Last updated: 2026-09-05 — created; the temporal alert group had no runbooks at all_
