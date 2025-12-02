# Grafana Annotations - Đánh dấu sự kiện trên Dashboard

> **Status:** Plan - Chưa triển khai  
> **Reference:** [Leverage Grafana annotations - 0xdc.me](https://0xdc.me/blog/leverage-grafana-annotations/)  
> **Created:** 2025-01-19

## Tổng quan

Triển khai Grafana Annotations để track các events quan trọng:
- **Deployments** - Khi deploy phiên bản mới
- **k6 Load Tests** - Khi chạy load test
- **Incidents** - Khi xảy ra sự cố
- **Config Changes** - Khi thay đổi config
- **Manual Interventions** - Khi can thiệp thủ công

## Grafana Annotations là gì?

> Annotations cho phép đánh dấu các điểm trên graph với thông tin chi tiết về sự kiện. Chúng được hiển thị dưới dạng đường thẳng đứng và icons trên tất cả graph panels.

**Lợi ích:**
- Correlate dữ liệu graph với các sự kiện quan trọng
- Theo dõi deployments và thấy impact lên metrics
- Đánh dấu incidents và quá trình giải quyết
- Team collaboration - mọi người thấy chuyện gì đã xảy ra và khi nào
- Troubleshoot nhanh hơn

## 3 loại Annotations

### 1. Simple Annotations (Điểm thời gian)
- Một timestamp duy nhất
- Đánh dấu sự kiện cụ thể (deployment hoàn tất, incident bắt đầu)
- Hiển thị: Đường thẳng đứng trên graphs

### 2. Region Annotations (Khoảng thời gian)
- Có timestamp bắt đầu và kết thúc
- Đánh dấu sự kiện kéo dài (load test đang chạy, incident resolution)
- Hiển thị: Vùng được tô màu trên graphs

### 3. Logs-based Annotations
- Pull annotations từ Loki logs
- Query: `{job="grafana-annotations"}`
- Tự động từ log streams

---

## Kế hoạch triển khai

### Phase 1: Bật Built-in Annotations

**Cấu hình trong grafana-dashboard.json:**

```json
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": {"type": "grafana", "uid": "-- Grafana --"},
        "enable": true,
        "hide": false,
        "name": "Annotations & Alerts"
      }
    ]
  }
}
```

**Action:**
- Enable built-in annotations
- Show trên tất cả panels
- Màu xanh dương mặc định

### Phase 2: Thêm Custom Annotations theo Tags

**3 loại tags chính:**

#### 1. Deployments (Màu xanh #5c4ee5)
- Tag: `deployment`
- Dùng khi: Deploy version mới
- Example: "Deployed auth v2.1.0 to production"

#### 2. k6 Load Tests (Màu cam #ff6b6b)
- Tag: `k6-loadtest`
- Dùng khi: Chạy load test
- Example: "k6 load test: continuous - VUs: 300-500"

#### 3. Incidents (Màu đỏ #ff0000)
- Tag: `incident`
- Dùng khi: Xảy ra sự cố
- Example: "Incident: High Error Rate - Severity: SEV1"

**Thêm vào grafana-dashboard.json:**

```json
{
  "annotations": {
    "list": [
      {
        "datasource": {"type": "datasource", "uid": "grafana"},
        "enable": true,
        "hide": false,
        "iconColor": "#5c4ee5",
        "name": "Deployments",
        "target": {
          "limit": 100,
          "matchAny": false,
          "tags": ["deployment"],
          "type": "tags"
        }
      },
      {
        "datasource": {"type": "datasource", "uid": "grafana"},
        "enable": true,
        "hide": false,
        "iconColor": "#ff6b6b",
        "name": "k6 Load Tests",
        "target": {
          "limit": 100,
          "matchAny": false,
          "tags": ["k6-loadtest"],
          "type": "tags"
        }
      },
      {
        "datasource": {"type": "datasource", "uid": "grafana"},
        "enable": true,
        "hide": false,
        "iconColor": "#ff0000",
        "name": "Incidents",
        "target": {
          "limit": 100,
          "matchAny": false,
          "tags": ["incident"],
          "type": "tags"
        }
      }
    ]
  }
}
```

### Phase 3: Tạo Scripts gửi Annotations

#### Script 1: Đánh dấu Deployment

**File:** `scripts/send-deployment-annotation.sh`

**Công dụng:**
- Gửi annotation khi deploy xong
- Point annotation (đường thẳng đứng)
- Màu xanh

```bash
#!/bin/bash
# Gửi annotation khi deploy

GRAFANA_URL="http://localhost:3000"
GRAFANA_TOKEN="${GRAFANA_TOKEN}"  # Cần setup trước

curl -X POST "${GRAFANA_URL}/api/annotations" \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"time\": $(date +%s%3N),
    \"tags\": [\"deployment\"],
    \"text\": \"Deployed ${APP_NAME} version ${VERSION} to ${ENV}\"
  }"
```

#### Script 2: Đánh dấu k6 Load Test

**File:** `scripts/send-k6-annotation.sh`

**Công dụng:**
- Gửi annotation sau khi k6 test xong
- Region annotation (vùng tô màu)
- Màu cam

```bash
#!/bin/bash
# Gửi annotation cho k6 load test

GRAFANA_URL="http://localhost:3000"
GRAFANA_TOKEN="${GRAFANA_TOKEN}"

START_TIME=$(date +%s%3N -d "60 minutes ago")  # Test chạy 60 phút
END_TIME=$(date +%s%3N)

curl -X POST "${GRAFANA_URL}/api/annotations" \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"time\": ${START_TIME},
    \"timeEnd\": ${END_TIME},
    \"tags\": [\"k6-loadtest\"],
    \"text\": \"k6 load test: VUs ${K6_VUS}, Duration 60m\",
    \"isRegion\": true
  }"
```

#### Script 3: Đánh dấu Incident

**File:** `scripts/send-incident-annotation.sh`

**Công dụng:**
- Gửi annotation khi xảy ra incident
- Region annotation (từ lúc bắt đầu đến lúc resolve)
- Màu đỏ

```bash
#!/bin/bash
# Gửi annotation khi có incident

GRAFANA_URL="http://localhost:3000"
GRAFANA_TOKEN="${GRAFANA_TOKEN}"

START_TIME="${INCIDENT_START}"  # Unix timestamp ms
END_TIME=$(date +%s%3N)

curl -X POST "${GRAFANA_URL}/api/annotations" \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"time\": ${START_TIME},
    \"timeEnd\": ${END_TIME},
    \"tags\": [\"incident\"],
    \"text\": \"Incident: ${INCIDENT_NAME} - Severity: ${SEVERITY}\",
    \"isRegion\": true
  }"
```

### Phase 4: Tích hợp vào Workflows

#### 1. Deployment Workflow

```bash
# Deploy version mới
kubectl apply -f k8s/deployment-v2.yaml

# Gửi annotation
export APP_NAME="auth"
export VERSION="v2.1.0"
export ENV="production"
./scripts/send-deployment-annotation.sh

# → Dashboard sẽ hiện đường thẳng đứng màu xanh tại thời điểm deploy
```

#### 2. k6 Load Test Workflow

```bash
# Chạy k6 test
kubectl apply -f k8s/k6/deployment.yaml

# Đợi test chạy xong (60 phút)

# Gửi annotation
export K6_VUS="300-500"
./scripts/send-k6-annotation.sh

# → Dashboard sẽ hiện vùng màu cam trong 60 phút test
```

#### 3. Incident Response Workflow

```bash
# Phát hiện incident lúc 09:30
export INCIDENT_START=$(date +%s%3N -d "09:30")
export INCIDENT_NAME="High Error Rate"
export SEVERITY="SEV1"

# Resolve incident lúc 10:15, gửi annotation
./scripts/send-incident-annotation.sh

# → Dashboard sẽ hiện vùng màu đỏ từ 09:30 đến 10:15
```

### Phase 5: Tạo Documentation

**File mới:** `docs/GRAFANA_ANNOTATIONS.md`

**Nội dung:**
1. Giới thiệu Grafana Annotations
2. Cách xem annotations trên dashboard
3. Cách gửi annotations thủ công
4. Ví dụ sử dụng scripts
5. Best practices
6. Troubleshooting

---

## Use Cases thực tế

### Use Case 1: "Deployment có làm tăng error rate không?"

**Scenario:**
- Deploy auth service lúc 10:00
- Muốn xem có ảnh hưởng gì không

**Workflow:**
```bash
# 1. Deploy
kubectl apply -f k8s/deployment-v2.yaml

# 2. Đánh dấu
./scripts/send-deployment-annotation.sh

# 3. Mở dashboard
# - Thấy đường thẳng đứng màu xanh tại 10:00
# - Check RPS: Có tăng không?
# - Check Error Rate %: Có tăng không?
# - Check Response Time: Có chậm hơn không?
```

**Kết quả:** Biết ngay deployment có impact gì lên hệ thống

### Use Case 2: "k6 test có làm hệ thống chậm không?"

**Scenario:**
- Chạy k6 stress test với 500 VUs
- Muốn xem system handle thế nào

**Workflow:**
```bash
# 1. Chạy test
kubectl apply -f k8s/k6/deployment.yaml

# 2. Đợi test xong, đánh dấu
./scripts/send-k6-annotation.sh

# 3. Mở dashboard
# - Thấy vùng màu cam (test duration)
# - Check RPS trong vùng cam: Tăng bao nhiêu?
# - Check Response Time p95: Có tăng không?
# - Check CPU/Memory: Có đủ resources không?
```

**Kết quả:** Hiểu được system capacity và bottlenecks

### Use Case 3: "Incident do deploy hay do load?"

**Scenario:**
- Error rate tăng đột ngột lúc 10:30
- Cần tìm nguyên nhân

**Workflow:**
```bash
# 1. Mở dashboard, zoom vào 10:30
# 2. Thấy các annotations:
#    - Deployment annotation lúc 10:00 (xanh)
#    - k6 test annotation 10:15-10:45 (cam)
#    - Error spike lúc 10:30

# 3. Phân tích:
#    - Deploy ok (10:00), không có error ngay lập tức
#    - k6 test bắt đầu 10:15
#    - Error tăng 10:30 (trong k6 test)
#    → Nguyên nhân: System không handle được load

# 4. Đánh dấu incident
export INCIDENT_START=$(date +%s%3N -d "10:30")
./scripts/send-incident-annotation.sh
```

**Kết quả:** Tìm được root cause nhanh chóng

---

## Prerequisites (Chuẩn bị)

### 1. Tạo Grafana Service Account

**Bước 1:** Truy cập Grafana
```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Mở: http://localhost:3000
```

**Bước 2:** Tạo Service Account
- Vào: `http://localhost:3000/org/serviceaccounts`
- Click `Add service account`
- Name: `annotations_sa`
- Role: `Editor`

**Bước 3:** Generate Token
- Click `Add service account token`
- Click `Generate token`
- Copy token (ví dụ: `glsa_OlX64rUBFgWD0FpwyuZDtvgBGjqWNQQk_aed22945`)

**Bước 4:** Lưu token
```bash
export GRAFANA_TOKEN="glsa_OlX64rUBFgWD0FpwyuZDtvgBGjqWNQQk_aed22945"
# Hoặc lưu vào .env file
echo "GRAFANA_TOKEN=glsa_..." >> .env
```

### 2. Test API Connection

```bash
# Test xem token có work không
curl -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  http://localhost:3000/api/org
  
# Nếu thành công, sẽ thấy response JSON
```

---

## Lợi ích cho Project này

### 1. Deployment Tracking
- Thấy ngay impact của mỗi deployment
- Correlate version changes với performance
- Quyết định rollback nhanh

### 2. Load Test Correlation
- Hiểu được metrics thay đổi thế nào khi chạy k6
- Validate system capacity
- Identify bottlenecks

### 3. Incident Response
- Đánh dấu incident start/end
- Thấy được gì đã thay đổi trước incident
- Document resolution timeline

### 4. Team Collaboration
- Mọi người thấy cùng events
- Không cần hỏi "chuyện gì xảy ra lúc 10am?"
- Shared context cho troubleshooting

---

## Color Coding (Mã màu)

| Loại Event | Màu | Ví dụ |
|------------|-----|-------|
| Deployment | Xanh (#5c4ee5) | Deploy version mới |
| k6 Load Test | Cam (#ff6b6b) | Chạy load test |
| Incident | Đỏ (#ff0000) | Sự cố production |
| Config Change | Tím (#9c27b0) | Update Prometheus config |
| Manual Action | Vàng (#ffd700) | Scale thủ công |

---

## Ví dụ Workflow hoàn chỉnh

### Scenario: Deploy rồi test

```bash
# Bước 1: Deploy version mới
kubectl apply -f k8s/deployment-v2.yaml
echo "✓ Deployed"

# Bước 2: Đánh dấu deployment
export APP_NAME="auth"
export VERSION="v2.1.0"
export ENV="dev"
./scripts/send-deployment-annotation.sh
echo "✓ Deployment annotation sent"

# Bước 3: Đợi 5 phút, check dashboard
sleep 300
echo "→ Check dashboard: Có deployment annotation màu xanh"
echo "→ Check metrics: RPS, Error Rate, Latency có thay đổi?"

# Bước 4: Nếu ok, chạy load test
kubectl apply -f k8s/k6/deployment.yaml
echo "✓ k6 test started"

# Bước 5: Đợi test xong (60 phút)
sleep 3600

# Bước 6: Đánh dấu k6 test
export K6_VUS="300-500"
./scripts/send-k6-annotation.sh
echo "✓ k6 annotation sent"

# Bước 7: Review dashboard
echo "→ Thấy 2 annotations:"
echo "  - Deployment (xanh) lúc 10:00"
echo "  - k6 test (cam) 10:05-11:05"
echo "→ Correlate với RPS, latency, error rate"
echo "→ Kết luận: System ok hay cần optimize?"
```

---

## Implementation Checklist

### Dashboard Configuration
- [ ] Enable built-in annotations
- [ ] Add "Deployments" annotation (tag: deployment, màu xanh)
- [ ] Add "k6 Load Tests" annotation (tag: k6-loadtest, màu cam)
- [ ] Add "Incidents" annotation (tag: incident, màu đỏ)

### Scripts
- [ ] Create `scripts/send-deployment-annotation.sh`
- [ ] Create `scripts/send-k6-annotation.sh`
- [ ] Create `scripts/send-incident-annotation.sh`
- [ ] Make scripts executable: `chmod +x scripts/*.sh`

### Setup
- [ ] Create Grafana service account
- [ ] Generate và lưu GRAFANA_TOKEN
- [ ] Test annotation scripts

### Documentation
- [ ] Create `docs/GRAFANA_ANNOTATIONS.md`
- [ ] Add examples và use cases
- [ ] Update README.md với link

### Testing
- [ ] Test deployment annotation
- [ ] Test k6 annotation (region)
- [ ] Test incident annotation (region)
- [ ] Verify hiển thị trên dashboard

---

## Future Enhancements (Tương lai)

### 1. Loki-based Annotations
- Stream annotations vào Loki
- Query từ Loki: `{job="grafana-annotations"}`
- Persistent annotation history

### 2. Automated Annotations
- GitHub Actions: Auto annotate khi merge PR
- ArgoCD: Auto annotate khi sync
- Prometheus AlertManager: Auto annotate khi có alert

### 3. Annotation Dashboard
- Panel riêng show tất cả annotations
- Filter by tag
- Search by text

---

## Tài liệu tham khảo

- [Leverage Grafana annotations - 0xdc.me](https://0xdc.me/blog/leverage-grafana-annotations/)
- [Grafana Annotations Docs](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/annotate-visualizations/)
- [Grafana HTTP API - Annotations](https://grafana.com/docs/grafana/latest/developers/http_api/annotations/)

