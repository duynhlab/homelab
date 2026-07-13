# RFC-0010: payment-service — bản tóm tắt tiếng Việt

> File local để đọc nhanh, KHÔNG push (repo docs English-only). Bản đầy đủ:
> [README.md](README.md). Cập nhật: 2026-07-03.

## Vì sao cần

Checkout hiện tại xác nhận order mà **chưa từng thu tiền**. Payment-service lấp
lỗ hổng đó và là nơi học các bài khó nhất của distributed systems: idempotency
thật, state machine có tiền, ledger audit, webhook async, reconciliation.

## Kiến trúc 1 dòng

SPA/saga → **payment-service** (REST :8080 + gRPC :9090) → **mockpay** (binary
riêng, giả lập Stripe) → webhook HMAC bắn ngược về → ledger + reconciliation
trong Postgres (cnpg-db).

## API chính

| Method | Route | Ai gọi | Ghi chú |
|--------|-------|--------|---------|
| POST | `/payment/v1/private/payments` | Browser (P1–P2) | Tạo intent — **bắt buộc header `Idempotency-Key`**; từ P3 checkout do saga tạo, gọi trùng order → `409 PAYMENT_EXISTS` |
| GET | `/payment/v1/private/payments[/{id}]` | Browser | Xem 1 / danh sách (phân trang chuẩn) |
| POST | `/payment/v1/internal/payments/{id}/refunds` | Saga / operator | Refund (partial được, idempotency key riêng) — user KHÔNG tự refund |
| POST | `/payment/v1/public/webhooks/mockpay` | mockpay | Verify HMAC in-app, dedup theo event_id |
| gRPC | `Authorize / Capture / Void / Refund` | order saga | idempotent theo `order_id` / `refund:{order_id}` |

## State machine (nhớ 5 ý)

1. `pending → authorized (hold, hết hạn 7d) → captured`; decline → `failed`
2. **Void** (hủy hold, chưa mất tiền) ≠ **Refund** (trả tiền đã capture)
3. Transition = whitelist `map[Status][]Status` **+ CAS ở DB** (`UPDATE … WHERE status=$expected`) chống race
4. `partially_refunded` KHÔNG lưu — **derive** từ `SUM(refunds)` so với amount
5. Tiền = **int64 minor units** (2000 = $20.00), không bao giờ float

## Idempotency (bài học số 1)

- Claim key bằng `INSERT … ON CONFLICT DO NOTHING` (unique index = lock)
- Trùng key + body khác → `409 IDEMPOTENCY_CONFLICT`; thiếu header → `400`
- **Recovery points** (`started → provider_called → finished`): provider call
  nằm NGOÀI transaction — an toàn nhờ truyền cùng key xuống mockpay + takeover
  lock cũ >90s. Ledger + outbox + hoàn tất key = 1 transaction cuối.

## Ledger + outbox

- Double-entry: mỗi giao dịch ghi cặp debit/credit **cân bằng**, append-only
  (không UPDATE/DELETE — sửa sai = entry đảo chiều mới)
- Outbox: đổi state + ghi ledger + phát event trong **cùng 1 DB txn**

## mockpay dạy gì

- Webhook ký HMAC (`t=…,v1=…`, raw body, lệch >5m từ chối), **cố tình gửi
  trùng + đảo thứ tự** → consumer phải dedup + chịu out-of-order
- Magic amounts: đuôi `…02` decline, `…95` insufficient, `…19` lỗi-rồi-ok;
  thêm `MOCKPAY_FAIL_RATE` chaos toggle
- Seed sẵn 4 loại lệch để reconciliation job có bài tập

## Saga v2 (sau P3)

```
Authorize → ReserveStock → CreateShipment → Capture → ConfirmOrder(pivot)
  fail trước Capture  → Void + ReleaseStock (+CancelShipment) + FailOrder
  fail sau Capture    → Refund + CancelShipment + ReleaseStock + FailOrder
```
Bật/tắt bằng `PAYMENT_ENABLED` trong order-service (default off = flow cũ) —
flag đọc 1 lần lúc start workflow (Temporal determinism). **Flag là giàn giáo:
sau khi bake ổn (~2 tuần SLO xanh + recon sạch) PHẢI có cleanup PR xóa flag +
2 nhánh if** — điều kiện đóng P3, đừng quên.

## Phases

| Phase | Nội dung | Repo |
|-------|----------|------|
| P1 | Scaffold + REST API + state machine + idempotency | payment-service, pkg |
| P2 | mockpay + webhook + ledger + outbox → **ADR ledger** | payment-service |
| P3 | Proto gRPC + saga rewire + minor-units + pkg/idempotency → **2 ADR** | pkg, order, shipping, homelab |
| P4 | Reconciliation + fault injection + e2e local-stack | payment-service, local-stack |
| P5 | GitOps cluster (DB, secrets ×2, NetworkPolicy, Kong, Kyverno ×3) | homelab |
| P6 | Frontend minimal | frontend |

## Rủi ro cần nhớ

- gRPC :9090 **chưa có mTLS/auth** (chờ RFC-0002) — chặn bằng NetworkPolicy
  (chỉ ns `order` được gọi)
- `422 PAYMENT_DECLINED` là status **mới** cho platform (cố ý)
- Order total đang `float64` → P3 refactor sang minor units
