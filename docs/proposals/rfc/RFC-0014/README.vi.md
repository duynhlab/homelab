# RFC-0014 Full OpenTelemetry adoption: OTLP push cho metrics, logs và traces

> Bản dịch tiếng Việt để đọc — bản chính thức (source of truth) là
> [README.md](README.md) (English). Diagram xem bản English.

| Status | Scope | Created | Last updated |
|--------|-------|---------|--------------|
| provisional | platform-wide | 2026-07-08 | 2026-07-08 |

> **Mọi quyết định là tradeoff.** RFC này chủ động chấp nhận blast radius lớn
> (đo đếm được — mọi consumer metrics đều rename) để đổi lấy MỘT chuẩn
> instrumentation từ đầu tới cuối. Chi phí liệt kê ở Drawbacks +
> [tracking.md](tracking.md); rollout thiết kế để không bước nào không lùi được.

## Tóm tắt

Chuyển cả 9 service (+ order-worker) từ stack hybrid hiện tại (client_golang
scrape + 3 schema log qua Vector + OTel chỉ cho traces/bridge) sang **chuẩn
OpenTelemetry đầy đủ**: một OTel SDK mỗi service phát **metrics, logs, traces
qua OTLP push** xuyên otel-collector sẵn có, **đổi tên metric sang semconv
ngay**. Metrics vào VictoriaMetrics qua OTLP ingest (đi qua vmagent — giữ chỗ
relabel + stream aggregation), logs vào VictoriaLogs với **`trace_id` là field
query được thật** (fix tận gốc correlation log↔trace đang gãy), traces vẫn về
Tempo. `checkout-service` được miễn, ở lại đường legacy sau hàng rào
`legacy-checkout`.

## Động cơ

1. **Chuẩn hoá**: 2 API metrics + 2 naming convention trên 1 endpoint, 3
   schema JSON log, ~380 dòng tracing init trùng ×9 — mỗi seam đều đã sinh
   drift thật (cart middleware, product tracing, user log level).
2. **Correlation gãy đúng chỗ quan trọng**: `trace_id` không phải field trong
   VictoriaLogs → Tempo traces→logs và query runbook match rỗng; exemplar chết
   toàn tuyến và VM sẽ không bao giờ hỗ trợ (won't-fix). Đường OTLP logs fix
   tận gốc: VictoriaLogs map `TraceId` → field `trace_id`.
3. **Hướng ngành**: OTel Go stable cho traces+metrics (v1.44), beta cho logs
   *bridge* (chấp nhận); pattern SDK→Collector→backend là chuẩn production
   (eBay, Shopify, Skyscanner ~1.000 services). Platform này tồn tại để mirror
   production — đây chính là practice đó.

### Goals
- Một chuẩn instrumentation: OTel API trong lib code, 1 điểm wire
  `SetupObservability` mỗi service, OTLP push cả 3 signal.
- Semconv ngay: `http.server.request.duration` → PromQL thấy
  `http_server_request_duration_seconds_*` (translation của VM) — rename 1 lần.
- Correlation khôi phục: `trace_id:"<id>"` trả logs; Tempo traces→logs chạy.
- Không flag day: mọi phase dual-emit/shadow, rollback 1-file/1-env (tiền lệ
  `PAYMENT_ENABLED`).
- Diệt lớp drift: 4 file middleware ×9 gộp về `pkg/obsx` v2.

### Non-Goals
Checkout-service (miễn) · VMCluster/retention · TSDB có exemplar (chấp nhận
mất) · instrumentation business/DB/cache mới · thay Vector cho pod không
instrument (Vector ở lại vĩnh viễn).

## Đề xuất

**OTel một trang — API vs SDK vs Contrib**: lib code chỉ import **API**
(no-op nếu chưa wire); `main()` wire **SDK** (provider/processor/Resource);
**exporter** là plugin của SDK; **Contrib** = otelgin/otelgrpc/runtime/bridges.
Với Go, "Logs Beta" = *bridge API* beta — **code app không bao giờ gọi API
logs của OTel**; zap call sites giữ nguyên, chỉ đổi handler trong main
(otelzap tee). Stability (v1.44): Traces Stable · Metrics Stable · Logs Beta.

**Alternatives** (bảng đầy đủ ở bản English): (1) giữ hybrid pull — bị loại
theo quyết định (verdict cũ dựa trên tiền đề "rename không kham nổi", tiền đề
đã đổi); (2) OTel SDK + Prometheus exporter pull — bị loại vì trả gần đủ chi
phí SDK mà không fix correlation lẫn log-schema; (3) **full OTLP push — chọn**.

## Kiến trúc

(2 Mermaid ở bản English.) In-process: 1 call `obsx.SetupObservability(ctx,
cfg)` = Resource semconv v1.41 (k8s.namespace/pod từ Downward API) +
TracerProvider (giữ nguyên) + MeterProvider (PeriodicReader **15s**, Views:
13-bucket cho duration, byte-bucket cho body.size, drop server.address/port
phía rpc client, cardinality backstop 2000) + LoggerProvider + otelzap tee
(stdout giữ cho kubectl) + `runtime.Start`. Cluster: services → collector
(pipeline metrics `[memory_limiter, deltatocumulative, batch]`, 512Mi) →
**vmagent :8429 OTLP** (flags D-1/D-2 + relabel D-3 + streamAggr) → VMSingle;
logs → VictoriaLogs (`VL-Stream-Fields: service.name,k8s.namespace.name`);
traces → Tempo. Infra exporters + checkout vẫn scrape; Vector ở lại cho pod
không instrument.

## Design Details

**Quyết định D-1…D-14** (bảng đủ ở bản English): D-1
`-opentelemetry.usePrometheusNaming` · D-2 allowlist resource-attrs (**land
trước mọi push** — VM mặc định promote hết → bom churn) · D-3 relabel
`service_name→app`, `k8s_namespace_name→namespace` (giữ hình `sum by (app,
namespace)`) · D-4 thay `up{}` bằng absence-alert trên `go_goroutine_count` +
alert self-metrics collector · D-5 mở rộng collector sẵn có · D-6 OTLP
http/protobuf :4318 (VM không nhận gì khác) · D-7 PeriodicReader 15s explicit
(= scrape hiện tại; mặc định 60s là regression ngầm 4×) · D-8 pin semconv
v1.41 · D-9 Temporal giữ OTel handler, OnError fix · D-10 grpcx
WithFilter + Views · D-11 tracker metricsx **superseded** → obsx v2 · D-12
logger hội tụ **zapx + otelzap** (clog nghỉ, zerolog freeze cho checkout) ·
D-13 checkout: ServiceMonitor trim + nhóm alert `legacy-checkout` có điều kiện
retire, 0 thay đổi repo checkout · D-14 chấp nhận mất exemplar (đã chết sẵn).

**Mapping metrics** (bảng đủ + 2 bẫy label ở bản English): duration →
`http_server_request_duration_seconds_*` (labels http_request_method /
http_route / http_response_status_code; **View 13-bucket BẮT BUỘC** — semconv
mặc định thiếu `le=2` và 0.2/0.3); in-flight → `http_server_active_requests`
(mất per-path — chấp nhận); sizes → `*_body_size_bytes_*` (View byte buckets);
`up{}` → D-4; `go_goroutines` → `go_goroutine_count`; GC summary → histogram
`go_memory_gc_pause_duration_seconds_*`; RSS → **không có tương đương Go** →
alert chuyển cAdvisor `container_memory_working_set_bytes`; `rpc_*` giữ nguyên.
Bẫy: `job="microservices"` không bao giờ quay lại (artifact relabeling);
`app`/`namespace` cũng vậy → cứu bằng D-2+D-3.

**Blast radius đo thật** (checklist sống: [tracking.md](tracking.md)): 17
alerts (27 refs) · 15 recording rules (tên record re-mint) · mop chart 3 SLI
(7 refs → toàn bộ rule Sloth regenerate) · 27 panels + 2 template vars · 19
docs files (140 dòng) · RFC-0013 P3 pattern · ServiceMonitor + PodMonitor
worker retire.

### Phases (bảng đủ + exit/rollback ở bản English)

| Phase | Nội dung chính | Repos |
|---|---|---|
| **P0** | pkg obsx v2 `SetupObservability` + policy page (`docs/observability/opentelemetry.md` rewrite); providers sau cờ env (mặc định off). Exit: pkg tag + unit test Views. | pkg, homelab docs |
| **P1** | Dual-emit metrics: services bật `OTEL_METRICS_ENABLED`, client_golang GIỮ NGUYÊN; vmagent flags + relabel **land trước, canary 1 service trước fleet**. Rollback: tắt env. | 9 repos, homelab, helm-charts |
| **P2** | Bản new-name của mọi consumer (alerts/rules/mop SLI/dashboards/vars + cặp alert gRPC east-west mới); cũ+mới cùng chạy, alert mới về staging receiver. Exit: **soak ≥1 tuần** khớp tolerance. | homelab, helm-charts, grafana-dashboards |
| **P3** | Cutover: retire scrape apps (trim còn checkout) + bật D-4 **cùng commit**; retire nhóm cũ (trừ legacy-checkout); gỡ code client_golang ở đợt PR SAU (đó chính là rollback plan). Exit: **pod-kill test** + 1 chu kỳ Sloth. Spawn ADR (số lấy lúc land — ADR-013…015 đã thuộc RFC-0012). | homelab → 9 repos + pkg |
| **P4** | Logs wave: auth+cart hội tụ zapx trước; per-service bật `OTEL_LOGS_ENABLED` (otelzap → OTLP → VL) + pod label loại khỏi Vector; thống nhất level 4xx; Tempo tracesToLogsV2 trỏ field thật. Exit: `trace_id:"<id>"` trả logs; volume ±10%. | pkg, 9 repos, homelab |
| **P5** | Cleanup + docs sweep 19 files; viết lại pattern streamAggr RFC-0013; xoá middleware chết ×9; document hàng rào legacy-checkout. | homelab, 9 repos |

### Bật / tắt
2 cờ env per service (`OTEL_METRICS_ENABLED`, `OTEL_LOGS_ENABLED`, mặc định
off) — bật là đổi values, tắt là revert; không cần rebuild trên đường rollback
cho tới đợt gỡ code cuối.

### Drawbacks
Mất `up{}` (regression thật, chấp nhận có guard) · exemplar off vĩnh viễn
trên đường VM · cửa sổ dual-emit nhiều tuần (2 tên cho 1 sự thật) · logs đi
bridge beta · collector thành hop mới cho metrics.

## Security
Không đổi PSS/Kyverno/ports; OTLP plaintext nội cluster như đường traces hiện
tại — NetworkPolicy là hàng rào; luật cấm PII/token trong label áp luôn vào
allowlist D-2.

## Observability & SLO impact
Cạnh sắc nhất = coupling Sloth/mop (SLI nằm trong Helm chart — rename sai là
cả cây SLO alert lặng lẽ đổi) → P2 render song song ≥1 tuần + so error-budget
trước P3. View 13-bucket bảo toàn Apdex (le=0.5/2) + mốc SLO 0.2/0.3/0.75.
Dual-emit tăng ~2× series app (~3k→6k; VMSingle đang nhàn). Signal mới cần
canh: exporter-failure collector, `otel.metric.overflow`, stream count VL.

## Rollout & rollback
StateDiagram ở bản English. Bất biến: **đường legacy không bao giờ bị phá
trước khi bản thay thế sống sót qua soak + kill test**; xoá code luôn đi sau
cutover config một đợt PR.

## Testing / verification
Exit criteria per phase (bảng trên) + **merge gate cho mọi phase đụng service
code (P1/P3-code/P4): e2e local-stack** — `docker compose up -d --build`
(throttle), curl flows + **`agent-browser` test login flow** (alice/password123
by username → cart → order details), verify signal mới trên VM/VL local. Go
gauntlet trước mọi push; homelab PR chạy `make validate`. P0 có integration
test pin bộ ba (SDK, contrib, semconv).

## Implementation History
- 2026-07-08 — RFC tạo từ observability review (5-agent) + deep research OTel/
  VictoriaMetrics (3 agent) + design synthesis; baseline đo trong tracking.md.

## Related
Supersede: verdict "Option C" của review + RFC-0013 D3 (→ D-11) + RFC-0013 P4
phần pkg-seam (→ P0). Tương tác: RFC-0013 P3 pilot chạy tiếp tới P3 của RFC
này, pattern viết lại ở P5. Checklist: [tracking.md](tracking.md). ADR: spawn
tại P3 cutover (số lấy lúc land). Docs: P0 rewrite
`docs/observability/opentelemetry.md` thành policy page; mỗi phase update docs
liên quan.
