# Streaming Aggregation — playbook metrics ở quy mô lớn

> Bản dịch tiếng Việt để đọc — bản chính thức (source of truth) là
> [streaming-aggregation.md](streaming-aggregation.md) (English).

Cách một pipeline metrics sống sót qua 1000+ microservices: aggregate series
**ngay trên đường bay** — trước khi chúng kịp trở thành cardinality trong
storage — thay vì trả tiền lưu dữ liệu per-instance không ai query. Đây là
tầng playbook nằm trên [app-side cardinality control](metrics-apps.md): hygiene
phía app chặn biên *một replica phát ra gì*; streaming aggregation chặn biên
*cả fleet tốn bao nhiêu*.

| | |
|---|---|
| **Status** | **Playbook at-scale** — shadow pilot theo [RFC-0013](../../proposals/rfc/RFC-0013/README.md) P3; **không** phải pipeline mặc định của homelab |
| **Engine** | Streaming aggregation của vmagent / VictoriaMetrics single-node |
| **Bề mặt config** | `VMAgent` CR `remoteWrite[].streamAggrConfig` (VM Operator) |
| **Vấn đề giải quyết** | Cardinality label per-instance × replicas × churn ở quy mô fleet |
| **Mô hình chi phí** | State nằm trong RAM aggregator theo window; storage chỉ nhận output đã aggregate |
| **Trigger** | Label per-instance chi phối active series VÀ query mức fleet chiếm đa số |

---

## Tổng quan

TSDB kiểu Prometheus không tính tiền theo metric — nó tính theo **time
series**: mỗi tổ hợp `tên metric + bộ label` là một series. Mọi bài toán scale
của pipeline metrics rốt cuộc là phép nhân này vượt kiểm soát:

```
series ≈ Σ theo service ( replicas × tổ-hợp-label × series-mỗi-tổ-hợp )
```

Hygiene phía app (route template, label chặn biên, không ID theo request) giữ
*tổ-hợp-label* trong tầm. Nhưng có hai nhân tử **không** kiểm soát được trong
code ứng dụng:

1. **`instance` (và `pod`)** — tầng scrape gắn vào, mỗi replica một giá trị.
   Nó nhân mọi series của app với số replica, và mỗi lần deploy/restart lại
   mint một bộ mới (churn).
2. **Kích thước fleet** — hôm nay 9 services; platform lớn chạy hàng trăm đến
   hàng nghìn.

Ở quy mô fleet, gần như mọi câu hỏi vận hành hỏi ở mức service/route ("service
nào lỗi", "endpoint nào chậm"), không hỏi từng pod. Chiều per-instance bị **trả
tiền trên 100% series** nhưng chỉ được **query trên ~1%**. Streaming
aggregation gỡ chiều đó ngay trong pipeline — sample raw được gom trong RAM
theo window cố định, chỉ series đã aggregate chạm tới storage.

## Phép toán cardinality

**Một replica của platform này phát ra gì** (đo từ local-stack đang chạy, 1
replica, traffic thật — label materialize lazy nên số này tiến dần về cận
trên): cart 720 · product 530 · notification 410 · auth 392 · order 382 ·
user 135 · shipping 83 · review 66 · payment 49 → **Σ 2.777**.

Cận trên lý thuyết mỗi replica với middleware chuẩn fleet (~12 route × ~4
status = ~48 combo):

```
http_server_request_duration_seconds       : 48 × (14 bucket + _sum + _count) ≈ 768
http_server_(request|response)_body_size_bytes : 48 × 8 × 2 ≈ 768
(http_server_active_requests)               : không phát ra — otelgin v0.69 không có gauge in-flight
go_* / process_*                            : ~250
                                            ≈ 1.800 series / replica (worst-case)
```

**Cùng phép toán ở quy mô fleet** (giả định thận trọng 600 series thực/replica,
scrape 15s):

| Fleet | Replicas | Raw active series | Samples/s | Sau khi strip `instance` |
|---|---|---|---|---|
| 9 services (homelab) | 1–2 | ~3k | ~200 | ~2,5k — *vô nghĩa, nhân tử chỉ 1–2* |
| 100 services | ×5 | ~300k | ~20k | ~60k |
| 1.000 services | ×10 | **~6M** | **~400k** | **~600k** |
| 1.000 services + churn deploy hằng ngày | ×10 | 6M active + hàng triệu series cũ còn trong index | — | churn biến mất: series aggregate không mang danh tính pod |

Hai thứ gãy trước khi cột raw phình: **RAM index/storage** (scale theo active
+ vừa-churn) và **chi phí query** (`sum by (app)` trên 6M raw series quét 6M
điểm mỗi step — trên mỗi lần refresh dashboard). Ý tưởng cốt lõi — đã được
chứng minh công khai ở các shop chạy 100M+ samples/s: **làm `sum without
(instance)` một lần trong pipeline thay vì trên mọi query**, và đừng bao giờ
để series per-instance chạm TSDB.

## Vì sao các công cụ quen thuộc không giải được

| Cách | Vì sao hụt hơi ở scale |
|---|---|
| **Recording rules** (`app:*` của mình) | Chạy *sau khi* ingest — storage đã trả tiền cho raw; rules còn **cộng thêm** series. Đúng ở scale nhỏ; là bộ khuếch đại chi phí ở scale lớn. |
| **Relabel-drop `instance`** | "Aggregate bằng xoá" là sai: sample của các replica đè nhau last-write-wins thành series rác. Chỉ an toàn cho series vứt hẳn. |
| **Scale storage ngang** (cluster/Thanos/Mimir) | Trả tiền lưu cardinality không có người đọc. Rồi sẽ cần cho HA/retention — nhưng nó scale *hoá đơn*, không scale signal-to-noise. |
| **Client aggregate kiểu StatsD** | Đẩy aggregation vào process app + protocol riêng; mất pull model, mất `up` per-replica, mất exemplars. |

Streaming aggregation **ghép cùng** chứ không thay recording rules (query-
shaping trên series đã nhỏ) và storage cluster (HA) — nó kiểm soát cái gì được
*vào* storage.

## Cơ chế hoạt động

vmagent (và VM single-node) áp rule aggregation trên **đường remote-write**:
sample khớp rule được gom vào state trong RAM; mỗi `interval` state flush ra
series output mới.

```yaml
- match: 'http_server_request_duration_seconds_bucket'  # selector
  interval: 1m                               # cửa sổ aggregate
  without: [instance, pod]                   # label bị gỡ
  outputs: [total]                           # hàm aggregate
```

Tên output tự chống va chạm:
`http_server_request_duration_seconds_bucket:1m_without_instance_pod_total` — raw (nếu
giữ) và aggregate sống cạnh nhau.

**Chọn output theo loại metric** (lỗi phổ biến nhất):

| Loại | Output đúng | Sai (và vì sao) |
|---|---|---|
| Counter (`*_total`, histogram `_bucket`/`_count`/`_sum`) | `total` (nhận biết counter-reset) hoặc `increase` | `sum_samples` — cộng giá trị cumulative thô → rác khi reset/restart |
| Gauge (độ sâu queue, active connections) | `avg`, `max`, `min`, `last` | `total` coi gauge như counter |
| Phân bố latency | aggregate histogram sẵn có bằng `total`, hoặc `quantiles(...)` | trung bình các percentile per-replica — percentile không cộng trung bình được |

**Bất biến histogram**: (1) `_bucket`/`_count`/`_sum` phải cùng một danh sách
`without` — lệch là `histogram_quantile()` trả NaN hoặc nói dối; (2) mọi bucket
`le` của một histogram phải về **cùng một** aggregator — không bao giờ shard
theo `le`.

## Kiến trúc at-scale — mô hình hai tầng

Một aggregator không ôm nổi state cả fleet, còn đặt load balancer trước N
aggregator là *sai* chứ không chỉ chậm: aggregation là stateful, tính đúng đòi
hỏi **mọi sample của một series output gặp nhau trong một process**. Lời giải
là sharding tất định — tầng router stateless consistent-hash series xuống tầng
aggregator stateful, hash bỏ qua đúng những label mà aggregator sẽ strip
(`shardByURL` + `shardByURL.ignoreLabels=instance,pod`). Xem diagram + đầy đủ
bất biến trong [bản English](streaming-aggregation.md#architecture-at-scale--the-two-tier-pattern);
tóm tắt: shard key = label giữ lại; không LB giữa hai tầng; aggregator định
danh từng pod (StatefulSet + headless DNS); scale-out tầng aggregator gây một
nhịp reshuffle (cùng lớp sự kiện với restart).

**Một window làm gì**: fold sample vào state theo key (labels trừ
`[instance, pod]`) → flush tại biên interval → state là RAM-only nên restart
giữa window mất window đó (window đầu sau start cũng bỏ). Thiết kế cho hệ quả
này: alerting SLO phải chịu được gap 1 interval; sample trễ quá
`staleness_interval` bị bỏ — giữ `interval ≥ 2× scrape interval`; HA scrape
pair khử trùng lặp bằng `dedup_interval` trước khi fold.

## Khi nào cần?

Đi theo decision flowchart trong [bản English](streaming-aggregation.md#when-do-you-need-this):
hoá đơn/RAM có đang phình? → label phía app đã bounded chưa (chưa thì fix
instrumentation trước — "aggregate rác thì lưu ít rác hơn, nhưng vẫn là rác")
→ tăng trưởng có do instance/pod × replicas × churn không? → còn cần query
per-instance thường xuyên không? → nếu hiếm: streaming aggregation theo trình
tự **shadow (keepInput) → verify → cutover consumer → dropInput**; một vmagent
không đủ state/HA thì lên hai tầng.

Homelab hôm nay trả lời "chưa" ngay câu đầu (~3k series apps) — vì thế pilot
bên dưới được scope là **shadow để học**, không phải để tiết kiệm. Playbook
tồn tại cho ngày câu trả lời đổi chiều.

## Trên platform này (dạng pilot)

Metrics của app trong homelab giờ đến bằng **OTLP push** (`obsx SDK →
otel-collector → vmagent OTLP ingest → VMSingle`; scrape `/metrics` per-app đã
được gỡ ở RFC-0014 P3). Streaming aggregation nằm trên đường remote-write của
vmagent nên áp dụng bất kể sample vào bằng cách nào. VM Operator expose nó
declarative trên `VMAgent` CR, nên pilot là một thay đổi GitOps-only trong
[`vmagent.yaml`](../../../kubernetes/infra/configs/monitoring/victoriametrics/vmagent.yaml)
— không component mới, không tầng router (1 vmagent = 1 aggregator = các bất
biến sharding tự thoả). YAML pilot đầy đủ (1 rule histogram RED trên
`http_server_request_duration_seconds` — chọn theo `app!=""`, `without
[k8s_pod_name]`, outputs `[total]`; SHADOW mode — không `dropInput`, không
`keep_metric_names`; rule gauge in-flight đã bỏ vì otelgin v0.69 không phát
`requests_in_flight`) xem
[bản English](streaming-aggregation.md#how-it-works-in-this-platform-pilot-shape).
Output có cùng hình dạng với recording rules `app:*` — chủ đích: giai đoạn
shadow so hai bên trước khi cutover bất kỳ consumer nào (RFC-0013 P3b).

## Vận hành

**Bật/tắt**: thêm/revert `streamAggrConfig` trong VMAgent CR → `make flux-push
&& make flux-sync`. Shadow mode không đụng raw series nên rollback zero blast
radius.

**Theo dõi chính aggregator** qua self-metrics của vmagent:
`vm_streamaggr_matched_samples_total` (bằng 0 = rule không match gì),
`vm_streamaggr_flushed_samples_total` (gap = mất window),
`vm_streamaggr_ignored_samples_total{reason="too_old"}` (tăng = pipeline lag),
`vm_streamaggr_dedup_dropped_samples_total`, `vm_streamaggr_samples_lag_seconds`
(giữ p99 ≪ interval).

**Checklist bẫy**: `sum_samples` trên counter · histogram lệch `without` ·
shard theo `le` · LB trước aggregator · restart mất window
(`flush_on_shutdown` cho graceful) · `keep_metric_names` trong shadow ·
`dedup.minScrapeInterval` (storage) lệch `dedup_interval` (aggregation) ·
`match` catch-all ăn RAM.

## Tham khảo

- VictoriaMetrics — [Streaming aggregation](https://docs.victoriametrics.com/victoriametrics/stream-aggregation/)
- VictoriaMetrics — [vmagent](https://docs.victoriametrics.com/victoriametrics/vmagent/)
- VictoriaMetrics Operator — [API: `StreamAggrConfig` / `StreamAggrRule`](https://docs.victoriametrics.com/operator/api/)
- Trong repo: [metrics hub](README.md) · [metrics-apps.md](metrics-apps.md) · [RFC-0013](../../proposals/rfc/RFC-0013/README.md)

---
_Last updated: 2026-07-09 — re-point pilot sang tên metric semconv/OTLP (RFC-0014 P3); đường app là OTLP push, không phải scrape._
