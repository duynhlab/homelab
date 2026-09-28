# Domain notes — what each homelab area's diagram must show

Short notes per platform area. Each says what a diagram of that area models,
what is easy to get wrong, and which relationship types it mostly uses. These
notes do not replace verifying against the manifests (SKILL.md step 2). They say
where to look and what a reviewer will ask about.

| Area | Model | Easy to get wrong | Mostly |
|---|---|---|---|
| **Edge / gateway** | Envoy Gateway, its Gateway + HTTPRoutes by hostname, Keycloak as the OIDC provider, TLS termination, JWT / CORS / rate-limit policies | Drawing a route the manifests do not have: hostnames come from `configs/envoy-gateway`, and one hostname can serve several backends | `traffic`, `trust` |
| **Kubernetes** | Cluster, namespaces as frames, workloads, Services, NetworkPolicies when the question is reachability, KEDA when it is scaling | Asserting a packet path without evidence. Kind uses kindnet, so NetworkPolicies are inert locally; say so rather than drawing them as enforced | `traffic`, `control`, `event` (scaling) |
| **GitOps / Flux** | Flux Kustomization waves, their `dependsOn`, each wave's gate (`wait` vs `healthChecks`), the OCI source each reads | Treating `wait: true` and `healthChecks` as both active (they are exclusive, and `wait` wins, AGENTS.md). Count the waves at run time; do not copy a number | `control` |
| **Observability** | Producers, collector pipelines, stores with retention, Grafana as the reader. Split signals when it helps (`signal` on telemetry edges) | Drawing retired Loki / Tempo / Jaeger, or a store's retention from memory: read `retentionPeriod`, the DDL TTL and the Pyroscope compactor | `telemetry`, `data` |
| **Databases** | CNPG clusters, poolers (PgDog for product-db, PgBouncer for platform-db), which service uses which (`db_host` in `apps/services/`), backups to RustFS, the DR replica | Services that bypass the pooler: Keycloak and Temporal connect to `platform-db-rw` directly, and migrations use the `-rw` host | `data`, `replication`, `control` |
| **Secrets / security** | OpenBao, External Secrets Operator, the Secrets it syncs, cert-manager + trust-manager for internal TLS, Kyverno admission | Showing a secret as flowing to a pod directly: ESO writes a Kubernetes Secret, which the pod mounts | `control`, `trust`, `dependency` |
| **Workflows** | Temporal server, the task queues, the workers that poll them, the services that start workflows | Arrow direction: a worker *polls* the server, so the edge starts at the worker | `traffic`, `event` |
| **Incident / RCA** | A causal chain, top-down: symptom → signal → affected component → contributing condition → root cause → mitigation → recovery | Mixing the causal chain with the topology. Draw the topology separately and link it | `dependency`, `event` |

Cloud provider boundaries (region / VPC / AZ) do not apply to this Kind-based
platform. If a diagram ever needs one, use the provider's official icons from
the Draw.io shape libraries, never a lookalike.
