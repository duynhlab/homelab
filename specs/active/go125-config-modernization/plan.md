# Implementation Plan: Go 1.25 Upgrade & Config Modernization

**Task ID:** `go125-config-modernization`  
**Created:** December 12, 2025  
**Estimated:** 17 days (3 weeks)

**Related Docs:**
- [Research](./research.md) - Technical analysis
- [Specification](./spec.md) - Requirements

---

## Quick Overview

**4 Work Streams:**
1. **Go 1.25 Upgrade** (5 days) - Update Go version, refactor WaitGroup
2. **Config Package** (5 days) - Centralize config with validation
3. **Helm Docs** (2 days) - Document env vs extraEnv patterns
4. **Doc Cleanup** (5 days) - Merge 24 → 15 files

---

## 1. Architecture Decisions

### 1.1 Config Package Design

**Structure:**
```
services/pkg/config/
├── config.go          # Main config struct
├── config_test.go     # Unit tests
└── validation.go      # Validation logic (optional, can be in config.go)
```

**Pattern:** Simple struct + validation, NO external libraries

```go
// config.go
package config

type Config struct {
    Server    ServerConfig
    Tracing   TracingConfig
    Profiling ProfilingConfig
    Logging   LoggingConfig
}

type ServerConfig struct {
    Port string  `env:"PORT" default:"8080"`
    Env  string  `env:"ENV" default:"production"`
}

type TracingConfig struct {
    Enabled       bool    `env:"TRACING_ENABLED" default:"true"`
    TempoEndpoint string  `env:"TEMPO_ENDPOINT" default:"tempo.monitoring.svc.cluster.local:4318"`
    SampleRate    float64 `env:"OTEL_SAMPLE_RATE" default:"0.1"`
}

func Load() (*Config, error)      // Parse env vars + defaults
func (c *Config) Validate() error // Validate all fields
```

**Why:** Simple, testable, no dependencies, easy for SRE/DevOps

### 1.2 Middleware Refactoring Strategy

**Backward Compatibility:**
```go
// OLD (keep for 2 sprints)
func InitTracing() (*sdktrace.TracerProvider, error) {
    cfg := DefaultTracingConfig() // Uses os.Getenv internally
    return InitTracingWithConfig(cfg)
}

// NEW (primary)
func InitTracingWithConfigStruct(cfg TracingConfig) (*sdktrace.TracerProvider, error) {
    // Implementation...
}
```

**Migration:** Old → New over 2 sprints, then remove old

### 1.3 Testing Strategy

**What to Test:**
- Config validation rules (unit tests)
- Middleware with new config (integration)
- Build & deployment (staging)

**Test Coverage:**
```
services/pkg/config/config_test.go       # Config validation
services/pkg/middleware/*_test.go        # Middleware (if time permits)
Integration: Staging deployment         # Full system test
```

**Why:** Start with high-value tests (config validation), expand later

---

## 2. Implementation Guide

### Phase 1: Go 1.25 Upgrade (Week 1)

#### Day 1-2: Update Go Version

**Files to Modify:**
```bash
services/go.mod                    # go 1.25
services/Dockerfile                # FROM golang:1.25-alpine
.github/workflows/*.yml            # Update CI/CD (if exists)
```

**Commands:**
```bash
cd services
go mod edit -go=1.25
go get -u ./...
go mod tidy
go build ./...
go test ./...  # Expect: PASS (no tests yet, will add)
```

**Dockerfile Change:**
```dockerfile
# Before
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG SERVICE_NAME
RUN CGO_ENABLED=0 GOOS=linux go build -o ${SERVICE_NAME} ./cmd/${SERVICE_NAME}

# After - Go 1.25
FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG SERVICE_NAME

# Build flags explained:
# CGO_ENABLED=0: Create fully static binary (no C dependencies) - perfect for minimal containers
# -ldflags="-s -w": Strip debug info to reduce binary size (OPTIONAL - only if size is critical)
#   -s: Omit symbol table (removes function/variable names)
#   -w: Omit DWARF debug info (removes line numbers in panics)
# Trade-off: Smaller images (30-40%) vs harder debugging (no stack traces)

# Option 1: Keep debug info (RECOMMENDED for most cases)
RUN CGO_ENABLED=0 GOOS=linux go build -o ${SERVICE_NAME} ./cmd/${SERVICE_NAME}

# Option 2: Strip for production (only if image size is critical)
# RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o ${SERVICE_NAME} ./cmd/${SERVICE_NAME}
```

**Green Tea GC Decision:**
- ❌ **NOT NEEDED** in Dockerfile by default
- ✅ Test manually in staging ONLY if GC is causing issues
- Command: `GOEXPERIMENT=greenteagc go build ...`
- Monitor: Grafana GC duration metrics for 48 hours
- Decision: If >15% improvement AND no crashes → consider production

#### Day 3: Refactor WaitGroup Usage

**Pattern in ALL 9 services** (`cmd/*/main.go`):

```go
// BEFORE (current - 9 services)
var wg sync.WaitGroup
wg.Add(3)
go func() {
    defer wg.Done()
    tp.Shutdown(shutdownCtx)
}()
go func() {
    defer wg.Done()
    middleware.StopProfiling()
}()
go func() {
    defer wg.Done()
    logger.Sync()
}()
wg.Wait()

// AFTER (Go 1.25 - simpler!)
var wg sync.WaitGroup
wg.Go(func() { tp.Shutdown(shutdownCtx) })
wg.Go(func() { middleware.StopProfiling() })
wg.Go(func() { logger.Sync() })
wg.Wait()
```

**Services to Update:**
- `cmd/auth/main.go`
- `cmd/user/main.go`
- `cmd/product/main.go`
- `cmd/cart/main.go`
- `cmd/order/main.go`
- `cmd/review/main.go`
- `cmd/notification/main.go`
- `cmd/shipping/main.go`
- `cmd/shipping-v2/main.go`

**Add Comments:**
```go
// Graceful shutdown sequence using Go 1.25 WaitGroup.Go()
// 1. Flush APM data (traces, logs, profiles)
// 2. Shutdown HTTP server (handled separately)
var wg sync.WaitGroup
wg.Go(func() { tp.Shutdown(shutdownCtx) })  // Flush traces to Tempo
wg.Go(func() { middleware.StopProfiling() }) // Stop Pyroscope profiling
wg.Go(func() { logger.Sync() })               // Flush logs
wg.Wait()
```

#### Day 4-5: Staging Deployment & Monitoring

**Build & Deploy:**
```bash
# Build staging images
./scripts/04-build-microservices.sh

# Deploy to staging
./scripts/05-deploy-microservices.sh --local

# Monitor for 48 hours
kubectl get pods -n auth,user,product,cart,order,review,notification,shipping
kubectl logs -n auth -l app=auth --tail=100 | grep -i error
```

**Metrics to Monitor:**
- Grafana → GC duration panel (expect 10-40% reduction)
- Prometheus → `go_gc_duration_seconds`
- Error rate unchanged

---

### Phase 2: Configuration Package (Week 2)

#### Day 1: Create Config Package

**File: `services/pkg/config/config.go`**

```go
package config

import (
    "fmt"
    "os"
    "strconv"
)

// Config holds all application configuration
type Config struct {
    Server    ServerConfig
    Tracing   TracingConfig
    Profiling ProfilingConfig
    Logging   LoggingConfig
}

type ServerConfig struct {
    Port string
    Env  string
}

type TracingConfig struct {
    Enabled       bool
    TempoEndpoint string
    SampleRate    float64
}

type ProfilingConfig struct {
    Enabled           bool
    PyroscopeEndpoint string
}

type LoggingConfig struct {
    Level  string
    Format string
}

// Load reads configuration from environment variables
func Load() (*Config, error) {
    cfg := &Config{
        Server: ServerConfig{
            Port: getEnv("PORT", "8080"),
            Env:  getEnv("ENV", "production"),
        },
        Tracing: TracingConfig{
            Enabled:       getEnvBool("TRACING_ENABLED", true),
            TempoEndpoint: getEnv("TEMPO_ENDPOINT", "tempo.monitoring.svc.cluster.local:4318"),
            SampleRate:    getEnvFloat("OTEL_SAMPLE_RATE", 0.1),
        },
        Profiling: ProfilingConfig{
            Enabled:           getEnvBool("PROFILING_ENABLED", true),
            PyroscopeEndpoint: getEnv("PYROSCOPE_ENDPOINT", "http://pyroscope.monitoring.svc.cluster.local:4040"),
        },
        Logging: LoggingConfig{
            Level:  getEnv("LOG_LEVEL", "info"),
            Format: getEnv("LOG_FORMAT", "json"),
        },
    }
    
    // Auto-adjust sample rate for development
    if cfg.Server.Env == "development" || cfg.Server.Env == "dev" {
        cfg.Tracing.SampleRate = 1.0
    }
    
    if err := cfg.Validate(); err != nil {
        return nil, err
    }
    
    return cfg, nil
}

// Validate checks configuration
func (c *Config) Validate() error {
    // Sample rate
    if c.Tracing.SampleRate < 0 || c.Tracing.SampleRate > 1 {
        return fmt.Errorf("invalid sample rate: %f (must be 0-1)", c.Tracing.SampleRate)
    }
    
    // Port
    port, err := strconv.Atoi(c.Server.Port)
    if err != nil || port < 1 || port > 65535 {
        return fmt.Errorf("invalid port: %s (must be 1-65535)", c.Server.Port)
    }
    
    // Endpoints
    if c.Tracing.Enabled && c.Tracing.TempoEndpoint == "" {
        return fmt.Errorf("tracing enabled but tempo endpoint empty")
    }
    
    return nil
}

// Helper functions
func getEnv(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}

func getEnvBool(key string, defaultValue bool) bool {
    if value := os.Getenv(key); value != "" {
        if parsed, err := strconv.ParseBool(value); err == nil {
            return parsed
        }
    }
    return defaultValue
}

func getEnvFloat(key string, defaultValue float64) float64 {
    if value := os.Getenv(key); value != "" {
        if parsed, err := strconv.ParseFloat(value, 64); err == nil {
            return parsed
        }
    }
    return defaultValue
}
```

**File: `services/pkg/config/config_test.go`**

```go
package config

import (
    "os"
    "testing"
)

func TestValidate(t *testing.T) {
    tests := []struct {
        name    string
        config  *Config
        wantErr bool
    }{
        {
            name: "valid config",
            config: &Config{
                Server:  ServerConfig{Port: "8080", Env: "production"},
                Tracing: TracingConfig{Enabled: true, SampleRate: 0.1, TempoEndpoint: "localhost:4318"},
            },
            wantErr: false,
        },
        {
            name: "invalid sample rate",
            config: &Config{
                Server:  ServerConfig{Port: "8080", Env: "production"},
                Tracing: TracingConfig{Enabled: true, SampleRate: 1.5, TempoEndpoint: "localhost:4318"},
            },
            wantErr: true,
        },
        {
            name: "invalid port",
            config: &Config{
                Server:  ServerConfig{Port: "99999", Env: "production"},
                Tracing: TracingConfig{Enabled: true, SampleRate: 0.1, TempoEndpoint: "localhost:4318"},
            },
            wantErr: true,
        },
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            err := tt.config.Validate()
            if (err != nil) != tt.wantErr {
                t.Errorf("Validate() error = %v, wantErr %v", err, tt.wantErr)
            }
        })
    }
}

func TestLoad(t *testing.T) {
    // Test with valid env vars
    os.Setenv("PORT", "8080")
    os.Setenv("OTEL_SAMPLE_RATE", "0.5")
    defer os.Unsetenv("PORT")
    defer os.Unsetenv("OTEL_SAMPLE_RATE")
    
    cfg, err := Load()
    if err != nil {
        t.Fatalf("Load() error = %v", err)
    }
    
    if cfg.Server.Port != "8080" {
        t.Errorf("Port = %s, want 8080", cfg.Server.Port)
    }
    
    if cfg.Tracing.SampleRate != 0.5 {
        t.Errorf("SampleRate = %f, want 0.5", cfg.Tracing.SampleRate)
    }
}
```

#### Day 2: Refactor Middleware

**Update `services/pkg/middleware/tracing.go`:**

```go
// Add new function (keep old for compatibility)
func InitTracingWithConfigStruct(cfg config.TracingConfig) (*sdktrace.TracerProvider, error) {
    // Use cfg.TempoEndpoint, cfg.SampleRate directly
    // ... implementation similar to current InitTracing()
}

// OLD - keep for 2 sprints
func InitTracing() (*sdktrace.TracerProvider, error) {
    cfg := DefaultTracingConfig() // Uses os.Getenv
    log.Println("DEPRECATED: Use InitTracingWithConfigStruct instead")
    return InitTracingWithConfigStruct(cfg)
}
```

**Repeat for:**
- `middleware/profiling.go` → `InitProfilingWithConfig(cfg config.ProfilingConfig)`
- `middleware/logging.go` → `NewLoggerWithConfig(cfg config.LoggingConfig)`

#### Day 3: Add godotenv

**Update `services/go.mod`:**
```bash
go get github.com/joho/godotenv@latest
```

**Update ALL 9 `cmd/*/main.go`:**
```go
package main

import (
    _ "github.com/joho/godotenv/autoload"  // Auto-load .env if exists
    // ... rest of imports
)
```

**Create `.env.example`:**
```bash
# Server
ENV=development
PORT=8080

# Tracing
TRACING_ENABLED=true
TEMPO_ENDPOINT=localhost:4318
OTEL_SAMPLE_RATE=1.0

# Profiling
PROFILING_ENABLED=true
PYROSCOPE_ENDPOINT=http://localhost:4040

# Logging
LOG_LEVEL=debug
LOG_FORMAT=console
```

**Update `.gitignore`:**
```
.env
```

#### Day 4-5: Update All Services

**Template for ALL 9 services** (`cmd/*/main.go`):

```go
package main

import (
    _ "github.com/joho/godotenv/autoload"  // NEW: Load .env
    
    "context"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"

    "github.com/gin-gonic/gin"
    "github.com/prometheus/client_golang/prometheus/promhttp"
    "go.uber.org/zap"

    "github.com/duynhne/monitoring/pkg/config"  // NEW: Config package
    "github.com/duynhne/monitoring/pkg/middleware"
    v1 "github.com/duynhne/monitoring/internal/auth/web/v1"
    v2 "github.com/duynhne/monitoring/internal/auth/web/v2"
)

func main() {
    // NEW: Load and validate configuration
    cfg, err := config.Load()
    if err != nil {
        panic(fmt.Sprintf("Failed to load config: %v", err))
    }
    
    // Initialize logger with config
    logger, err := middleware.NewLoggerWithConfig(cfg.Logging)
    if err != nil {
        panic("Failed to initialize logger: " + err.Error())
    }
    defer logger.Sync()
    
    // Initialize tracing with config
    if cfg.Tracing.Enabled {
        tp, err := middleware.InitTracingWithConfigStruct(cfg.Tracing)
        if err != nil {
            logger.Warn("Failed to initialize tracing", zap.Error(err))
        } else {
            defer tp.Shutdown(context.Background())
        }
    }
    
    // Initialize profiling with config
    if cfg.Profiling.Enabled {
        if err := middleware.InitProfilingWithConfig(cfg.Profiling); err != nil {
            logger.Warn("Failed to initialize profiling", zap.Error(err))
        } else {
            defer middleware.StopProfiling()
        }
    }
    
    // Rest stays the same...
    r := gin.Default()
    r.Use(middleware.TracingMiddleware())
    r.Use(middleware.LoggingMiddleware(logger))
    r.Use(middleware.PrometheusMiddleware())
    
    // ... routes, server, graceful shutdown
}
```

**Apply to all 9 services:**
- auth, user, product, cart, order, review, notification, shipping, shipping-v2

---

### Phase 3: Helm Documentation (Week 2 - Parallel)

**File: `charts/README.md`** (create new)

```markdown
# Microservice Helm Chart

Generic chart for deploying microservices.

## Environment Variables

### Base Configuration (`env`)
Common variables for ALL services (set in `values.yaml`):

```yaml
env:
  - name: ENV
    value: "production"
  - name: LOG_LEVEL
    value: "info"
```

### Structured Configuration
Feature-specific config with typed fields:

```yaml
tracing:
  enabled: true
  endpoint: "tempo.monitoring.svc.cluster.local:4318"
  sampleRate: "0.1"
```

### Service-Specific (`extraEnv`)
Override defaults per service (set in `values/<service>.yaml`):

```yaml
extraEnv:
  - name: OTEL_SAMPLE_RATE
    value: "0.05"  # Override for high-traffic service
  - name: API_KEY
    valueFrom:
      secretKeyRef:
        name: my-secret
        key: api-key
```

### Execution Order
1. `env` (base)
2. Structured config (tracing, profiling)
3. `extraEnv` (can override anything)

## Usage

```bash
helm upgrade --install auth charts/ -f charts/values/auth.yaml -n auth
```
```

**Update `AGENTS.md`** - Add link to charts/README.md

---

### Phase 4: Documentation Cleanup (Week 3)

**Merge Actions:**

| Source | Target | Action |
|--------|--------|--------|
| `monitoring/VARIABLES_REGEX.md` | `monitoring/METRICS.md` | Merge as section "Dashboard Variables" |
| `monitoring/METRICS_LABEL_SOLUTIONS.md` | `monitoring/METRICS.md` | Merge as section "Label Configuration" |
| `monitoring/TROUBLESHOOTING.md` | `getting-started/SETUP.md` | Merge as section "Troubleshooting" |
| `apm/ARCHITECTURE.md` | `apm/README.md` | Merge as section "Architecture" |
| `apm/PROFILING.md` | `apm/README.md` | Merge as section "Continuous Profiling" |
| `slo/ERROR_BUDGET_POLICY.md` | `slo/ALERTING.md` | Merge as section "Error Budget Management" |

**Commands:**
```bash
# Merge content, then delete source files
cat monitoring/VARIABLES_REGEX.md >> monitoring/METRICS.md
rm monitoring/VARIABLES_REGEX.md

# Update docs/README.md
# Change: 24 files → 15 files
```

---

## 3. Testing & Validation

### Unit Tests
```bash
cd services
go test ./pkg/config/...        # Config validation tests
go test ./pkg/middleware/...    # Middleware tests (if added)
```

### Integration Tests (Staging)
```bash
# Deploy to staging
./scripts/05-deploy-microservices.sh --local

# Test invalid config (should fail at startup)
kubectl set env deployment/auth -n auth OTEL_SAMPLE_RATE=invalid
kubectl logs -n auth -l app=auth | grep "invalid sample rate"

# Rollback
kubectl rollout undo deployment/auth -n auth
```

### Performance Validation
```bash
# Monitor GC metrics
kubectl port-forward -n monitoring svc/grafana-service 3000:3000
# Open Grafana → GC duration panel
# Expect: 10-40% reduction with Green Tea GC
```

---

## 4. Rollback Plan

**If issues occur:**

### Go 1.25 Rollback
```bash
# Revert Docker images
kubectl set image deployment/auth -n auth auth=ghcr.io/duynhne/auth:v5
kubectl set image deployment/user -n user user=ghcr.io/duynhne/user:v5
# ... repeat for all services
```

### Config Rollback
```bash
# OLD functions still work (backward compatible)
# Services automatically use old pattern if new fails
```

---

## 5. Success Criteria

**Phase 1 (Go 1.25):**
- ✅ All services build with Go 1.25
- ✅ Tests pass (once added)
- ✅ GC overhead reduced 10-40%

**Phase 2 (Config):**
- ✅ Config validation catches typos at startup
- ✅ All 9 services use new config package
- ✅ `.env` works locally

**Phase 3 (Helm Docs):**
- ✅ `charts/README.md` exists
- ✅ Zero questions from team

**Phase 4 (Docs):**
- ✅ 24 → 15 files
- ✅ Zero broken links

---

## 6. Timeline

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| **Phase 1** | Week 1 (5 days) | Go 1.25 deployed to staging |
| **Phase 2** | Week 2 (5 days) | Config package integrated |
| **Phase 3** | Week 2 (2 days) | Helm docs published |
| **Phase 4** | Week 3 (5 days) | Docs consolidated |
| **Total** | 17 days | All 4 phases complete |

---

**Next Steps:**
1. Review this plan
2. Get approval
3. Run `/tasks go125-config-modernization` to create todo-list.md
4. Begin Phase 1

**Document Version:** 1.0  
**Status:** Ready for Review
