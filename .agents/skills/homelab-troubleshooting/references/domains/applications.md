# Applications (+ Temporal / KEDA)

Service RED/correctness incidents and the workflow layer that drives
fulfillment. Application *code* lives in service repos; here you diagnose the
deployed behavior and route the fix.

## Authoritative docs

- Per-alert + cross-signal workflows:
  [microservices runbooks](../../../../../docs/observability/runbooks/microservices/README.md).
- Service contracts and call graph: [api/api.md](../../../../../docs/api/api.md),
  [api/README.md § Service contracts](../../../../../docs/api/README.md#service-contracts).
- Shutdown contract: [api/graceful-shutdown.md](../../../../../docs/api/graceful-shutdown.md).

## Diagnose (cross-signal)

Use the correlation pivots in [evidence-correlation](../evidence-correlation.md):

- **5xx** → error-rate panel → `trace_id` from VictoriaLogs → errored span → DB
  vs downstream vs app code.
- **Slow** → P95/P99 → slowest span → DB query / GC / saturation → Pyroscope.
- **No traffic** → heartbeat, then `kubectl get endpoints -n <ns> <app>`,
  selector vs pod labels, then upstream health.

The decision trees already exist in the
[investigation workflows](../../../../../docs/observability/runbooks/microservices/README.md#investigation-workflows) —
link them, don't restate them.

## Temporal / KEDA

- Temporal server/worker/scaler alerts:
  [temporal runbooks](../../../../../docs/observability/runbooks/temporal/README.md).
- Autoscaler own-health: [keda runbooks](../../../../../docs/observability/runbooks/keda/README.md).
- Who owns replicas (KEDA + Worker Controller), the backlog signal, and the
  drill traps: [platform/worker-autoscaling.md](../../../../../docs/platform/worker-autoscaling.md).
- Workflows as built, saga vs 2PC, task queues:
  [api/temporal.md](../../../../../docs/api/temporal.md),
  [api/workflows.md](../../../../../docs/api/workflows.md).

A stuck order is usually a saga/worker/scaler question, not an HTTP one: check
worker versions, task-slot/backlog, and the scaler before the service's RED
panel.

## Boundary

Handler/business-logic fixes are service-repo changes, not homelab mitigations.
From homelab you can scale, roll, or route; code and unit tests belong to the
owning `*-service` repo. `docs/api/` is the contract truth.
