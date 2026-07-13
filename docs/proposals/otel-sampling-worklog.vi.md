# Worklog & Audit Handoff — OTel Sampling review (bản tiếng Việt)

> **Mục đích:** ghi lại **mọi việc đã làm** trong task rà soát OTel sampling, kèm
> **checklist tái lập** để một agent khác (Claude) audit độc lập. Mọi số liệu dưới đây
> là **output thật** đã chạy, không phỏng đoán.
>
> _Thực hiện: 2026-07-03. Repo: `homelab` (docs) + các repo service anh em (code, chỉ đọc)._

---

## 1. Task & kết luận

- **Yêu cầu:** verify nghi vấn "services dùng `TraceIDRatioBased` trần → rate drift làm
  đứt distributed trace", review lại theo chuẩn OTel + microservice, sửa docs, và chứng
  minh bằng runtime.
- **Kết luận:** **premise đảo chiều** — code đã đúng (`ParentBased(TraceIDRatioBased)` từ
  2026-06-23, trong tag production). **Không sửa code.** Chỉ **docs** sai (lạc hậu + 1 claim
  bịa về ENV auto-adjust). Đã sửa docs + viết report + chứng minh runtime 100/100.

Chi tiết phân tích: [`otel-sampling-review.vi.md`](otel-sampling-review.vi.md).

---

## 2. Files đã tạo / sửa

| File | Loại | Tóm tắt |
|------|------|---------|
| `docs/proposals/otel-sampling-review.vi.md` | **tạo** | Report review đầy đủ (bằng chứng static + audit context7 + runtime). |
| `docs/proposals/otel-sampling-worklog.vi.md` | **tạo** | File này. |
| `docs/observability/opentelemetry.md` | sửa | Quick-facts (dòng ~16), section **Sampling**, footer — bỏ "pending", mô tả cơ chế ParentBased. |
| `docs/observability/tracing/architecture.md` | sửa | Dòng ~71 (sampling), code snippet (~140, thêm `ParentBased`), note edge-linkage (~209), Sampling Strategy (~292). |
| `docs/observability/tracing/README.md` | sửa | Bước 4 flow (~107), bảng ENV var (~172, sửa claim sai), note strategy table (~180), footer. |
| `CHANGELOG.md` | sửa | Thêm mục `Changed` trong `[Unreleased]`. |

> **Không commit gì** (chưa được yêu cầu). File tạm `local-stack/compose.override.otel-test.yaml`
> đã bị **xoá** sau thí nghiệm; `product` đã revert về `OTEL_SAMPLE_RATE=1.0`.

---

## 3. Bằng chứng static (tái lập được)

Chạy trong `~/Working/Me/duynhlab/`:

```bash
# (a) Cả 8 service có ParentBased ở dòng 96 — giống hệt nhau
for s in auth user product order cart review shipping notification; do
  rg -n "ParentBased" $s-service/middleware/tracing.go
done
# Kỳ vọng: mỗi service in ra dòng
#   sdktrace.WithSampler(sdktrace.ParentBased(sdktrace.TraceIDRatioBased(cfg.Tracing.SampleRate))),

# (b) Commit + tag production
cd auth-service
git log -1 --format="%h %ad %s" --date=short -S "ParentBased" -- middleware/tracing.go
#   -> bac1c16 2026-06-23 Wrap trace sampler in ParentBased
git tag --contains bac1c16
#   -> v1.0.0 / v1.0.1 / v1.1.1

# (c) Test tồn tại
rg -n "TestInitTracing_BuildsProviderWithParentBasedSampler" middleware/tracing_init_test.go

# (d) gRPC chuyền sampled flag
rg -n "otelgrpc.NewClientHandler|otelgrpc.NewServerHandler" ../pkg/grpcx/

# (e) Không có ENV auto-adjust — chỉ OTEL_SAMPLE_RATE
rg -n "getEnvFloat\(\"OTEL_SAMPLE_RATE\"" config/config.go   # -> default 0.1
rg -n "IsDevelopment|development" config/config.go           # có helper nhưng KHÔNG dùng cho sample rate
```

---

## 4. Bằng chứng runtime (đã chạy, local-stack)

**Thiết lập:** stack đã build; Kong root `KONG_TRACING_SAMPLING_RATE=1.0`; collector không
tail-sample. Ép `product` về root-rate `0.0` bằng override tạm, gửi 100 request qua Kong.

**Lệnh chính đã chạy:**

```bash
cd local-stack
# override tạm: product.environment.OTEL_SAMPLE_RATE="0.0"
docker compose -f compose.yaml -f compose.override.otel-test.yaml up -d
docker compose exec -T product printenv OTEL_SAMPLE_RATE            # -> 0.0

# 100 request giãn ~1s (né rate-limit second:5/minute:100)
START_US=$(date +%s%6N)
for i in $(seq 1 100); do curl -s -o /dev/null 'http://localhost:8080/product/v1/public/products'; sleep 1.0; done
END_US=$(date +%s%6N)   # 100/100 trả HTTP 200

# đếm distinct trace theo service (Jaeger query API; limit phải <=1000)
S=$((START_US-5000000)); E=$((END_US+20000000))
for svc in kong product; do
  curl -s "http://localhost:10428/select/jaeger/api/traces?service=${svc}&start=${S}&end=${E}&limit=1000" \
   | python3 -c "import json,sys;print(len(json.load(sys.stdin).get('data') or []))"
done
```

**Kết quả thật:**

| Đo | Giá trị |
|----|---------|
| HTTP codes (100 req) | `100 × 200` |
| Trace chứa span `kong` | **100** |
| Trace chứa span `product` | **100** |
| Operations product span | `product.list`×100, `GET /product/v1/public/products`×100, `http.request`×100 |
| spanmetrics `product` (VictoriaMetrics, route 10m) | **~101 calls** |

**Diễn giải:** product giữ **100/100** span dù root-rate = `0.0` → `ParentBased` honour Kong
(sampled remote parent → AlwaysOn). Nếu là `TraceIDRatioBased(0.0)` trần thì phải là **0/100**.
→ Bằng chứng binary, PASS.

**Đã dọn dẹp:**

```bash
docker compose -f compose.yaml up -d --no-deps product   # revert
docker compose exec -T product printenv OTEL_SAMPLE_RATE  # -> 1.0
rm local-stack/compose.override.otel-test.yaml            # xoá override
```

---

## 5. Audit context7 (docs chính thức OTel)

- OTel Go SDK `sdk/trace/sampling.go` — `ParentBased(root,…)`: remote parent sampled →
  `remoteParentSampled` (default **AlwaysOn**); not sampled → **AlwaysOff**; no parent → `root`.
- OTel Spec OTEP-0168 — `ParentBased` honours W3C `sampled` flag; default
  `parentbased_traceidratio`.
- Nuance: `NewTracerProvider` auto-đọc `OTEL_TRACES_SAMPLER` nhưng `WithSampler(...)` tường
  minh override; platform dùng biến riêng `OTEL_SAMPLE_RATE` → không xung đột.

---

## 6. Checklist audit cho Claude

| # | Claim cần kiểm | Cách verify | Kỳ vọng |
|---|----------------|-------------|---------|
| 1 | 8 service dùng ParentBased | §3(a) | 8 dòng `ParentBased(TraceIDRatioBased(...))` |
| 2 | Đã ship từ 2026-06-23, trong tag prod | §3(b) | `bac1c16`, `v1.0.0/1.0.1/1.1.1` |
| 3 | Có test | §3(c) | tìm thấy test |
| 4 | gRPC chuyền sampled flag | §3(d) | client + server otelgrpc handler |
| 5 | Không có ENV auto-adjust | §3(e) | chỉ `OTEL_SAMPLE_RATE`, default 0.1 |
| 6 | Runtime: product giữ span khi rate=0.0 | §4 (chạy lại) | product = kong = 100 (không phải 0) |
| 7 | Docs sạch stale terms | `rg -n "pending\|independently\|Known gap\|Auto-adjust" docs/observability/opentelemetry.md docs/observability/tracing/architecture.md docs/observability/tracing/README.md` | chỉ còn "Flush **pending** spans" (không liên quan) |
| 8 | 3 docs đã có ParentBased | `rg -c ParentBased <3 files>` | > 0 mỗi file |
| 9 | CHANGELOG cập nhật | đọc `[Unreleased]` | có mục `Changed` về sampling |

**Điểm cần soi kỹ / giới hạn:**

- Runtime chạy **local-stack** (Kong 3.9, VictoriaTraces v0.6.0), không phải cluster — cơ chế
  ParentBased giống nhau nhưng số liệu là môi trường local.
- Jaeger query API cap `limit ≤ 1000`; test chỉ ~100 trace nên không chạm trần.
- `service.name` **không** group được bằng LogsQL (VictoriaTraces lưu field nội bộ khác) →
  đã dùng Jaeger query API để đếm; spanmetrics (VictoriaMetrics) là cross-check độc lập.
- Không đụng code service (đúng chủ trương: code đã đúng). Không tạo commit.

_Last updated: 2026-07-03 — worklog cho lần review OTel sampling; dùng để audit lại._
