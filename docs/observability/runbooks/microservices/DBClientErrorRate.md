# DBClientErrorRate

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
`db_client_operation_errors_total` grows >0.1/s for 5 minutes (otelpgx counts every non-`ErrNoRows` operation error).

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Diagnosis
### Possible causes
Postgres down/failing over, pooler (PgDog) unhealthy, statement timeouts, schema drift (SQLSTATE 42xxx), connection storms.

### Investigation
service logs carry the SQLSTATE on the query span (`pgx.sql_state` attribute); check CNPG cluster status and PgDog logs; correlate with `MicroserviceHighErrorRate` — DB errors usually surface as 5xx.
