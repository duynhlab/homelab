# GrpcServerHighErrorRate

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning

**Fires when**: Incoming gRPC error ratio >5% for 5 minutes (`rpc_server_call_duration_seconds_count`, status != OK).

## Diagnosis

### Possible causes
downstream DB failure surfacing on gRPC handler, validation bugs, dependency timeouts on east-west path.

### Investigation
```promql
sum by (app, rpc_response_status_code) (rate(rpc_server_call_duration_seconds_count{app="$APP"}[5m]))
```

Check calling service retry/saga behavior; correlate with HTTP error alerts on the caller.

## Mitigation

Fix callee handler or dependency; see [MicroserviceHighErrorRate.md](MicroserviceHighErrorRate.md) for HTTP-side triage.
