# Context-Aware Logging Research

> **Status**: 🔬 Research  
> **Created**: 2026-01-28  
> **Author**: Research findings for evaluating logging solutions

---

## 1. Bối cảnh nghiên cứu

### 1.1 Vấn đề hiện tại

Dự án microservices hiện đang sử dụng **Zap** (`go.uber.org/zap` v1.27.1) với Go 1.25. Context-aware logging được implement thủ công qua Gin context:

```go
// middleware/logging.go - Current implementation
loggerWithTrace := logger.With(zap.String("trace_id", traceID))
c.Set("logger", loggerWithTrace)  // Store in Gin context only

func GetLoggerFromGinContext(c *gin.Context) *zap.Logger {
    loggerVal, exists := c.Get("logger")
    // ... type assertion
}
```

**Hạn chế:**
- ❌ Chỉ hoạt động với `*gin.Context`, không portable
- ❌ Không sử dụng được với `context.Context` chuẩn
- ❌ Không thể truyền logger xuống các layer không phụ thuộc Gin (repository, service)
- ❌ Phải truyền logger riêng qua function parameters

---

## 2. Các giải pháp được nghiên cứu

### 2.1 chainguard-dev/clog

**Repository**: https://github.com/chainguard-dev/clog

#### Tổng quan
- Context-aware wrapper cho `log/slog` (Go 1.21+)
- **Zero dependencies** - chỉ sử dụng stdlib
- Lấy cảm hứng từ `knative.dev/pkg/logging` nhưng nhẹ hơn nhiều

#### Core APIs

```go
// Gắn logger vào context
ctx := clog.WithLogger(context.Background(), logger)

// Lấy logger từ context
log := clog.FromContext(ctx)
log.Info("message", "key", "value")

// Hoặc dùng package-level functions
clog.InfoContext(ctx, "message")
clog.ErrorContextf(ctx, "error: %v", err)
```

#### Tính năng

| Feature | Có/Không |
|---------|----------|
| Context propagation | ✅ |
| Zero dependencies | ✅ |
| slog compatible | ✅ |
| Testing support (`slogtest`) | ✅ |
| GCP Cloud Logging handler | ✅ |
| Sampling | ❌ |
| Binary encoding | ❌ |

#### Benchmark (ước tính)
- Performance dựa trên slog (~4x chậm hơn Zap/Zerolog trong high-throughput)
- Memory allocations: thấp nhưng không zero-alloc

---

### 2.2 rs/zerolog

**Repository**: https://github.com/rs/zerolog

#### Tổng quan
- **Zero allocation** JSON logger
- Performance tốt nhất trong các logging libraries
- Native context.Context support

#### Core APIs

```go
// Gắn logger vào context
ctx := logger.WithContext(context.Background())

// Lấy logger từ context
log := zerolog.Ctx(ctx)
log.Info().Str("key", "value").Msg("message")
```

#### Tính năng

| Feature | Có/Không |
|---------|----------|
| Context propagation | ✅ |
| Zero allocation | ✅ |
| Sampling | ✅ |
| Hooks | ✅ |
| Binary encoding (CBOR) | ✅ |
| HTTP integration (`hlog`) | ✅ |
| Pretty console logging | ✅ |

#### Benchmark
```
BenchmarkInfo-8            30000000    42.5 ns/op    0 B/op   0 allocs/op
BenchmarkLogFields-8       10000000    184 ns/op     0 B/op   0 allocs/op
```

---

### 2.3 log/slog (Standard Library)

**Package**: `log/slog` (Go 1.21+)

#### Tổng quan
- Standard library từ Go 1.21
- Structured, leveled logging
- Handler interface cho extensibility

#### Core APIs

```go
// Với context
slog.InfoContext(ctx, "message", "key", "value")

// Handler có thể extract từ context
type contextHandler struct {
    handler slog.Handler
}

func (h *contextHandler) Handle(ctx context.Context, r slog.Record) error {
    if traceID := ctx.Value(traceIDKey); traceID != nil {
        r.AddAttrs(slog.String("trace_id", traceID.(string)))
    }
    return h.handler.Handle(ctx, r)
}
```

#### Tính năng

| Feature | Có/Không |
|---------|----------|
| Context support | ✅ (manual) |
| Zero dependencies | ✅ |
| Handler interface | ✅ |
| Pluggable backends (Zap, Zerolog) | ✅ |
| Built-in context propagation | ❌ |

---

### 2.4 uber-go/zap (Hiện tại)

**Repository**: https://github.com/uber-go/zap

#### Tổng quan
- High-performance structured logging
- Type-safe field construction
- Đang được sử dụng trong dự án

#### Context Support (Manual)

```go
// Cần tự implement context propagation
type ctxKey struct{}

func WithLogger(ctx context.Context, logger *zap.Logger) context.Context {
    return context.WithValue(ctx, ctxKey{}, logger)
}

func FromContext(ctx context.Context) *zap.Logger {
    if logger, ok := ctx.Value(ctxKey{}).(*zap.Logger); ok {
        return logger
    }
    return zap.L() // global logger
}
```

---

## 3. Bảng so sánh tổng hợp

```
┌─────────────────────┬──────────┬─────────┬───────────┬──────────┐
│      Tiêu chí       │   Zap    │  clog   │  zerolog  │   slog   │
├─────────────────────┼──────────┼─────────┼───────────┼──────────┤
│ Performance         │ ⭐⭐⭐⭐⭐  │ ⭐⭐⭐⭐   │ ⭐⭐⭐⭐⭐   │ ⭐⭐⭐⭐   │
│ Memory allocations  │ 0-2      │ Low     │ 0         │ Low      │
│ Dependencies        │ ~10 pkgs │ 0       │ ~3 pkgs   │ 0        │
│ Context-aware       │ Manual   │ Native  │ Native    │ Manual   │
│ Go version          │ 1.15+    │ 1.21+   │ 1.15+     │ 1.21+    │
│ Learning curve      │ Medium   │ Low     │ Medium    │ Low      │
│ Community           │ Huge     │ Small   │ Large     │ Official │
│ API Style           │ Type-safe│ Printf  │ Chainable │ Printf   │
│ Cloud integrations  │ Plugins  │ GCP     │ Plugins   │ Plugins  │
└─────────────────────┴──────────┴─────────┴───────────┴──────────┘
```

---

## 4. Use Cases Analysis

### 4.1 Request Scoping (HTTP Server)

**Yêu cầu**: Gắn `trace_id`, `request_id` vào mọi log trong request lifecycle

| Library | Đánh giá |
|---------|----------|
| **clog** | ⭐⭐⭐⭐⭐ Native support, clean API |
| **zerolog** | ⭐⭐⭐⭐⭐ Native support + `hlog` package |
| **Zap** | ⭐⭐⭐ Cần wrapper, đang làm thủ công |
| **slog** | ⭐⭐⭐⭐ Cần custom handler |

### 4.2 Cross-layer Logging (Handler → Service → Repository)

**Yêu cầu**: Logger propagate qua mọi layer mà không truyền tham số

| Library | Đánh giá |
|---------|----------|
| **clog** | ⭐⭐⭐⭐⭐ `clog.FromContext(ctx)` ở mọi layer |
| **zerolog** | ⭐⭐⭐⭐⭐ `zerolog.Ctx(ctx)` ở mọi layer |
| **Zap** | ⭐⭐ Cần tự implement |
| **slog** | ⭐⭐⭐ Cần tự implement |

### 4.3 Testing

**Yêu cầu**: Log output hiển thị trong test failures

| Library | Đánh giá |
|---------|----------|
| **clog** | ⭐⭐⭐⭐⭐ `slogtest.TestContextWithLogger(t)` |
| **zerolog** | ⭐⭐⭐⭐ `zerolog.New(zerolog.TestWriter{T: t})` |
| **Zap** | ⭐⭐⭐⭐ `zaptest.NewLogger(t)` |
| **slog** | ⭐⭐⭐ Cần custom handler |

---

## 5. Migration Effort Estimate

### 5.1 Zap → clog

| Task | Effort | Files Affected |
|------|--------|----------------|
| Update go.mod | Low | 8 services |
| Refactor middleware | Medium | 8 files |
| Update handlers | Medium-High | ~30 files |
| Update services/repositories | Medium | ~20 files |
| Testing | Medium | ~15 files |
| **Total** | **2-3 days** | ~80 files |

### 5.2 Zap → zerolog

| Task | Effort | Files Affected |
|------|--------|----------------|
| Update go.mod | Low | 8 services |
| Learn chainable API | Medium | N/A |
| Refactor all logging calls | High | ~80 files |
| Update middleware | High | 8 files |
| Testing | Medium-High | ~15 files |
| **Total** | **4-5 days** | ~100 files |

---

## 6. Recommendations

### 6.1 Short-term (Quick Win)

Thêm context propagation wrapper cho Zap hiện tại:

```go
// pkg/logger/context.go
package logger

import (
    "context"
    "go.uber.org/zap"
)

type ctxKey struct{}

func WithLogger(ctx context.Context, l *zap.Logger) context.Context {
    return context.WithValue(ctx, ctxKey{}, l)
}

func FromContext(ctx context.Context) *zap.Logger {
    if l, ok := ctx.Value(ctxKey{}).(*zap.Logger); ok {
        return l
    }
    return zap.L()
}
```

**Effort**: 1 day  
**Benefit**: Context propagation mà không thay đổi logging library

---

### 6.2 Long-term (Recommended)

**Migrate sang clog** vì:

1. ✅ **Zero dependencies** - giảm attack surface, nhẹ binary
2. ✅ **Clean API** - `clog.FromContext(ctx)` gọn gàng
3. ✅ **Future-proof** - dựa trên slog chuẩn Go
4. ✅ **Testing support** - slogtest package
5. ✅ **GCP ready** - có handler cho Cloud Logging

**Migration path**:
```
Phase 1: Add clog alongside Zap (parallel logging)
Phase 2: Migrate high-traffic services first
Phase 3: Complete migration, remove Zap
```

---

## 7. References

- [chainguard-dev/clog](https://github.com/chainguard-dev/clog)
- [rs/zerolog](https://github.com/rs/zerolog)
- [uber-go/zap](https://github.com/uber-go/zap)
- [log/slog documentation](https://pkg.go.dev/log/slog)
- [Go 1.21 slog announcement](https://go.dev/blog/slog)
- [Structured Logging with slog](https://go.dev/blog/slog)
- [Zerolog Benchmarks](http://bench.zerolog.io/)

---

## 8. Next Steps

- [ ] POC: Implement clog trong 1 service (product)
- [ ] Benchmark: So sánh performance clog vs Zap trong dự án
- [ ] Document: Tạo migration guide cho team
- [ ] Review: Trình bày findings cho team lead
