# RFC-0013 Audit cardinality metrics tầng ứng dụng & playbook scale bằng streaming aggregation

> Bản dịch tiếng Việt để đọc — bản chính thức (source of truth) là
> [README.md](README.md) (English).

| Status | Scope | Created | Last updated |
|--------|-------|---------|--------------|
| superseded (đặt tên metric) | platform-wide | 2026-07-07 | 2026-07-09 |

> **⚠️ Bị thay thế bởi [RFC-0014](../RFC-0014/) (cutover P3, 2026-07-09).** Tên
> metric, label và match pattern streaming-aggregation bên dưới phản ánh thế giới
> client_golang **trước cutover** (`request_duration_seconds{method,path,code}`,
> `job="microservices"`, `requests_in_flight`). Nền tảng nay emit tên semconv qua
> OTLP (`http_server_request_duration_seconds`, label
> `http_request_method`/`http_route`/`http_response_status_code`, không còn `job`).
> RFC này giữ lại **làm hồ sơ audit lịch sử** — kết luận và rubric vẫn đúng; đừng
> đọc các query của nó như hiện trạng.

> **Tiến độ**: P1 (audit + siết chuẩn) và P2 (playbook scale) land cùng RFC
> này. P3a/P3b (shadow pilot trên homelab → adopt) và P4 (remediation) là các
> PR sau.

> **Mọi quyết định là một tradeoff.** Homelab hôm nay **không** có vấn đề
> cardinality (~3k series apps; VMSingle chạy nhàn). RFC này tồn tại để (a)
> chứng minh instrumentation của mình xứng đáng với trạng thái đó, và (b) xây —
> theo chuẩn production-match — playbook cho quy mô mà vấn đề là thật.

## Tóm tắt

Hai deliverable gắn với nhau. **Phần A — audit:** đo và chấm điểm custom
metrics tầng app của cả 9 service Go theo chuẩn đã viết
([metrics-apps.md](../../../observability/metrics/metrics-apps.md)) và quy tắc
label-hygiene của Prometheus; mọi defect tìm thấy được mô tả ngay trong RFC kèm
lịch fix. **Phần B — playbook scale:** phép toán cardinality dự đoán điểm gãy
của pipeline hiện tại (100 → 1.000 services), và kiến trúc streaming
aggregation trên stack VictoriaMetrics mà các platform production dùng khi vượt
ngưỡng đó — chốt thành doc sống
([streaming-aggregation.md](../../../observability/metrics/streaming-aggregation.md))
cộng một **shadow pilot** additive, có giới hạn, trên chính VMAgent của homelab,
rollout đúng kiểu production (shadow → verify → cutover).

## Động cơ

TSDB kiểu Prometheus tính tiền theo **tổ hợp label**, không theo metric. Hygiene
phía app quyết định một replica phát ra gì; ở quy mô fleet, các nhân tử chi
phối (`instance`/`pod` × replicas × churn mỗi lần deploy) nằm ngoài code ứng
dụng và chỉ kiểm soát được ở tầng pipeline. Platform này mô phỏng thực hành
production để học: audit chứng minh (hoặc sửa) tầng hygiene mình sở hữu, còn
playbook + pilot luyện tầng pipeline mình chưa từng cần — trên đúng stack GitOps
thật, không phải demo vứt đi.

### Goals

- Rubric thành văn; mỗi custom metric có **verdict**.
- Mọi defect được **mô tả trong RFC kèm phase fix** (bảng D).
- Baseline cardinality **đo thật** (không ước lượng khi đo được).
- Phép toán điểm gãy tại 9 / 100 / 1.000 services, suy ra từ số của chính mình.
- Thiết kế at-scale trên stack VM (two-tier vmagent streaming aggregation).
- Pilot homelab **không thể làm vỡ** Sloth SLO, recording rules, dashboards
  (bất biến additive-only), promote theo kiểu production.

### Non-Goals

- Deploy đội hình hai tầng router/aggregator trong homelab (thiết kế trên giấy;
  pilot 1-vmagent luyện đúng semantics một cách an toàn).
- Sao chép 1:1 stack của một công ty cụ thể (đường StatsD/OTLP, backend vendor).
- Migrate VMSingle → VMCluster; chính sách retention/downsampling.
- Instrumentation business/DB/cache mới (theo dõi riêng).
- Extract middleware copy-paste vào `pkg` — nêu tên là remediation gốc rễ (D3)
  nhưng là effort 9-repo, theo dõi ngoài RFC này.

## Đề xuất

**Phần A.** Chấm mỗi metric family theo rubric 10 chiều (§ Design Details A).
Findings mang severity (Critical / Required / Consider / Nit), mỗi cái map về
một phase fix.

**Phần B.** Nhận
[streaming-aggregation.md](../../../observability/metrics/streaming-aggregation.md)
làm playbook at-scale của platform, và kiểm chứng cơ chế ngay trên homelab bằng
shadow pilot: VMAgent CR hiện có thêm `streamAggrConfig` để *bổ sung* series
tổng hợp mức fleet (`*:1m_without_instance_pod_*`) chạy cạnh series raw. Sau
giai đoạn soak so sánh tương đương với recording rules `job_app:*`, consumer có
thể được cutover (P3b) — hoặc gỡ shadow; kết quả nào cũng ghi thành ADR-013.

### User Stories

- Là operator của platform, tôi nói được chính xác chi phí series khi thêm một
  endpoint, một replica, hay một service — và chỉ vào bảng số đo.
- Là SRE đối mặt fleet 1.000 service, tôi đi theo decision flowchart để biện
  luận recording rules vs relabel drop vs streaming aggregation vs mô hình hai
  tầng, và thuộc tên các bất biến histogram/sharding.
- Là reviewer, tôi reject được PR thêm label không chặn biên bằng cách trích
  danh sách label cấm trong chuẩn.

### Alternatives (đã cân nhắc và loại)

- **Chỉ recording rules** (hiện trạng): tính *sau khi* ingest — storage trả
  tiền cho raw trước, rules còn cộng thêm series. Đúng ở scale hiện tại (vì
  thế pilot chỉ *shadow*), nhưng là bộ khuếch đại chi phí ở scale lớn.
- **Relabel-drop `instance` lúc scrape**: "aggregate bằng xoá" — sample các
  replica đè nhau last-write-wins thành series rác. Loại.
- **Scale storage ngang** (VMCluster/Thanos/Mimir): scale hoá đơn cho series
  không ai query; cần cho HA/retention nhưng trực giao với chi phí tín hiệu.
- **Pre-aggregate phía client kiểu StatsD**: đẩy state vào process app, mất
  pull-model health + exemplars, thêm protocol. Loại.
- **Không làm gì đến khi đau**: rẻ nhất hôm nay; bỏ mục tiêu học và bỏ defect
  chưa fix. Loại.

## Kiến trúc & Diagram

Xem 4 diagram Mermaid trong [README.md](README.md#architecture--diagrams):
pipeline hiện tại (mọi raw series đổ vào storage), pilot shadow (additive,
consumer giữ nguyên đọc raw), chuỗi nhân cardinality với số đo thật, và
stateDiagram rollout.

## Design Details

### A. Audit

**Rubric 10 chiều**: (1) label bounded — cấm `user_id`, `request_id`,
`session_id`, `email`, raw URL, ID đơn hàng/giỏ/thanh toán, pod UID, image SHA;
(2) đúng loại metric; (3) naming chuẩn Prometheus (`_total` chỉ cho counter);
(4) buckets histogram thống nhất fleet, bọc quanh ngưỡng SLO 500ms; (5)
duplication/drift — 9 bản copy phải giống hệt bản reference; (6) scrape
hygiene; (7) exemplars trên histogram kèm `traceID`; (8) aggregation-first —
label không ai group-by là "cardinality không có khách hàng"; (9) coverage đủ
9 services; (10) cardinality đo thật.

**Baseline (đo 2026-07-06, local-stack, 1 replica/service, traffic thật)**:
cart 720 · product 530 · notification 410 · auth 392 · order 382 · user 135 ·
shipping 83 · review 66 · payment 49 — **Σ 2.777** (cận dưới, label
materialize lazy). Cận trên lý thuyết ≈ **1.800/replica**. Con số "~2.400
fleet" trong docs cũ đã stale — sửa ở P1.

**Kết luận chính**: platform **đậu** bài kiểm tra hygiene mức bài báo — route
template khắp nơi, không ID theo request, label chặn biên. Defect còn lại là
lỗi coverage/độ-chính-xác-docs, không phải bom cardinality.

**Bảng defect** (chi tiết đầy đủ ở bản English):

| # | Severity | Defect | Fix |
|---|---|---|---|
| D1 | Required | Alert `MicroserviceHighRestartRate` hardcode 8 namespace — **thiếu payment** (alerts.yaml:44). | P4 (homelab) |
| D2 | Required | Header "8 services" stale trong rule manifests (alerts.yaml/recording-rules.yaml); prose docs đã sweep riêng. Điểm contested: SLO docs nói "payment chưa có SLO" nhưng checkout-rs áp `slo.enabled: true` vô điều kiện cho mọi service nó render (gồm payment) → sẽ là 9 × 3 = 27 SLO. Fix: sửa header → 9 và verify PrometheusServiceLevel thật ở lần bring-up tới rồi chốt 24 vs 27. | P4 (docs) |
| D3 | Consider | middleware copy-paste 9 repo không có chốt chống drift → extract vào `duynhlab/pkg` (vd `pkg/metricsx`) + harden bản reference cùng lúc (allowlist `method`, defer `Dec()` in-flight, bỏ observe ContentLength âm) — **follow-up tracker**, không phải phase. | Follow-up |
| D4 | Required | Doc chuẩn sai thực tế: số fleet stale, bucket set + danh sách label cấm chỉ nằm ngầm trong code snippet, trạng thái exemplar mâu thuẫn giữa TODO.md và metrics-apps.md. | **P1 ✅ (PR này)** |
| D5 | Consider | spanmetrics ở local-stack mang resource label không chặn biên theo thời gian (`process_pid`, `process_command_args`, `host_name`, …) — mỗi restart re-mint toàn bộ 1.846+ series (riêng order). Fix: allowlist dimensions / bỏ resource conversion trong collector local-stack. | P4 (local-stack) |

### B. Phép toán cardinality (headline)

| Fleet | Raw active series | Samples/s | Khi aggregate bỏ `instance` |
|---|---|---|---|
| 9 services × 1–2 (hôm nay) | ~3k | ~200 | vô nghĩa — nhân tử chỉ 1–2 |
| 100 × 5 | ~300k | ~20k | ~60k |
| 1.000 × 10 | **~6M (+churn)** | ~400k | ~600k |

Chiều `instance` bị trả tiền trên 100% series nhưng chỉ được query trên ~1% —
ở 1.000 services nó là nhân tử ×10 cho storage/index. Chính sự bất đối xứng đó
(không phải số service) là trigger của streaming aggregation.

### C. Thiết kế at-scale

Two-tier vmagent: tầng router stateless consistent-hash
(`shardByURL`/`ignoreLabels`) → tầng aggregator StatefulSet chạy `streamAggr`
strip `instance`/`pod` → storage cluster. Bất biến + failure modes trong
[playbook](../../../observability/metrics/streaming-aggregation.md).

### D. Pilot homelab

1 vmagent = 1 aggregator nên mọi bất biến sharding tự thoả; pilot luyện
**semantics** (dạng rule, tên output, xử lý counter/gauge/histogram,
self-metrics, rollout GitOps) và **quy trình** (shadow → verify → cutover) —
đúng phần chuyển giao được sang thiết kế at-scale. YAML pilot + bất biến an
toàn (không `dropInput`, không `keep_metric_names`, `_bucket`/`_count`/`_sum`
chung một rule, match chỉ `job="microservices"`) xem bản English. P3b cutover
production-style giống rollout `PAYMENT_ENABLED`; kết quả ghi ADR-013.

### Bảng phase

| Phase | Scope | Repos |
|-------|-------|-------|
| **P1 ✅ (PR này)** | Audit + đo baseline + verdicts + bảng D; amend `metrics-apps.md` | homelab (docs) |
| **P2 ✅ (PR này)** | Playbook `streaming-aggregation.md` + wiring index | homelab (docs) |
| **P3a** | Shadow pilot trên VMAgent CR; protocol verify; soak 1 tuần | homelab (kubernetes) |
| **P3b** | Adopt hoặc remove (gated soak); spawn **ADR-013** | homelab |
| **P4** | Fix D1 (payment regex) + D2 (header sweep + verify SLO count) + D5 (spanmetrics) | homelab |

## Security

Không có gì thêm ngoài chính kiểm soát của audit: danh sách label cấm cũng là
quy tắc data-hygiene (label value hiện trên dashboard/alert/URL — không PII,
không token). Pilot không thêm port/component/quyền; Kyverno/PSS giữ nguyên.

## Tác động Observability & SLO

Blast radius của chính RFC được thiết kế bằng 0: Sloth SLO, 17 threshold
alerts, 13 recording rules, dashboard RED đều đọc raw
`request_duration_seconds*` — **shadow pilot không bao giờ rename/drop/sửa
raw series** (bất biến additive-only). Tên output của streamAggr tự chống
va chạm. Theo dõi P3 qua `vm_streamaggr_*`.

## Rollout & rollback

Shadow → Adopt theo stateDiagram trong bản English. P1/P2 docs-only. P3a
additive, rollback = revert commit. P3b chỉ đổi query của consumer — raw vẫn
còn nên rollback là trỏ lại, không phải khôi phục dữ liệu.

## Testing / verification

P1 đã chạy cho RFC này (diff middleware CRLF-normalized so với bản
reference; đo series live). Protocol P3a 7 bước (gate CRD → before/after count →
series mới không có instance/pod → raw không đổi → self-metrics healthy →
equivalence ±5% với `job_app:*` → consumers sạch lỗi) xem bản English.

## Implementation History

- 2026-07-06 — đo baseline: 49–720 series/service, Σ 2.777.
- 2026-07-07 — tạo RFC; P1 + P2 land cùng PR.

## Related

- [streaming-aggregation.md](../../../observability/metrics/streaming-aggregation.md) · [metrics-apps.md](../../../observability/metrics/metrics-apps.md) · [metrics hub](../../../observability/metrics/README.md)
- RFC-0010 (tiền lệ rollout: shadow có cờ → verify → cutover → cleanup)
- ADR-013 — sẽ spawn từ P3b
- Follow-up (D3): extract middleware metrics chung vào `duynhlab/pkg` + harden reference (method allowlist, defer Dec, guard ContentLength âm)
