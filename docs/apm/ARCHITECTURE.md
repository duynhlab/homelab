# 3-Layer Architecture & APM Integration

## Overview

This document visualizes the 3-layer architecture (web → logic → core) and how APM (Application Performance Monitoring) integrates with each layer to provide comprehensive observability.

## 3-Layer Architecture

### Code Structure

The codebase follows a clean 3-layer architecture pattern:

```
┌─────────────────────────────────────────┐
│         HTTP Request (Gin)              │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│      Middleware Chain (pkg/middleware)  │
│  ┌──────────────────────────────────┐   │
│  │ 1. TracingMiddleware()           │   │
│  │    - Creates root span           │   │
│  │    - Propagates trace context    │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ 2. LoggingMiddleware()           │   │
│  │    - Extracts trace-id           │   │
│  │    - Creates logger with trace-id│   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ 3. PrometheusMiddleware()        │   │
│  │    - Collects HTTP metrics       │   │
│  └──────────────────────────────────┘   │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│   Layer 1: Web (HTTP Handlers)          │
│   internal/{service}/web/v1/            │
│   internal/{service}/web/v2/            │
│  ┌──────────────────────────────────┐   │
│  │ - Parse HTTP request             │   │
│  │ - Validate input                 │   │
│  │ - Create web layer span          │   │
│  │ - Call logic layer               │   │
│  │ - Format HTTP response           │   │
│  └──────────────────────────────────┘   │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│   Layer 2: Logic (Business Logic)       │
│   internal/{service}/logic/v1/          │
│   internal/{service}/logic/v2/          │
│  ┌──────────────────────────────────┐   │
│  │ - Business rules                 │   │
│  │ - Data validation                │   │
│  │ - Create logic layer span        │   │
│  │ - Use domain models              │   │
│  │ - Return business result         │   │
│  └──────────────────────────────────┘   │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│   Layer 3: Core (Domain Models)         │
│   internal/{service}/core/domain/       │
│  ┌──────────────────────────────────┐   │
│  │ - Domain entities                │   │
│  │ - Value objects                  │   │
│  │ - Domain interfaces              │   │
│  │ - No business logic              │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### Mermaid Diagram: 3-Layer Architecture Flow

```mermaid
graph TD
    A[HTTP Request] --> B[Gin Router]
    B --> C[Middleware Chain]
    
    C --> D[TracingMiddleware<br/>Creates root span]
    D --> E[LoggingMiddleware<br/>Extracts trace-id]
    E --> F[PrometheusMiddleware<br/>Collects metrics]
    
    F --> G{API Version?}
    G -->|v1| H[Web Layer v1<br/>web/v1/handler.go]
    G -->|v2| I[Web Layer v2<br/>web/v2/handler.go]
    
    H --> J[Parse Request<br/>Validate Input<br/>Create Web Span]
    I --> J
    
    J --> K{Version?}
    K -->|v1| L[Logic Layer v1<br/>logic/v1/service.go]
    K -->|v2| M[Logic Layer v2<br/>logic/v2/service.go]
    
    L --> N[Business Logic<br/>Create Logic Span<br/>Use Domain Models]
    M --> N
    
    N --> O[Core Layer<br/>core/domain/<br/>Domain Models]
    
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

1. **Traces** - Distributed tracing with spans at each layer
2. **Logs** - Structured JSON logs with trace-id correlation
3. **Metrics** - HTTP and business metrics
4. **Profiles** - Continuous CPU, heap, goroutine profiling

### Mermaid Diagram: APM Data Flow

```mermaid
graph LR
    subgraph "HTTP Request Flow"
        A[HTTP Request] --> B[Middleware]
        B --> C[Web Layer]
        C --> D[Logic Layer]
        D --> E[Core Layer]
        E --> F[Response]
    end
    
    subgraph "Tracing (OpenTelemetry)"
        B --> T1[Root Span<br/>HTTP Request]
        C --> T2[Web Span<br/>layer=web]
        D --> T3[Logic Span<br/>layer=logic]
        T1 --> T2
        T2 --> T3
        T3 --> TEMPO[Tempo<br/>OTLP HTTP]
    end
    
    subgraph "Logging (Zap)"
        B --> L1[Request Log<br/>trace-id extracted]
        C --> L2[Handler Log<br/>trace-id included]
        D --> L3[Business Log<br/>trace-id included]
        L1 --> VECTOR[Vector<br/>Log Collector]
        L2 --> VECTOR
        L3 --> VECTOR
        VECTOR --> LOKI[Loki<br/>Log Storage]
    end
    
    subgraph "Metrics (Prometheus)"
        B --> M1[HTTP Metrics<br/>request_duration_seconds<br/>requests_total<br/>requests_in_flight]
        M1 --> PROM[Prometheus<br/>Scrape /metrics]
    end
    
    subgraph "Profiling (Pyroscope)"
        B --> P1[CPU Profile]
        C --> P2[Heap Profile]
        D --> P3[Goroutine Profile]
        P1 --> PYRO[Pyroscope<br/>Continuous Profiling]
        P2 --> PYRO
        P3 --> PYRO
    end
    
    style T1 fill:#e1f5ff
    style T2 fill:#e1f5ff
    style T3 fill:#e1f5ff
    style TEMPO fill:#b3e5fc
    style L1 fill:#fff4e1
    style L2 fill:#fff4e1
    style L3 fill:#fff4e1
    style LOKI fill:#ffe0b2
    style M1 fill:#ffe1f5
    style PROM fill:#f8bbd0
    style P1 fill:#e1ffe1
    style P2 fill:#e1ffe1
    style P3 fill:#e1ffe1
    style PYRO fill:#c8e6c9
```

## Complete System Flow

### End-to-End Request with APM

This diagram shows the complete flow from HTTP request to APM data collection:

```mermaid
sequenceDiagram
    participant Client
    participant Gin as Gin Router
    participant MW as Middleware Chain
    participant Web as Web Layer
    participant Logic as Logic Layer
    participant Core as Core Layer
    participant Tempo as Tempo
    participant Loki as Loki
    participant Prom as Prometheus
    participant Pyro as Pyroscope
    
    Client->>Gin: HTTP Request
    Gin->>MW: Route to handler
    
    Note over MW: TracingMiddleware
    MW->>MW: Create root span
    MW->>Tempo: Send span (async)
    
    Note over MW: LoggingMiddleware
    MW->>MW: Extract trace-id
    MW->>MW: Create logger with trace-id
    MW->>Loki: Log request (via Vector)
    
    Note over MW: PrometheusMiddleware
    MW->>MW: Record metrics
    
    MW->>Web: Call handler
    
    Note over Web: web/v1/handler.go
    Web->>Web: Parse & validate request
    Web->>Web: Create web layer span
    Web->>Tempo: Send span (async)
    Web->>Loki: Log handler entry (trace-id)
    Web->>Logic: Call business logic
    
    Note over Logic: logic/v1/service.go
    Logic->>Logic: Execute business rules
    Logic->>Logic: Create logic layer span
    Logic->>Tempo: Send span (async)
    Logic->>Loki: Log business logic (trace-id)
    Logic->>Core: Use domain models
    
    Note over Core: core/domain/
    Core-->>Logic: Return domain objects
    
    Logic-->>Web: Return business result
    Web->>Loki: Log handler exit (trace-id)
    Web-->>MW: Return response
    
    MW->>Prom: Expose /metrics endpoint
    MW->>Loki: Log response (trace-id)
    MW->>Tempo: Complete root span (async)
    MW-->>Gin: Response ready
    Gin-->>Client: HTTP Response
    
    Note over Pyro: Continuous Profiling
    Pyro->>Pyro: Collect CPU samples
    Pyro->>Pyro: Collect heap samples
    Pyro->>Pyro: Collect goroutine samples
```

## Layer Responsibilities

### Web Layer (`web/v1/`, `web/v2/`)

**Responsibilities:**
- HTTP request/response handling
- Input validation and parsing
- HTTP status code mapping
- Error formatting
- Create web layer spans for tracing
- Log HTTP-level events with trace-id

**APM Integration:**
- **Traces**: Creates spans with `layer=web` attribute
- **Logs**: Logs request/response with trace-id
- **Metrics**: HTTP metrics collected by middleware (not in web layer)

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

### Logic Layer (`logic/v1/`, `logic/v2/`)

**Responsibilities:**
- Business logic implementation
- Data validation and transformation
- Business rule enforcement
- Create logic layer spans for tracing
- Log business-level events with trace-id

**APM Integration:**
- **Traces**: Creates spans with `layer=logic` attribute
- **Logs**: Logs business logic execution with trace-id
- **Metrics**: Can create custom business metrics
- **Profiles**: Business logic appears in CPU/heap profiles

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

### Core Layer (`core/domain/`)

**Responsibilities:**
- Domain models (entities, value objects)
- Domain interfaces
- Domain constants
- **No business logic** (pure data structures)

**APM Integration:**
- **Traces**: Not directly (used by logic layer)
- **Logs**: Not directly (used by logic layer)
- **Metrics**: Not directly
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

All APM data is correlated via trace-id:

```mermaid
graph TD
    A[Trace-ID<br/>Generated by TracingMiddleware] --> B[Traces<br/>Tempo]
    A --> C[Logs<br/>Loki]
    A --> D[Metrics<br/>Prometheus<br/>via labels]
    A --> E[Profiles<br/>Pyroscope<br/>via tags]
    
    B --> F[Grafana<br/>Trace View]
    C --> G[Grafana<br/>Log View]
    D --> H[Grafana<br/>Metrics View]
    E --> I[Grafana<br/>Profile View]
    
    F --> J[Correlation<br/>Trace-to-Logs<br/>Trace-to-Metrics<br/>Trace-to-Profiles]
    G --> J
    H --> J
    I --> J
    
    style A fill:#ffeb3b
    style J fill:#4caf50
```

## Benefits of 3-Layer Architecture with APM

1. **Clear Separation of Concerns**
   - Web layer: HTTP handling
   - Logic layer: Business rules
   - Core layer: Domain models

2. **Observability at Each Layer**
   - Traces show request flow through layers
   - Logs show what happens at each layer
   - Metrics show performance at each layer
   - Profiles show resource usage at each layer

3. **Easy Debugging**
   - Trace-id correlates all observability data
   - Can trace a request from HTTP to domain model
   - Can see which layer has performance issues

4. **Version Independence**
   - v1 and v2 can have different logic
   - Same domain models (core layer)
   - APM shows differences between versions

## Related Documentation

- [APM Overview](./README.md) - Complete APM system overview
- [Tracing Guide](./TRACING.md) - Distributed tracing details
- [Logging Guide](./LOGGING.md) - Structured logging guide
- [Profiling Guide](./PROFILING.md) - Continuous profiling guide

