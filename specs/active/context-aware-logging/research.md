# Context-Aware Logging Research

> **Status**: ✅ POC Complete  
> **Created**: 2026-01-28  
> **Last Updated**: 2026-01-30
> **Author**: Research findings for evaluating logging solutions

---

## 1. Bối cảnh & Yêu cầu 

### 1.1 Vấn đề hiện tại
Dự án microservices hiện đang sử dụng **Zap** (`go.uber.org/zap` v1.27.1) với việc implement context-aware logging thủ công và không chuẩn hóa.
- **8 microservices** đang dùng Zap.
- **Victorialogs** là đích đến của log, yêu cầu định dạng **JSON** thuần để dễ dàng parse và query.
- Cần **Tracing Support** mạnh mẽ để tích hợp với OpenTelemetry.

### 1.2 Mục tiêu
1.  **JSON Format**: Bắt buộc để tương thích tốt với Victorialogs và các công cụ log aggregation (Graylog, ELK).
2.  **Tracing Support**: Log phải tự động gắn `trace_id` và `span_id` từ OpenTelemetry context mà không cần code thủ công.
3.  **Migration Target**: Sử dụng library **`clog`** (chainguard-dev/clog) cho service **`cart`** như một bước chuyển đổi (POC).

---

## 2. Standardized Log Levels

Để đảm bảo tính nhất quán khi chuyển đổi giữa các thư viện và tương thích với hệ thống monitoring (Victorialogs), dự án sẽ chuẩn hóa các log levels theo thang đo sau:

| Level Name | Value | Description |
| :--- | :--- | :--- |
| **panic** | **5** | Hệ thống gặp lỗi không thể phục hồi và sẽ crash (panic). |
| **fatal** | **4** | Lỗi nghiêm trọng buộc process phải dừng hoạt động (os.Exit). |
| **error** | **3** | Runtime errors, nhưng hệ thống vẫn có thể tiếp tục phục vụ request khác. |
| **warn** | **2** | Cảnh báo về vấn đề tiềm ẩn, deprecated APIs, hoặc sử dụng tài nguyên cao. |
| **info** | **1** | Thông tin xác nhận hệ thống hoạt động bình thường (startup, healthcheck). |
| **debug** | **0** | Thông tin chi tiết phục vụ debug (payload, state changes). |
| **trace** | **-1** | Thông tin chi tiết nhất, tracing flow chi tiết từng step. |

### 2.1 Library Level Comparison Table

Bảng so sánh giá trị Log Level thực tế (Integer values) giữa các thư viện:

| User Standard | **Zap** (`go.uber.org/zap`) | **clog** (`log/slog`) | **zerolog** (`rs/zerolog`) | Note |
| :--- | :--- | :--- | :--- | :--- |
| **panic (5)** | `PanicLevel` (4) | N/A (Note 1) | `PanicLevel` (5) | Slog dùng Error+panic |
| **fatal (4)** | `FatalLevel` (5) | N/A (Note 2) | `FatalLevel` (4) | Slog dùng Error+exit |
| **error (3)** | `ErrorLevel` (2) | `LevelError` (8) | `ErrorLevel` (3) | |
| **warn (2)** | `WarnLevel` (1) | `LevelWarn` (4) | `WarnLevel` (2) | |
| **info (1)** | `InfoLevel` (0) | `LevelInfo` (0) | `InfoLevel` (1) | |
| **debug (0)** | `DebugLevel` (-1) | `LevelDebug` (-4) | `DebugLevel` (0) | |
| **trace (-1)** | N/A (Note 3) | Custom (-8) | `TraceLevel` (-1) | Zap thường dùng Debug |

*   **Note 1 (Slog Panic)**: Slog (và clog) không có level Panic riêng biệt trong thiết kế chuẩn, thường xử lý bằng cách log Error rồi gọi `panic()`.
*   **Note 2 (Slog Fatal)**: Slog không có level Fatal. Triết lý của Go team là logger không nên side-effect (exit).
*   **Note 3 (Zap Trace)**: Zap mặc định không có Trace level, thường map Trace vào Debug hoặc dùng custom core.

---

## 3. Deep Dive: chainguard-dev/clog

**Repository**: https://github.com/chainguard-dev/clog  
**Base**: Wrapper cho `log/slog` (Standard Library Go 1.21+).

### 3.1 Tại sao chọn `clog`?
- **Zero Dependencies**: Sử dụng `slog` của Go, không kéo thêm dependencies nặng nề.
- **Context-First API**: `clog.FromContext(ctx)` giúp lấy logger đã được gắn metadata (như trace ID) ở bất kỳ đâu.
- **JSON Support**: Native support qua `slog.JSONHandler`. Metadata được flatten thành JSON fields chuẩn.
- **Cloud Native**: Thiết kế cho Kubernetes và Cloud Run (GCP), output mặc định rất gần với format của cloud providers.

### 3.2 Tracing Support & OpenTelemetry Integration
Đây là điểm mạnh khi kết hợp với `slog`.
- **Cơ chế**: `clog` (thông qua `slog`) cho phép định nghĩa `Handler` middleware.
- **Implementation**:
    Chúng ta có thể viết một `TracingHandler` đơn giản wrap `slog.JSONHandler`.
    ```go
    // Middleware tự động extract TraceID từ Otel
    func (h *TracingHandler) Handle(ctx context.Context, r slog.Record) error {
        if span := trace.SpanFromContext(ctx); span.SpanContext().IsValid() {
            r.AddAttrs(
                slog.String("trace_id", span.SpanContext().TraceID().String()),
                slog.String("span_id", span.SpanContext().SpanID().String()),
            )
        }
        return h.handler.Handle(ctx, r)
    }
    ```
- **Kết quả**: Mọi log call `clog.InfoContext(ctx, "msg")` sẽ tự động có field `trace_id` trong JSON output.

---

## 4. Deep Dive: rs/zerolog

**Repository**: https://github.com/rs/zerolog  
**Base**: Pure Go, Zero Allocation JSON Logger.

### 4.1 Tổng quan
`rs/zerolog` cung cấp một logger siêu nhanh và đơn giản, dành riêng cho output **JSON**.

### 4.2 Thiết kế & Hiệu năng
API của Zerolog được thiết kế để mang lại trải nghiệm lập trình tuyệt vời đồng thời đảm bảo hiệu suất tối ưu (stunning performance).
- **Chaining API**: API dạng chuỗi độc đáo cho phép zerolog viết log JSON (hoặc CBOR) mà tránh được overhead của memory allocation và reflection.
- **Inspiration**: Uber's `zap` library đi tiên phong trong cách tiếp cận này, nhưng `zerolog` đưa concept này lên tầm cao mới với API đơn giản hơn và performance thậm chí tốt hơn.

### 4.3 Focus & Features
- **Efficient Structured Logging**: Để giữ codebase và API đơn giản, zerolog chỉ tập trung vào structured logging hiệu quả.
- **Console Logging**: Pretty logging trên console được hỗ trợ qua `zerolog.ConsoleWriter` (tuy nhiên inefficient hơn so với JSON mode, chỉ nên dùng cho dev).

### 4.4 Example
```go
// Zero allocation, JSON output
zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
log.Info().
    Str("scale", "833 cents").
    Float64("interval", 833.09).
    Msg("Fibonacci is everywhere")

// Output: {"level":"info","scale":"833 cents","interval":833.09,"time":1560968903,"message":"Fibonacci is everywhere"}
```

### 4.5 Global Settings
Some settings can be changed and will be applied to all loggers:

*   **`log.Logger`**: You can set this value to customize the global logger (the one used by package level methods).
*   **`zerolog.SetGlobalLevel`**: Can raise the minimum level of all loggers. Call this with `zerolog.Disabled` to disable logging altogether (quiet mode).
*   **`zerolog.DisableSampling`**: If argument is `true`, all sampled loggers will stop sampling and issue 100% of their log events.
*   **`zerolog.TimestampFieldName`**: Can be set to customize Timestamp field name.
*   **`zerolog.LevelFieldName`**: Can be set to customize level field name.
*   **`zerolog.MessageFieldName`**: Can be set to customize message field name.
*   **`zerolog.ErrorFieldName`**: Can be set to customize Err field name.
*   **`zerolog.TimeFieldFormat`**: Can be set to customize Time field value formatting. If set with `zerolog.TimeFormatUnix`, `zerolog.TimeFormatUnixMs` or `zerolog.TimeFormatUnixMicro`, times are formatted as UNIX timestamp.
*   **`zerolog.DurationFieldUnit`**: Can be set to customize the unit for `time.Duration` type fields added by `Dur` (default: `time.Millisecond`).
*   **`zerolog.DurationFieldFormat`**: Can be set to `DurationFormatFloat`, `DurationFormatInt`, or `DurationFormatString` (default: `DurationFormatFloat`) to append the Duration as a Float64, Int64, or by calling `String()` (respectively).
*   **`zerolog.DurationFieldInteger`**: If set to `true`, `Dur` fields are formatted as integers instead of floats (default: `false`). *Deprecated: Use `zerolog.DurationFieldFormat = DurationFormatInt` instead.*
*   **`zerolog.ErrorHandler`**: Called whenever zerolog fails to write an event on its output. If not set, an error is printed on the stderr. This handler must be thread safe and non-blocking.
*   **`zerolog.FloatingPointPrecision`**: If set to a value other than `-1`, controls the number of digits when formatting float numbers in JSON. See `strconv.FormatFloat` for more details.

### 4.6 Field Types

#### Standard Types
*   `Str`
*   `Bool`
*   `Int`, `Int8`, `Int16`, `Int32`, `Int64`
*   `Uint`, `Uint8`, `Uint16`, `Uint32`, `Uint64`
*   `Float32`, `Float64`

#### Advanced Fields
*   **`Err`**: Takes an error and renders it as a string using the `zerolog.ErrorFieldName` field name.
*   **`Func`**: Run a func only if the level is enabled.
*   **`Timestamp`**: Inserts a timestamp field with `zerolog.TimestampFieldName` field name, formatted using `zerolog.TimeFieldFormat.
*   **`Time`**: Adds a field with time formatted with `zerolog.TimeFieldFormat`.
*   **`Dur`**: Adds a field with `time.Duration`.
*   **`Dict`**: Adds a sub-key/value as a field of the event.
*   **`RawJSON`**: Adds a field with an already encoded JSON (`[]byte`)
*   **`Hex`**: Adds a field with value formatted as a hexadecimal string (`[]byte`)
*   **`Interface`**: Uses reflection to marshal the type.
*   **`IPAddr`**: Adds a field with `net.IP`.
*   **`IPPrefix`**: Adds a field with `net.IPNet`.
*   **`MACAddr`**: Adds a field with `net.HardwareAddr`

> Most fields are also available in the slice format (`Strs` for `[]string`, `Errs` for `[]error` etc.)

---

## 5. Compatibility với Victorialogs

Victorialogs ingest log qua HTTP/TCP/UDP và tối ưu cho JSON logs.
- **Format**: `clog` xuất ra JSON chuẩn (`{"time": "...", "level": "INFO", "msg": "...", "trace_id": "..."}`).
- **Parsing**: Victorialogs (và Vector) dễ dàng parse JSON này thành các fields để filter.
- **Raw Data**: JSON giữ nguyên cấu trúc raw, đảm bảo tính mở rộng nếu sau này chuyển sang ClickHouse hay Elasticsearch.

---

## 6. Plan: Convert `cart` Service sang `clog`

Kế hoạch chuyển đổi service `cart` từ Zap sang `clog` để kiểm chứng.

### 6.1 Step 1: Chuẩn bị Shared Package
Tạo `services/pkg/logger` mới wrap `clog` và setup default handler (JSON + Tracing).

```go
// services/pkg/logger/logger.go
package logger

import (
    "context"
    "log/slog"
    "os"
    "github.com/chainguard-dev/clog"
)

// Setup cấu hình logger mặc định cho service
func Setup() {
    handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
        Level: slog.LevelInfo,
    })
    // TODO: Add TracingHandler here
    logger := slog.New(handler)
    slog.SetDefault(logger)
}
```

### 6.2 Step 2: Refactor `cart/cmd/main.go`
- Thay thế `zap.NewProduction()` bằng `logger.Setup()`.
- Inject logger vào `context` ở root level: `ctx = clog.WithLogger(ctx, logger)`.

### 6.3 Step 3: Refactor Middleware
- Update logging middleware để sử dụng `clog.FromContext(ctx)`.
- Đảm bảo TraceID từ HTTP header được truyền vào context trước khi logger được khởi tạo/sử dụng.

### 6.4 Step 4: Refactor Business Logic
- Thay format:
    - **Old**: `logger.Info("failed to call", zap.Error(err))`
    - **New**: `clog.ErrorContext(ctx, "failed to call", "error", err)`

---

## 7. Bảng So Sánh Cập Nhật (Feature)

| Feature | Zap | clog (slog wrapper) | Zerolog |
| :--- | :--- | :--- | :--- |
| **JSON Output** | ✅ (High Perf) | ✅ (Native) | ✅ (High Perf) |
| **Tracing Support** | ⚠️ Manual (Fields) | ✅ Easy w/ Handler | ✅ Native Support |
| **API Style** | Fluent / Type-safe | Printf / KV | Chainable |
| **Context Propagation** | ❌ Manual Wrapper | ✅ Built-in | ✅ Built-in |
| **Dependencies** | ~10 | **0** (Stdlib) | ~3 |
| **Usage in Project** | 8 Services | **Target for `cart`** | 0 |

---

## 8. Next Actions

- [ ] **Create `services/pkg/logger`**: Implement `clog` wrapper với JSON handler và OTel integration.
- [ ] **Convert `cart`**: Refactor service `cart` theo plan section 6.
- [ ] **Verify**: Check log output trong Victorialogs để đảm bảo JSON valid và có `trace_id`.
