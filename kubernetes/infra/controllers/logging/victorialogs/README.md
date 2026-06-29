# VictoriaLogs

VictoriaLogs Single Node deployment for log storage and querying.

## Architecture

```mermaid
flowchart TD
    subgraph Sources["Log Sources"]
        K8s[Kubernetes Pods]
        CNPG[CloudNativePG Postgres]
    end

    subgraph Vector["Vector Agent (kube-system)"]
        KLogs[kubernetes_logs source]
        AddLabels[add_labels transform]
        ParsePG[parse_pg_json transform]
        FilterExplain[filter_pg_auto_explain]
        ParseExplain[parse_pg_auto_explain]
    end

    subgraph Sinks["Log Destinations"]
        VLogsAll[VictoriaLogs - All Logs]
        VLogsPlans[VictoriaLogs - PG Plans]
        VLogsFailures[VictoriaLogs - Parse Failures]
    end

    K8s --> KLogs
    CNPG --> KLogs
    
    KLogs --> AddLabels
    KLogs --> ParsePG
    
    AddLabels --> VLogsAll
    
    ParsePG --> FilterExplain
    FilterExplain --> ParseExplain
    ParseExplain --> VLogsPlans
    ParseExplain --> VLogsFailures
```

## Data Flow

```mermaid
flowchart LR
    subgraph Collection["Log Collection"]
        Vector[Vector Agent<br/>DaemonSet]
    end

    subgraph Storage["Log Storage"]
        VLogs[VictoriaLogs<br/>LogsQL]
    end

    subgraph Query["Query Interface"]
        Grafana[Grafana]
    end

    Vector -->|All Logs + PG Plans| VLogs
    VLogs --> Grafana
```

## Key Design Decisions

1. **Single Vector Agent**: One cluster-wide Vector DaemonSet ships to VictoriaLogs (the sole log backend; Loki was removed in v0.94.0)
2. **Collector Disabled**: VictoriaLogs embedded Vector/collector is disabled (`vector.enabled: false`)
3. **Single Backend**: VictoriaLogs is the only log sink — no second backend to operate

## Endpoints

| Endpoint | Port | Purpose |
|----------|------|---------|
| `/insert/jsonline` | 9428 | JSON Lines log ingestion |
| `/insert/elasticsearch` | 9428 | Elasticsearch-compatible bulk API |
| `/select/logsql/query` | 9428 | LogsQL query endpoint |
| `/health` | 9428 | Health check |

## Configuration

Key HelmRelease values:

```yaml
server:
  retentionPeriod: 7d
  persistentVolume:
    enabled: true
    size: 20Gi

# CRITICAL: Embedded collector disabled
vector:
  enabled: false
```

## Related Files

| File | Purpose |
|------|---------|
| `helmrelease.yaml` | VictoriaLogs HelmRelease |
| `../vector/vector.yaml` | Vector Agent with VictoriaLogs sinks |
| `docs/victorialogs/README.md` | Full documentation |

## References

- [VictoriaLogs Docs](https://docs.victoriametrics.com/victorialogs/)
- [VictoriaLogs Vector Setup](https://docs.victoriametrics.com/victorialogs/data-ingestion/vector)
- [VictoriaLogs Helm Chart](https://docs.victoriametrics.com/helm/victorialogs-single/)
