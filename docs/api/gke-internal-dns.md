# GKE internal DNS on GCP (`cluster.local`, Cloud DNS private zones, multi-environment)

> **Purpose:** Complements the **internal / in-cluster** section in [`api-naming-convention.md`](api-naming-convention.md) — explains Kubernetes default DNS, Cloud DNS **private zones**, and naming split by environment (`dev` / `uat` / `prod`).

---

## 1. Default internal DNS in GKE

### 1.1 What is `cluster.local`?

- It is Kubernetes’ **default domain** for in-cluster **Service discovery**.
- It is **not** a domain you register at a registrar; it only applies **inside** the cluster (and on nodes when resolving via CoreDNS/kube-dns).

### 1.2 Standard FQDN shape

A Kubernetes Service has a full DNS name (FQDN) of the form:

```text
<service-name>.<namespace>.svc.cluster.local
```

**Examples** (aligned with [`api-naming-convention.md`](api-naming-convention.md)):

| Service | Namespace | FQDN |
|---------|-----------|------|
| `notification` | `notification` | `notification.notification.svc.cluster.local` |
| `product` | `product` | `product.product.svc.cluster.local` |

**Short forms (same cluster):**

- Same namespace: you can use `http://notification:8080` (Service name only).
- Different namespace: `http://notification.notification.svc` or the full `...svc.cluster.local`.

### 1.3 How CoreDNS works

- On modern GKE, **CoreDNS** (usually in `kube-system`) is the **DNS server** Pods use via the `kube-dns` Service `ClusterIP`.
- Inside a Pod, `/etc/resolv.conf` points there; **search domains** typically include `namespace.svc.cluster.local`, `svc.cluster.local`, `cluster.local` — so short names work within the correct namespace.
- CoreDNS’s **`kubernetes` plugin** answers queries for `*.svc.cluster.local` using the **API Server** (Services/Endpoints).
- Queries **leaving** the cluster (internet, `google.com`, …) are usually **forwarded** to the node/VPC upstream resolver (depending on `forward` / `proxy` in the `Corefile`).

**Summary:** `*.svc.cluster.local` is **owned by Kubernetes + CoreDNS**; you do **not** need Cloud DNS to “create” these names.

---

## 2. Cloud DNS — private zones on GCP

### 2.1 How is this different from `cluster.local`?

- **`cluster.local`:** cluster-only, served by CoreDNS.
- **Cloud DNS private zone:** you create a **private DNS zone** (e.g. `gke.internal.` or `svc.gke.prod.`) **attached to a VPC**; only resources in (or correctly peered with) that **VPC** can resolve it — **not** the public Internet.

### 2.2 Attaching a zone to a VPC

1. Create a **managed zone** with `visibility=private`.
2. Attach **VPC network(s)** to the zone (private visibility config).
3. Add **records** (A, CNAME, …) pointing to internal IPs (ClusterIP, ILB, VM, …).

Then **VMs / Pods** (if Pod DNS correctly forwards to the VPC resolver or you configure CoreDNS **stub/forward** for that zone) can resolve `notification.prod.gke.internal` instead of only `*.svc.cluster.local`.

**Note:** If Pods **only** need `svc.cluster.local`, Cloud DNS is **not** required — private Cloud DNS helps when you want **stable names per environment / org standard** or names that **point outside** the cluster abstraction (ILB, PSC, …).

### 2.3 GKE “DNS options” (reference)

Google documents DNS options for GKE (kube-dns / CoreDNS / Cloud DNS integration). With **Cloud DNS for GKE** (availability varies by time/region), resolution may combine **managed zones** scoped to cluster/VPC — see current docs: [Understanding DNS options for GKE](https://cloud.google.com/blog/products/networking/understanding-dns-options-for-gke) and [Troubleshoot Cloud DNS in GKE](https://cloud.google.com/kubernetes-engine/docs/troubleshooting/cloud-dns).

---

## 3. Multi-environment (`dev` / `uat` / `prod`)

### 3.1 Common patterns

| Approach | Idea | Notes |
|----------|------|--------|
| **Separate clusters** | One GKE cluster (or project) per env | Separate `cluster.local` namespaces naturally; clearer security boundaries. |
| **Separate namespaces** | One cluster; `dev` / `uat` / `prod` as namespaces | Different FQDNs: `svc.dev.svc.cluster.local` vs `svc.prod.svc.cluster.local`. |
| **Per-env private DNS** | Cloud DNS: `*.dev.gke.internal`, `*.prod.gke.internal` | Records point to the right ILB/ClusterIP; may need CoreDNS forward or clients using full FQDNs. |

### 3.2 Naming suggestions (non-binding)

- **By suffix:** `api.notification.dev.internal`, `api.notification.prod.internal` (private zone `internal` or `gke.company.com`).
- **By subdomain:** `dev.gke.company.local` (private) — avoid conflating with `cluster.local` (keep “local” semantics clear in runbooks).

**Best practice:** One **naming standard** for app config (URL base) + **one** source of truth (Helm values / ConfigMap) + **IAM/NetworkPolicy** separation per environment.

---

## 4. Hands-on configuration (`gcloud` & Terraform)

### 4.1 Create a private zone with `gcloud`

```bash
# Replace PROJECT_ID, VPC_NAME, ZONE_NAME as needed
gcloud dns managed-zones create "${ZONE_NAME}" \
  --project="${PROJECT_ID}" \
  --description="Private DNS for GKE internal services" \
  --dns-name="gke.internal." \
  --visibility=private \
  --networks="https://www.googleapis.com/compute/v1/projects/${PROJECT_ID}/global/networks/${VPC_NAME}"
```

Add a record (example pointing to an **internal load balancer** or static IP):

```bash
gcloud dns record-sets create notification.prod.gke.internal. \
  --zone="${ZONE_NAME}" \
  --type=A \
  --ttl=300 \
  --rrdatas="10.0.0.50"
```

*(Illustrative IP — replace with your ILB/endpoint IP in the VPC.)*

### 4.2 Terraform (minimal)

```hcl
resource "google_dns_managed_zone" "gke_private" {
  name        = "gke-internal"
  dns_name    = "gke.internal."
  visibility  = "private"
  description = "Private DNS for GKE workloads"

  private_visibility_config {
    networks {
      network_url = var.vpc_id
    }
  }
}

resource "google_dns_record_set" "notification_prod" {
  name         = "notification.prod.gke.internal."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.gke_private.name
  rrdatas      = [var.notification_ilb_ip]
}
```

### 4.3 CoreDNS: forward to Cloud DNS (when needed)

If Pods must resolve `*.gke.internal` via VPC **Cloud DNS**, configure **CoreDNS** (the `coredns` ConfigMap in `kube-system`): add **stub** / **forward** for the `gke.internal` suffix to the appropriate **DNS endpoint** (VPC internal resolver — see Google’s docs for addresses and GKE version constraints).

**Warning:** A bad CoreDNS change can **break DNS for the entire cluster** — test on a dev cluster and keep a backup of the `Corefile`.

---

## 5. Quick links

| Document | URL |
|----------|-----|
| Cloud DNS — private zones | [Cloud DNS private zones](https://cloud.google.com/dns/docs/zones#create-private-zones) |
| Scopes & hierarchy | [Scopes and hierarchies](https://cloud.google.com/dns/docs/scopes) |
| GKE — DNS / troubleshooting | [Troubleshoot Cloud DNS in GKE](https://cloud.google.com/kubernetes-engine/docs/troubleshooting/cloud-dns) |
| Kubernetes — DNS for Services | [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) |

---

## 6. Relation to HTTP examples in `api-naming-convention`

URLs such as:

```http
POST http://notification.notification.svc.cluster.local:8080/api/v1/notify/email
```

follow the **default Kubernetes DNS model** — Cloud DNS is not required.

If you want names like `notification.prod.gke.internal`, use a **private zone + records** (section 4) and, if needed, **CoreDNS forward** (section 4.3).
