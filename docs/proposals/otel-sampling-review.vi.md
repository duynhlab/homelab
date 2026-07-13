# Đánh giá thiết kế OTel Sampling — ParentBased (bản tiếng Việt)

> **Trạng thái:** review / finding — **không cần sửa code.** Đây là báo cáo xác minh
> một nghi vấn thiết kế (sampling làm "đứt" distributed trace). Kết luận: **code đã
> đúng chuẩn OpenTelemetry**; vấn đề chỉ nằm ở **tài liệu bị lạc hậu**.
>
> _Soát: 2026-07-03, nhánh `main` + các repo service (8 services, `pkg`), đối chiếu
> docs chính thức OpenTelemetry qua MCP context7, và một bài kiểm chứng runtime trên
> `local-stack`. Dẫn chứng kèm file:line._

---

## 0. Tóm tắt nhanh

- **Nghi vấn ban đầu (đúng về lý thuyết):** các service dùng `TraceIDRatioBased(0.1)`
  *trần*, thiếu `ParentBased` wrapper → mỗi hop tự quyết định sample, không follow root
  (Kong). Nếu một component đổi rate (rate drift), trace sẽ bị xé giữa chừng.
- **Nhưng khi verify sâu, premise đảo chiều:** cả 8 service **đã** dùng
  `ParentBased(TraceIDRatioBased(rate))` từ **2026-06-23** (commit `bac1c16`), nằm trong
  các tag production `v1.0.0 / v1.0.1 / v1.1.1`. Đây đúng là default khuyến nghị của OTel
  (`parentbased_traceidratio`). **Kịch bản "Service B đổi 5% làm đứt trace" không còn xảy ra.**
- **Chỗ sai thật sự là DOCS:** `opentelemetry.md`, `tracing/architecture.md`,
  `tracing/README.md` vẫn ghi "ParentBased **pending**" / "sample **independently**" —
  lạc hậu so với code đã ship.
- **Doc-bug thứ hai:** `tracing/README.md` claim `ENV` **tự động** chỉnh sampling
  (`development=100%`) — **sai**, code không hề có nhánh ENV-override; `OTEL_SAMPLE_RATE`
  là knob duy nhất (default `0.1`), `local-stack` set `1.0` **tường minh**.
- **Bằng chứng runtime (local-stack):** ép `product` về root-rate `0.0` trong khi Kong
  root = `1.0`, gửi 100 request → **product giữ 100/100 span** (đúng ParentBased). Thiết
  kế sai giả định sẽ cho **0/100**.
- **Không cần sửa code.** Việc cần làm chỉ là cập nhật 3 tài liệu về đúng thực tế.

---

## 1. Nghi vấn ban đầu & vì sao nó hợp lý về lý thuyết

Với `TraceIDRatioBased(rate)` *trần* (không `ParentBased`), mỗi service tự "gieo xúc xắc"
theo rate của riêng nó. Hôm nay nó *tình cờ* chạy đúng vì `TraceIDRatioBased` **tất định
theo `trace_id`** và mọi nơi cùng 10% → các quyết định trùng nhau. Nhưng chỉ cần một
component lệch rate:

```
Kong (10%):     sample ✅
Service A (10%): sample ✅
Service B (5%):  drop ❌   ← trace bị "xé" ở đây
Service C (10%): sample ✅
```

Phân tích này **đúng** — nếu code thực sự dùng sampler trần. Đó là lý do phải verify.

---

## 2. Hiện trạng code (ground truth)

### Sampler — đã bọc `ParentBased` ở cả 8 service

Cả 8 service (`auth/user/product/order/cart/review/shipping/notification-service`) có dòng
**giống hệt** trong `middleware/tracing.go:96`:

```go
// ParentBased: honor the upstream sampling decision so distributed
// traces aren't fragmented when SampleRate < 1.0 (e.g. prod 10%).
sdktrace.WithSampler(sdktrace.ParentBased(sdktrace.TraceIDRatioBased(cfg.Tracing.SampleRate))),
```

- **Commit:** `bac1c16 "Wrap trace sampler in ParentBased"` — ngày **2026-06-23**.
- **Có trong tag production:** `v1.0.0`, `v1.0.1`, `v1.1.1` (`git tag --contains bac1c16`),
  nằm trên `origin/main` → image đang chạy **đã** có ParentBased.
- **Test:** `middleware/tracing_init_test.go` có
  `TestInitTracing_BuildsProviderWithParentBasedSampler`.

### gRPC east-west chuyền sampled flag

`pkg/grpcx` gắn otelgrpc stats handler ở cả hai đầu → `traceparent` (kèm sampled flag) đi
qua gRPC metadata:

- `pkg/grpcx/client.go:72` — `grpc.WithStatsHandler(otelgrpc.NewClientHandler())`
- `pkg/grpcx/server.go:77` — `grpc.StatsHandler(otelgrpc.NewServerHandler())`

### Sample rate — không có nhánh ENV auto-adjust

`config/config.go:146` — nguồn **duy nhất** của rate:

```go
SampleRate: getEnvFloat("OTEL_SAMPLE_RATE", 0.1), // 10% default (production)
```

`IsDevelopment()` có tồn tại nhưng **không** dùng để chỉnh sample rate. `local-stack`
set `OTEL_SAMPLE_RATE=1.0` **tường minh** (`compose.yaml:27`), Kong root cũng `1.0`
(`compose.yaml:514`). Không có logic "ENV=development → 100%".

---

## 3. Đối chiếu docs chính thức OpenTelemetry (MCP context7)

### Cơ chế `ParentBased` (OTel Go SDK `sdk/trace/sampling.go`)

`ParentBased(root, ...)` chọn sampler theo parent:

| Tình huống | Sampler áp dụng | Mặc định |
|------------|-----------------|----------|
| Remote parent **sampled** (Kong→service qua `traceparent`) | `remoteParentSampled` | **AlwaysOn** |
| Remote parent **not sampled** | `remoteParentNotSampled` | **AlwaysOff** |
| Local parent sampled / not | `localParentSampled` / `localParentNotSampled` | AlwaysOn / AlwaysOff |
| **Không parent** (là root) | `root` | `TraceIDRatioBased(rate)` |

→ Hệ quả then chốt: **rate riêng của một service chỉ có tác dụng khi service đó là
root**. Khi có parent (đường Kong→service, hay service→service qua gRPC), nó **luôn
honour** quyết định của parent. Rate drift **không thể** xé trace giữa chừng.

### Spec (OTEP-0168)

`ParentBased` "honors the W3C `sampled` flag and copies incoming tracestate keys to the
child" — nền tảng của *consistent / partial-trace sampling*, và là default khuyến nghị
`parentbased_traceidratio`.

### Nuance đáng ghi vào docs

`NewTracerProvider` auto-đọc biến chuẩn `OTEL_TRACES_SAMPLER` *trước*, nhưng option
`WithSampler(...)` tường minh apply *sau* nên **override** nó. Platform dùng biến **riêng**
`OTEL_SAMPLE_RATE` (đọc vào `cfg`), không phải `OTEL_TRACES_SAMPLER` chuẩn → không xung
đột. (Củng cố note đã có sẵn trong `opentelemetry.md`.)

> `ConsistentProbabilityBased` (OTEP-4673, dùng `tracestate ot=r:p`) là **experimental** —
> chỉ để tham khảo thêm, platform **không** dùng.

---

## 4. Kiểm chứng runtime (local-stack) — bằng chứng "sống"

**Thiết kế binary discriminator.** Kong root = `1.0` (mọi trace bắt đầu đều sampled);
collector **không** tail-sample (`otel-collector-config.yaml` chỉ có `batch` + `spanmetrics`)
→ số span đếm được phản ánh đúng quyết định head-sampling. Ép `product` về root-rate `0.0`:

- Nếu **ParentBased** (code hiện tại): product là remote child của Kong → `remoteParentSampled=AlwaysOn` → giữ **100%** span (root-rate 0.0 không bao giờ được dùng).
- Nếu **`TraceIDRatioBased(0.0)` trần** (thiết kế sai giả định): product drop **100%** → **0 span**.

**Cách chạy:** override tạm `product.environment.OTEL_SAMPLE_RATE=0.0`, gửi **100** request
`GET /product/v1/public/products` qua Kong (`:8080`), giãn ~1s/req (100/100 trả `200`, không
dính rate-limit), chờ export, đếm distinct trace theo service qua Jaeger query API của
VictoriaTraces.

**Kết quả:**

| Đo | Giá trị | Kỳ vọng ParentBased | Chữ ký nếu "đứt trace" |
|----|---------|---------------------|------------------------|
| Trace chứa span `kong` (cửa sổ test) | **100** | ~100 | ~100 |
| Trace chứa span `product` (cửa sổ test) | **100** | ~100 | **~0** |
| Tỷ lệ `product/kong` | **1.00** | ≥ 0.95 | ~0.00 |
| spanmetrics `product` (route, VictoriaMetrics) | **~101 calls** | ~100 | ~0 |
| Operations của product span | `product.list`×100, `GET /product/v1/public/products`×100, `http.request`×100 | — | — |

→ **PASS tuyệt đối.** product giữ đủ 100/100 span **dù root-rate = 0.0**, chứng minh
`ParentBased` đang honour quyết định của Kong. Sau đo đã revert product về `1.0` và xoá
file override (không commit).

---

## 5. Các doc-bug cần sửa

| File | Dòng | Vấn đề | Sửa thành |
|------|------|--------|-----------|
| `docs/observability/opentelemetry.md` | 16 | "`ParentBased` wrapper **pending**" | Đã dùng `ParentBased(TraceIDRatioBased)` = `parentbased_traceidratio` |
| `docs/observability/opentelemetry.md` | 109–124 | "Known gap … fix … pending" | Mô tả cơ chế ParentBased đã triển khai đúng |
| `docs/observability/opentelemetry.md` | 159 | footer "ParentBased gap documented" | footer phản ánh đã implement |
| `docs/observability/tracing/architecture.md` | 140 | code snippet còn `TraceIDRatioBased` trần | thêm `ParentBased` wrapper cho khớp code |
| `docs/observability/tracing/architecture.md` | 209–215 | "services *should* use ParentBased (follow-up)" | services **đã** dùng → completeness đảm bảo |
| `docs/observability/tracing/architecture.md` | 71, 294 | "100% in development" (ngụ ý auto) | 100% chỉ khi `OTEL_SAMPLE_RATE=1.0` tường minh |
| `docs/observability/tracing/README.md` | 107 | "sample **independently** … ParentBased pending" | downstream honour root qua ParentBased |
| `docs/observability/tracing/README.md` | 172 | `ENV` "Auto-adjust sampling: development=100%" | **SAI** — `OTEL_SAMPLE_RATE` là knob duy nhất, ENV không auto-adjust |
| `docs/observability/tracing/README.md` | 442 | footer "independent-sampling caveat (ParentBased pending)" | bỏ caveat |

---

## 6. Khuyến nghị

1. **Sửa 3 docs** theo bảng mục 5 (đây là toàn bộ việc cần làm — không đụng code).
2. **Không** thêm `ConsistentProbabilityBased` — thiết kế hiện tại đã đủ chuẩn cho nhu cầu;
   consistent-probability là experimental.
3. Cân nhắc thêm một dòng trong docs về **cách tự kiểm chứng** (bài test mục 4) để lần sau
   không phải nghi ngờ lại.

---

## Tài liệu tham khảo

- OTel Go SDK — `ParentBased` semantics: `sdk/trace/sampling.go` (remoteParentSampled=AlwaysOn / remoteParentNotSampled=AlwaysOff / root=delegate).
- OTel Spec — [OTEP-0168 sampling propagation](https://github.com/open-telemetry/opentelemetry-specification/blob/main/oteps/trace/0168-sampling-propagation.md); [sampling guidance](https://opentelemetry.io/docs/concepts/sampling/).
- Docs nội bộ: [`../observability/opentelemetry.md`](../observability/opentelemetry.md) · [`../observability/tracing/architecture.md`](../observability/tracing/architecture.md) · [`../observability/tracing/README.md`](../observability/tracing/README.md).

_Last updated: 2026-07-03 — verify ParentBased đã ship (commit `bac1c16`, tag v1.0.0–v1.1.1); runtime proof product 0.0 vs Kong 1.0 = 100/100; docs cần cập nhật._
