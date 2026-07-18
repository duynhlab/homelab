# GrpcServerHighLatencyP95

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning

Fires when P95 gRPC server latency >500ms for 10 minutes. East-west budget is
tighter than edge HTTP — high gRPC latency compounds into edge P95.

## Diagnosis

```promql
histogram_quantile(0.95, sum by (app, le) (rate(rpc_server_call_duration_seconds_bucket{app="$APP"}[5m])))
```

Use Tempo to find slow RPC spans; check DB client metrics (`db_client_operation_*`).

## Resolution

Same as [MicroserviceHighLatencyP95.md](MicroserviceHighLatencyP95.md) but scoped to gRPC handlers.
