# 3-Layer Architecture & APM Integration

## Quick Summary

**Objectives:**
- Understand the 3-layer architecture (web → logic → core)
- Learn how APM integrates at each layer
- Visualize data flow and correlation patterns

**Learning Outcomes:**
- Clean architecture principles (separation of concerns)
- Middleware chain ordering and responsibilities
- APM data flow through layers
- Trace, log, metric, and profile correlation
- Mermaid diagram creation for architecture visualization

**Keywords:**
3-Layer Architecture, Clean Architecture, Web Layer, Logic Layer, Core Layer, Middleware Chain, APM Integration, Data Flow, Correlation, Mermaid Diagrams

**Technologies (current stack):**
- Gin (HTTP framework)
- OpenTelemetry SDK + OTel Collector (tracing pipeline)
- Tempo (trace storage, queried by Grafana)
- Jaeger (secondary trace UI, fed from OTel Collector)
- Zap (structured JSON logging)
- Vector (DaemonSet log shipper)
- VictoriaLogs / VLSingle (log storage, replaces Loki)
- VictoriaMetrics — VMAgent (scrape) + VMSingle (storage) + VMAlert + VMAlertmanager (replaces Prometheus)
- Pyroscope (continuous profiling, push-based from services)
- Grafana (single UI for traces, logs, metrics, profiles)
- Mermaid (diagram syntax)

> Note: `prometheus-operator-crds` is installed only so VictoriaMetrics Operator can transparently consume `ServiceMonitor` / `PodMonitor` / `PrometheusRule` resources — there is no Prometheus server running.

## Overview

This document visualizes the 3-layer architecture (web → logic → core) and how APM (Application Performance Monitoring) integrates with each layer to provide comprehensive observability.

## 3-Layer Architecture

### Code Structure

The codebase follows a clean 3-layer architecture pattern:

```mermaid
graph TD
    A[HTTP Request] --> B[Gin Router]
    B --> C[Middleware Chain]

    C --> D[TracingMiddleware<br/>Creates root span]
    D --> E[LoggingMiddleware<br/>Extracts trace-id]
    E --> F[MetricsMiddleware<br/>Records HTTP metrics]

    F --> H[Web Layer v1<br/>web/v1/handler.go]

    H --> J[Parse Request<br/>Validate Input<br/>Create Web Span]

    J --> L[Logic Layer v1<br/>logic/v1/service.go]

    L --> N[Business Logic<br/>Create Logic Span<br/>Cache-Aside]

    N --> O[Core Layer<br/>core/domain/<br/>core/database.go<br/>core/cache/]

    O --> P[Return Result]
    P --> Q[Format Response]
    Q --> R[HTTP Response]

    style D fill:#e1f5ff
    style E fill:#fff4e1
    style F fill:#ffe1f5
    style J fill:#e1ffe1
    style N fill:#ffe1e1
    style O fill:#f0e1ff
```

## APM Integration

### Observability Data Collection

APM collects four types of observability data at different layers:

1. **Traces** - OTLP spans at each layer, exported to OTel Collector → Tempo (+ Jaeger)
2. **Logs** - Structured JSON logs to stdout, scraped by Vector DaemonSet → VictoriaLogs
3. **Metrics** - `/metrics` endpoint scraped by VMAgent → VMSingle
4. **Profiles** - Continuous CPU / heap / goroutine profiles pushed from the Go SDK → Pyroscope

### Mermaid Diagram: APM Data Flow

#### Option 1: Top-Bottom Central Flow

Request flow goes top to bottom in center, APM components branch out to the right.

```mermaid
graph TB
    subgraph REQ[" "]
        A[HTTP Request] --> B[Middleware]
        B --> C[Web Layer]
        C --> D[Logic Layer]
        D --> E[Core Layer]
        E --> F[Response]
    end

    B -->|Creates| T1[Root Span<br/>HTTP Request]
    C -->|Creates| T2[Web Span<br/>layer=web]
    D -->|Creates| T3[Logic Span<br/>layer=logic]
        T1 --> T2
        T2 --> T3
        T3 --> OTEL[OTel Collector<br/>OTLP gRPC :4317]
        OTEL --> TEMPO[Tempo<br/>Trace Storage]
        OTEL --> JAEGER[Jaeger<br/>Trace UI]

    B -->|stdout JSON| L1[Request Log<br/>trace-id]
    C -->|stdout JSON| L2[Handler Log<br/>trace-id]
    D -->|stdout JSON| L3[Business Log<br/>trace-id]
        L1 --> VECTOR[Vector DaemonSet<br/>kubernetes_logs source]
        L2 --> VECTOR
        L3 --> VECTOR
        VECTOR --> VLOGS[VictoriaLogs<br/>VLSingle]

    B -->|/metrics| M1[HTTP Metrics<br/>duration, total, in_flight]
        M1 --> VMAGENT[VMAgent<br/>Scraper]
        VMAGENT --> VMSINGLE[VMSingle<br/>Metrics Storage]
        VMSINGLE --> VMALERT[VMAlert + VMAlertmanager]

    B -->|push| P1[CPU Profile]
    C -->|push| P2[Heap Profile]
    D -->|push| P3[Goroutine Profile]
        P1 --> PYRO[Pyroscope<br/>Continuous Profiling]
        P2 --> PYRO
        P3 --> PYRO

    style A fill:#f9f9f9
    style B fill:#f9f9f9
    style C fill:#f9f9f9
    style D fill:#f9f9f9
    style E fill:#f9f9f9
    style F fill:#f9f9f9
    style T1 fill:#e1f5ff
    style T2 fill:#e1f5ff
    style T3 fill:#e1f5ff
    style OTEL fill:#90caf9
    style TEMPO fill:#b3e5fc
    style JAEGER fill:#b3e5fc
    style L1 fill:#fff4e1
    style L2 fill:#fff4e1
    style L3 fill:#fff4e1
    style VECTOR fill:#e1bee7
    style VLOGS fill:#ffe0b2
    style M1 fill:#ffe1f5
    style VMAGENT fill:#f8bbd0
    style VMSINGLE fill:#f8bbd0
    style VMALERT fill:#f48fb1
    style P1 fill:#e1ffe1
    style P2 fill:#e1ffe1
    style P3 fill:#e1ffe1
    style PYRO fill:#c8e6c9
```

#### Option 2: Two-Column Layout (Recommended)

Left column shows request processing flow, right column shows APM data collection with clear horizontal connections.

```mermaid
graph LR
    subgraph LEFT["Request Processing Flow"]
        A[HTTP Request] --> B[Middleware]
        B --> C[Web Layer]
        C --> D[Logic Layer]
        D --> E[Core Layer]
        E --> F[Response]
    end

    subgraph RIGHT["APM Data Collection"]
        subgraph TRACE["🔵 Tracing (OpenTelemetry)"]
            T1[Root Span] --> T2[Web Span]
            T2 --> T3[Logic Span]
            T3 --> OTEL[OTel Collector]
            OTEL --> TEMPO[Tempo]
            OTEL --> JAEGER[Jaeger]
        end

        subgraph LOG["🟠 Logging (Zap → Vector → VictoriaLogs)"]
            L1[Request Log] --> VECTOR[Vector DaemonSet]
            L2[Handler Log] --> VECTOR
            L3[Business Log] --> VECTOR
            VECTOR --> VLOGS[VictoriaLogs]
        end

        subgraph METRIC["🟣 Metrics (VictoriaMetrics)"]
            M1["/metrics endpoint"] --> VMAGENT[VMAgent]
            VMAGENT --> VMSINGLE[VMSingle]
            VMSINGLE --> VMALERT[VMAlert + AM]
        end

        subgraph PROF["🟢 Profiling (Pyroscope, push)"]
            P1[CPU Profile] --> PYRO[Pyroscope]
            P2[Heap Profile] --> PYRO
            P3[Goroutine Profile] --> PYRO
        end
    end

    B -->|Creates| T1
    C -->|Creates| T2
    D -->|Creates| T3

    B -->|stdout| L1
    C -->|stdout| L2
    D -->|stdout| L3

    B -->|exposes| M1

    B -->|pushes| P1
    C -->|pushes| P2
    D -->|pushes| P3

    style A fill:#f9f9f9
    style B fill:#f9f9f9
    style C fill:#f9f9f9
    style D fill:#f9f9f9
    style E fill:#f9f9f9
    style F fill:#f9f9f9
    style T1 fill:#e1f5ff
    style T2 fill:#e1f5ff
    style T3 fill:#e1f5ff
    style OTEL fill:#90caf9
    style TEMPO fill:#b3e5fc
    style JAEGER fill:#b3e5fc
    style L1 fill:#fff4e1
    style L2 fill:#fff4e1
    style L3 fill:#fff4e1
    style VECTOR fill:#e1bee7
    style VLOGS fill:#ffe0b2
    style M1 fill:#ffe1f5
    style VMAGENT fill:#f8bbd0
    style VMSINGLE fill:#f8bbd0
    style VMALERT fill:#f48fb1
    style P1 fill:#e1ffe1
    style P2 fill:#e1ffe1
    style P3 fill:#e1ffe1
    style PYRO fill:#c8e6c9
```

## Complete System Flow

### End-to-End Request with APM

This diagram shows the complete flow from HTTP request to APM data collection. Tracing and profiling are out-of-band: spans go through the OTel Collector before reaching Tempo/Jaeger, log lines hit stdout and are picked up by the Vector DaemonSet, and metrics are pull-based via VMAgent scrapes.

```mermaid
sequenceDiagram
    participant Client
    participant Gin as Gin Router
    participant MW as Middleware Chain
    participant Web as Web Layer
    participant Logic as Logic Layer
    participant Core as Core Layer
    participant OTel as OTel Collector
    participant Tempo
    participant Vector as Vector DaemonSet
    participant VLogs as VictoriaLogs
    participant VMAgent
    participant VMSingle
    participant Pyro as Pyroscope

    Client->>Gin: HTTP Request
    Gin->>MW: Route to handler

    Note over MW: TracingMiddleware
    MW->>MW: Create root span
    MW->>OTel: Export span (OTLP gRPC)

    Note over MW: LoggingMiddleware
    MW->>MW: Extract trace-id
    MW->>MW: Create logger with trace-id
    MW-->>Vector: stdout JSON line (request)

    Note over MW: MetricsMiddleware
    MW->>MW: Record HTTP metrics

    MW->>Web: Call handler

    Note over Web: web/v1/handler.go
    Web->>Web: Parse & validate request
    Web->>Web: Create web layer span
    Web->>OTel: Export span
    Web-->>Vector: stdout JSON line (handler)
    Web->>Logic: Call business logic

    Note over Logic: logic/v1/service.go
    Logic->>Logic: Execute business rules
    Logic->>Logic: Create logic layer span
    Logic->>OTel: Export span
    Logic-->>Vector: stdout JSON line (business)
    Logic->>Core: DB / cache via repository

    Note over Core: core/domain, database.go, cache/
    Core-->>Logic: Return domain objects

    Logic-->>Web: Return business result
    Web-->>Vector: stdout JSON line (handler exit)
    Web-->>MW: Return response

    MW-->>Vector: stdout JSON line (response)
    MW->>OTel: Complete root span
    MW-->>Gin: Response ready
    Gin-->>Client: HTTP Response

    Note over OTel,Tempo: OTel Collector fan-out
    OTel->>Tempo: otlp/tempo (4317)

    Note over Vector,VLogs: Vector ships parsed lines
    Vector->>VLogs: HTTP ingest (VictoriaLogs sink)

    Note over VMAgent,VMSingle: Pull-based metrics
    VMAgent->>MW: GET /metrics (every 30s)
    VMAgent->>VMSingle: Remote write

    Note over Pyro: Continuous profiling (push)
    MW->>Pyro: CPU / heap / goroutine samples
```

## Layer Responsibilities

### Web Layer (`web/v1/`)

**Responsibilities:**
- HTTP request/response handling
- Input validation and parsing
- HTTP status code mapping
- Error formatting
- Create web layer spans for tracing
- Log HTTP-level events with trace-id

**APM Integration:**
- **Traces**: Creates spans with `layer=web` attribute (exported via OTel Collector → Tempo)
- **Logs**: Logs request/response as JSON on stdout with trace-id (collected by Vector → VictoriaLogs)
- **Metrics**: HTTP metrics collected by middleware and scraped by VMAgent (not in web layer)

**Example:**
```go
func Login(c *gin.Context) {
    // Create span for web layer
    ctx, span := middleware.StartSpan(c.Request.Context(), "http.request",
        trace.WithAttributes(attribute.String("layer", "web")))
    defer span.End()

    // Get logger with trace-id
    logger := middleware.GetLoggerFromContext(c, baseLogger)

    // Parse request
    var req domain.LoginRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        logger.Error("Invalid request", zap.Error(err))
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    // Call logic layer
    result, err := authService.Login(ctx, req)
    // ... handle response
}
```

### Logic Layer (`logic/v1/`)

**Responsibilities:**
- Business logic implementation
- Data validation and transformation
- Business rule enforcement
- Cache-Aside pattern against Valkey for read-heavy paths
- Create logic layer spans for tracing
- Log business-level events with trace-id

**APM Integration:**
- **Traces**: Creates spans with `layer=logic` attribute
- **Logs**: Logs business logic execution with trace-id
- **Metrics**: Can create custom business metrics (exposed on the same `/metrics` endpoint scraped by VMAgent)
- **Profiles**: Business logic appears in CPU/heap profiles pushed to Pyroscope

**Example:**
```go
func (s *AuthService) Login(ctx context.Context, req domain.LoginRequest) (*domain.AuthResponse, error) {
    // Create span for business logic layer
    ctx, span := middleware.StartSpan(ctx, "auth.login",
        trace.WithAttributes(attribute.String("layer", "logic")))
    defer span.End()

    // Business logic
    if req.Username == "admin" && req.Password == "password" {
        // ... authentication logic
        span.SetAttributes(attribute.Bool("auth.success", true))
        return response, nil
    }

    span.SetAttributes(attribute.Bool("auth.success", false))
    return nil, errors.New("invalid credentials")
}
```

### Core Layer (`core/`)

**Responsibilities:**
- Domain models (entities, value objects) in `core/domain/`
- Database connection in `core/database.go` (PostgreSQL via PgBouncer / PgDog)
- Cache client in `core/cache/` (Valkey, Redis-compatible)
- Domain interfaces and constants
- **No business logic** (pure data structures + thin infra adapters)

**APM Integration:**
- **Traces**: Not directly (used by logic layer; DB/cache spans bubble up via instrumentation)
- **Logs**: Not directly (used by logic layer)
- **Metrics**: DB pool / cache hit-rate metrics exposed on `/metrics`
- **Profiles**: Memory allocations visible in heap profiles

**Example:**
```go
// Domain model (pure data structure)
type User struct {
    ID       string `json:"id"`
    Username string `json:"username"`
    Email    string `json:"email"`
}

type LoginRequest struct {
    Username string `json:"username"`
    Password string `json:"password"`
}
```

## Trace-ID Propagation

Trace-IDs are propagated through all layers using context:

```mermaid
graph LR
    A[HTTP Request<br/>traceparent header] --> B[TracingMiddleware<br/>Extract/Generate trace-id]
    B --> C[LoggingMiddleware<br/>Add trace-id to logger]
    C --> D[Web Handler<br/>Get logger from context]
    D --> E[Logic Service<br/>Get logger from context]
    E --> F[All Logs<br/>Include trace-id]

    B --> G[OpenTelemetry Context<br/>Propagate via context.Context]
    G --> H[Web Span<br/>Parent: Root Span]
    H --> I[Logic Span<br/>Parent: Web Span]

    style B fill:#e1f5ff
    style C fill:#fff4e1
    style F fill:#fff4e1
    style G fill:#e1f5ff
    style H fill:#e1f5ff
    style I fill:#e1f5ff
```

## APM Data Correlation

All APM data is correlated via trace-id. Grafana is the single pane of glass for traces, logs, metrics, and profiles.

```mermaid
graph TD
    A[Trace-ID<br/>Generated by TracingMiddleware] --> B[Traces<br/>Tempo<br/>via OTel Collector]
    A --> C[Logs<br/>VictoriaLogs<br/>via Vector]
    A --> D[Metrics<br/>VictoriaMetrics<br/>exemplars / labels]
    A --> E[Profiles<br/>Pyroscope<br/>via tags]

    B --> F[Grafana<br/>Trace View]
    C --> G[Grafana<br/>Log View]
    D --> H[Grafana<br/>Metrics View]
    E --> I[Grafana<br/>Profile View]

    F --> J[Correlation<br/>Trace ↔ Logs<br/>Trace ↔ Metrics<br/>Trace ↔ Profiles]
    G --> J
    H --> J
    I --> J

    style A fill:#ffeb3b
    style J fill:#4caf50
```

## Benefits of 3-Layer Architecture with APM

1. **Clear Separation of Concerns**
   - Web layer: HTTP handling
   - Logic layer: Business rules + caching
   - Core layer: Domain models + DB/cache adapters

2. **Observability at Each Layer**
   - Traces show request flow through layers
   - Logs show what happens at each layer
   - Metrics show performance at each layer
   - Profiles show resource usage at each layer

3. **Easy Debugging**
   - Trace-id correlates all observability data
   - Can trace a request from HTTP to domain model
   - Can see which layer has performance issues

4. **Single API Version**
   - v1 is the canonical API (frontend-aligned)
   - Same domain models (core layer)
   - APM correlates traces, logs, and metrics per request

## Related Documentation

- [APM Overview](./README.md) — complete APM system overview
- [Tracing Guide](./tracing/README.md) — distributed tracing details (OTel Collector → Tempo + Jaeger)
- [Tracing Architecture](./tracing/architecture.md) — middleware chain ordering
- [Logging Guide](./logging/README.md) — Vector → VictoriaLogs pipeline
- [VictoriaLogs Reference](./logging/victorialogs.md)
- [Metrics Guide](./metrics/README.md) — VMAgent / VMSingle / VMAlert
- [VictoriaMetrics Reference](./metrics/victoriametrics.md)
- [Profiling Guide](./profiling/README.md) — Pyroscope (push-based)
- [MCP Servers](../platform/mcp-servers.md) — VM-MCP, VL-MCP, Flux-MCP for AI agents
