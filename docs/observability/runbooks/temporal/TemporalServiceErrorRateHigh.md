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
(sum(rate(service_error_with_type{service_name="frontend",
    error_type=~"serviceerror_(Internal|Unavailable|DeadlineExceeded|DataLoss|ResourceExhausted)"}[5m]))
  or vector(0))
/ clamp_min(sum(rate(service_requests{service_name="frontend"}[5m])), 1) > 0.02
```

More than 2% of the RPCs **clients** send to Temporal's frontend are failing with
a **server-side** error. This is the service layer, as distinct from
[TemporalPersistenceErrorRateHigh](TemporalPersistenceErrorRateHigh.md), which is
the database layer beneath it.

Two things the ratio deliberately leaves out:

- **Internal hops.** history and matching report their own `service_requests`
  and `service_error_with_type`. One client RPC fans out across them, so summing
  every service counts the same work several times and is not an error rate a
  client sees. A history or matching fault that matters reaches the client as an
  `Unavailable` or `DeadlineExceeded` at the frontend.
- **Control flow and caller errors.** `NotFound` is how the server answers "does
  this exist?", and `InvalidArgument`, `WorkflowExecutionAlreadyStarted`,
  `FailedPrecondition`, `NamespaceNotFound` and `Canceled` are the caller's doing.
  The rule is an **allowlist** of server faults, so a new client-side error type
  cannot make it noisy again.

Measured on Kind on 2026-10-02, before this rule: of 26,774 service errors in
24 h, 26,714 were `NotFound`, and 26,551 of those were `QueryWorkflow` between
history and matching, once every 30 s, with no frontend counterpart. The old
unfiltered ratio peaked at 27% and crossed 5% in 7 one-minute samples a day,
which a rollout or a k6 run could hold for the 10-minute `for`. Over the same
24 h this expression stays at 0.

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
topk(10, sum by (operation, error_type) (rate(service_error_with_type{service_name="frontend"}[5m])))
sum by (service_name, error_type) (rate(service_error_with_type{error_type!="serviceerror_NotFound"}[5m]))
```

The second query also shows faults on history and matching. They are expected
to explain a frontend `Unavailable` or `DeadlineExceeded`, and on their own they
do not page.

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
