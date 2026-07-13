# RFC-0015: checkout-service — bản tóm tắt tiếng Việt

> File local để đọc nhanh, KHÔNG push (repo docs English-only). Bản đầy đủ +
> diagram: [README.md](README.md) (trên PR #494 / branch
> `docs/rfc-0015-checkout-service` cho tới khi merge). Cập nhật: 2026-07-12.

| Status | Scope | Created |
|--------|-------|---------|
| provisional | platform-wide | 2026-07-11 |

## Vì sao cần

"Checkout" hiện tại chỉ là một cú `POST /orders`: SPA bắn thẳng vào order,
order đọc giá từ cart (giá **denormalize từ lúc add-to-cart** — có thể đã cũ
nhiều ngày), insert `pending`, start saga, SPA poll. Thiếu hẳn tầng phễu mua
hàng thật: không session, không re-validate giá, shipping fee hardcode $5
trong cart, không tax, không promo, idempotency ở order chỉ là header
*optional*. Checkout-service lấp mảnh cuối đó và là nơi học: **session FSM,
re-validation, durable idempotency lần 2, Temporal timer/Signal/Query, và mọc
gRPC surface cho service đang chạy**.

## Kiến trúc 1 dòng

Checkout là **session/UX orchestrator đứng TRƯỚC order** — own bảng
`checkout_sessions` (ephemeral, TTL 30 phút), còn order vẫn là **single
writer của `orders` và người duy nhất start saga**; confirm = checkout gọi
gRPC `order.v1/CreateOrder`, saga `OrderFulfillmentWorkflow` không đổi một
dòng.

## Quyết định boundary (ADR-018 tương lai — quan trọng nhất)

- Checkout **không** ghi bảng orders, **không** start saga, **không** wrap
  saga bằng workflow cha. 3 phương án kia bị loại vì: blur ownership, phá
  contract 201-pending-poll, hoặc race (saga cần row `pending` tồn tại trước
  StartWorkflow mà checkout không insert được vào DB của order).
- Transport: **gRPC, không REST forward-JWT** — user chốt "làm như công ty
  thật", chấp nhận refactor: order và cart **mọc gRPC server mới**.

## 4 cạnh gRPC mới (convention east-west 100%)

| Cạnh | RPC | Ghi chú |
|------|-----|---------|
| checkout→cart | `cart.v1/GetCart` | cart lần đầu có gRPC server; read-only (ClearCart của saga vẫn REST internal) |
| checkout→product | `product.v1/GetProducts` (batch) | giá + available_qty; server có sẵn |
| checkout→shipping | `shipping.v1/GetQuote` | fee + ETA theo method/region — khai tử hardcode $5 |
| checkout→order | `order.v1/CreateOrder` | order lần đầu có gRPC server; `idempotency_key` là field bắt buộc |

gRPC không mang JWT (như mọi cạnh east-west hiện có): `user_id` explicit +
NetworkPolicy fence; mTLS vẫn là việc của RFC-0002.

## Session FSM (nhớ 6 ý)

1. `open → address_set → shipping_set → ready → confirming → completed`;
   terminal: `expired`, `cancelled`. Không có state `abandoned` riêng —
   abandoned = `expired` + cột `reason` (`timer` | `lazy`).
2. **1 session active/user** — `POST /sessions` idempotent (partial unique
   index trên `user_id`), khớp mô hình 1-cart-per-user.
3. Transition table enforce ở **logic layer** (giống payment state machine);
   sai transition → `INVALID_TRANSITION` có sẵn trong httpx.
4. `PRICE_CHANGED` lúc confirm → rơi về `shipping_set` (totals phải tính
   lại), SPA hiện diff giá — không bao giờ charge giá user chưa nhìn thấy.
5. TTL 30 phút, **reset mỗi mutation** (Signal) — clock đo "user còn đang
   điền form", không phải giữ chỗ (vì không reserve gì cả).
6. Route: `/checkout/v1/private/checkout/sessions[...]` — create, get, PUT
   address/shipping/payment, POST promo, POST confirm, DELETE. Checkout,
   giống auth, là service dạng process — segment sở hữu là chữ `checkout`
   literal, resource (`sessions`) nested bên dưới (rule v3.0.1).

## Re-validation (ADR-020 tương lai)

- **Authority shift**: cart = *item-list* authority; **product = price
  authority tại thời điểm checkout**. Snapshot lấy items từ cart nhưng giá từ
  `GetProducts`, khoá vào `unit_price_minor` (int64 minor units).
- Validate 2 lần: lúc create (UX trung thực) + lúc confirm (thời điểm tiền).
- **Stock chỉ CHECK, không reserve.** Reservation vẫn độc quyền của saga
  (`ReserveStock`, RFC-0003). TOCTOU giữa check và reserve là tradeoff **được
  gọi tên và chấp nhận**: check = fail-fast UX, saga = chốt chặn đúng, đã có
  compensation sẵn. Soft-reserve từ checkout = 2 writer trên cùng ledger →
  loại.

## Confirm path (bài học idempotency lần 2)

- `POST .../confirm` bắt buộc `Idempotency-Key`, dùng **`pkg/idempotency`**
  (brandur recovery-points, ADR-010) — consumer thứ 2 sau payment, validate
  claim "shared library" của ADR đó.
- Key sang order **derive từ session_id** (deterministic) → retry an toàn
  xuyên 2 service; double-click không bao giờ ra 2 order, promo không bị đốt
  2 lần.
- Đường gRPC bỏ bước order-đọc-lại-cart (checkout đã re-validate với product
  — check mạnh hơn); đường REST cũ giữ nguyên validation tới P6.

## AbandonedCheckoutWorkflow (Temporal mới học được gì)

- 1 workflow / session, ID `checkout-session-<id>`, task queue `checkout`,
  worker = subcommand `worker` của checkout image (pattern order-worker).
- Học đủ bộ: **durable timer** (`workflow.NewTimer` trong Selector loop),
  **Signal** (`activity` reset clock, `finalize` kết thúc), **Query handler**
  (soi state qua Temporal UI), **Signal-With-Start** (create idempotent).
- **Lazy-expiry backstop là bài học production**: logic layer luôn check
  `now > expires_at` trên mọi read/write — worker chết thì expiry chỉ được
  *ghi nhận muộn*, không bao giờ có chuyện session hết hạn mà vẫn được dùng.
  Temporal là actor dọn dẹp, không phải source of truth về validity.
- Timer nổ muộn trên session đã completed = no-op (UPDATE conditional).

## Totals + promo

- `total = subtotal + shipping(GetQuote) + tax − discount`, toàn bộ int64
  minor units, persist trên session mỗi lần recompute (session = quote có
  audit).
- Tax: bảng rule flat-rate (`region → rate_bps`) trong checkout DB — bài học
  là *tax sống ở đâu và tính lúc nào*, không phải mô hình thuế.
- Promo: `promo_codes` + `promo_redemptions`; apply chỉ validate, **redemption
  đếm tại confirm** bằng `UPDATE ... WHERE redeemed_count < max` atomic —
  0 row = `PROMO_EXHAUSTED`; có race test (N goroutine, cap M, đúng M thắng).

## Những gì CỐ TÌNH không làm (đọc kỹ trước khi "thêm cho vui")

- **Kafka `order.created` / Debezium CDC** — platform chưa có broker; async =
  Temporal + outbox (payment). Eventing = RFC tương lai, confirm pivot là
  điểm publish tự nhiên sau này.
- **Payment confirm qua Signal + CancelOrderWorkflow** → **RFC-0016** (đòi
  mockpay async mode + đổi step Authorize đang shipped — quá nhiều biến).
- **Saga cha mới** — đã tồn tại: `OrderFulfillmentWorkflow`.
- Shipping child workflow + Continue-As-New (shipping là mock, chưa có
  driver thật), guest checkout, promo stacking/admin UI, đổi write-path cart.

## Phases

| P | Gì | Repo chạm |
|---|----|-----------|
| P1 | scaffold + DB triplet + sessions FSM + snapshot + cart `GetCart` + product `GetProducts` + local-stack (port 8010) | checkout-service (mới), pkg, cart, product, homelab |
| P2 | confirm (`pkg/idempotency` + order `CreateOrder`) + AbandonedCheckoutWorkflow + worker | checkout-service, pkg, order, homelab |
| P3 | shipping `GetQuote` + tax + totals + **SPA cutover (dual-entry)** | shipping, pkg, checkout, frontend |
| P4 | promo + race test | checkout-service |
| P5 | cluster GitOps: RSIP + triplet + netpol + Kong + **Kyverno ns lists** (bài học RFC-0010 P5) | homelab |
| P6 | deprecate SPA direct `POST /orders`, order bỏ cart re-check, docs sweep | order, frontend, homelab |

Rollback mọi lúc tới P5 = revert SPA; **không service nào dial vào checkout**
nên gỡ checkout không gãy gì. Không cần feature flag backend (không rewire
saga — khác `PAYMENT_ENABLED` của RFC-0010).

## Rủi ro cần nhớ

- TOCTOU stock (chấp nhận, saga chốt) · dual validation path P3–P5 (gRPC vs
  REST legacy) · order lần đầu mọc gRPC server (risk trung bình — reuse đúng
  code path REST) · thêm 1 service + worker + DB + idempotency store để vận
  hành · Temporal history per-session (bounded, còn xa Continue-As-New).
- Metric đáng canh: `expired{reason="lazy"}` chiếm đa số kéo dài = worker
  chết/kẹt; `PRICE_CHANGED` spike = product pricing churn hoặc bug; p95
  confirm (thêm 2 hop gRPC so với legacy).

## ADR sẽ spawn

ADR-018 boundary · ADR-019 expiry (timer + lazy backstop) · ADR-020
re-validation · ADR-021 cart gRPC read surface · ADR-022 promo atomicity.
(Dãy dời +1 ngày 2026-07-12: ADR-017 đã bị quyết định api-path-collection-noun
của platform chiếm.)
