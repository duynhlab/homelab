# Telemetry implementation audit

**Audit date:** 2026-10-23. **Method:** static code/configuration review, existing unit tests, and isolated synthetic reproductions. **Runtime verification:** not performed. This is an evidence record and a proposal for follow-up work, not a new normative contract.

The architecture is sound: shared instrumentation, OTLP transport, independent application RED metrics, a central Collector, source-level log redaction, and registry/CI controls are all present. These choices follow established large-platform principles. The remaining weaknesses are in behavior and enforcement: failed business spans can appear successful, trace error text bypasses the log privacy boundary, and a checkout retry can double-count a completed session. Passing the existing tests and importing the shared packages do not establish compliance with those properties.

There is already a shared implementation contract in [Application observability](../../api/observability.md). The documentation problem is discoverability and drift between normative rules, historical evidence, and current implementation. Creating a second policy owner would make that worse; the proposed authoring guide below should link the existing rules.

## Bảng tổng hợp tiếng Việt

Bảng này được bổ sung theo yêu cầu của chủ repo. **P1:** cần ưu tiên sửa vì ảnh hưởng tính đúng đắn hoặc an toàn dữ liệu telemetry; **P2:** sửa tiếp hoặc hoàn tất trước khi vận hành ngoài phạm vi lab tin cậy; **P3:** cải thiện tính nhất quán và khả năng bảo trì. Không xác nhận sự cố P0 hay rò rỉ dữ liệu thực tế. Test tái hiện chỉ dùng dữ liệu giả lập.

| ID | Mức | Phát hiện | Ảnh hưởng / việc nên làm | Bằng chứng |
|---|---|---|---|---|
| F01 | P1 | Nhiều business span ghi exception nhưng vẫn `Unset` | Truy vấn theo Error status bỏ sót lỗi; chuẩn hóa lỗi bất ngờ và business outcome | Đã tái hiện bằng code `user-service` |
| F02 | P1 | Nội dung lỗi đi qua traces mà không được redact như logs | Secret trong lỗi provider có thể vào trace store; sanitize trước khi ghi span và bổ sung lớp bảo vệ exporter | Đã tái hiện bằng secret giả lập |
| F03 | P1 | Checkout đếm confirmed hai lần sau lỗi `Finish` rồi retry | Một order nhưng counter tăng 2; sửa vị trí ghi metric và test recovery | Đã tái hiện bằng code checkout |
| F04 | P2 | Baggage đầu vào được chuyển nguyên sang outbound HTTP | Thiếu allowlist tại biên tin cậy; lọc trước khi gọi provider | Đã tái hiện ở shared transport; chưa thử qua gateway thật |
| F05 | P2 | `GetUser` bỏ context do logic span trả về | DB span trở thành sibling thay vì con của use case; giữ context mới | Đã tái hiện với repository fake |
| F06 | P2 | Manifests còn pin release trước bản sửa shutdown trên `main` | Flush có thể nhận context hết hạn; checkout worker còn shutdown không giới hạn ở tag đã pin | Đối chiếu source tag và `main` |
| F07 | P2 | Product log cùng lỗi ở adapter và fallback | Một lỗi dependency tạo nhiều record, mức Error dù response degraded thành công | Đọc đầy đủ đường gọi |
| F08 | P2 | Mockpay callback mất trace causality | Trace charge và webhook bị tách; cần context/span link cho callback do mình kiểm soát | Đọc emitter và HTTP client |
| F09 | P2 | Alert thiếu queue pressure và một số lỗi export traces/logs | Có thể chỉ thấy telemetry biến mất sau khi queue đầy hoặc sink lỗi | Kiểm tra toàn bộ live alert manifests |
| F10 | P2 | CI dependency floor chậm hơn policy một minor | CI vẫn cho phép dùng thư viện cũ hơn giới hạn đã quy định | Đối chiếu workflow pin và package tags |
| F11 | P2 | Collector Compose thiếu memory limit/limiter | E2E local không kiểm tra được khả năng chịu áp lực giống cluster | Kiểm tra Compose và Collector YAML |
| F12 | P2 trước production | OTLP plaintext, monitoring ingress chưa giới hạn, CH dùng tài khoản rộng quyền | Cần xác định trust zone, quyền ingest tối thiểu và isolation; không phải bằng chứng public exposure | Cấu hình mong muốn, chưa xác minh CNI runtime |
| F13 | P2 trước production | Queue volatile và chưa có loss budget định lượng | Restart/outage có thể mất telemetry; lab đã chấp nhận best-effort nhưng chưa đo mức mất | Cấu hình queue/Vector và runbook |
| F14 | P3 | Weaver kiểm tra một tập emissions đã được lọc | Không thể dùng C22 để tuyên bố mọi telemetry thô đều compliant | Đọc overlay và release gate |
| F15 | P3 | Inventory đặt tracer scope theo service name | Không đúng quy định package-path scope; sửa kèm test scope | Kiểm tra helper tracing |
| F16 | P3 | Docs lẫn trạng thái cũ, trạng thái hiện tại và mục tiêu | Dễ dùng sai hướng dẫn; sửa tại đúng owner, thêm guide hướng dẫn từng bước | Đối chiếu docs, source tags và manifests |
| F17 | P2 | Inventory Backoffice chưa có HTTP server spans và RED | Khó theo dõi riêng request quản trị; cân nhắc bổ sung middleware, giữ probe filters | Source main và tag; docs đã ghi nhận đúng giới hạn này |

> **Publication context (2026-10-26):** this report retains the 2026-10-23
> baseline and source snapshots. Main has since changed service pins and deployed
> analytics. Recheck each finding against the candidate image; this publication
> does not re-audit those newer binaries or close any finding.

## Scope, baseline, and evidence rules

The homelab worktree is `chore/worktree-20261023`, based on `bd55d8d19b778357684208f5f86acdd0ed2de030`. Service source is the fetched `main` snapshot below. Review covers all ten active Go services and their two worker modes, shared packages, the planned analytics service, frontend propagation boundaries, and platform telemetry configuration. Auth is archived and excluded from the active-fleet verdict.

**Configured version is not running version.** Kubernetes image tags were resolved to Git source tags for comparison; no image digest/build attestation or running-pod inspection was performed. Compose builds local source into `:dev` images, but no rebuild was performed. The production cluster directory is a placeholder. “Cluster configuration” below means the local/Kind desired state, not measured production behavior.

| Service | Audited main SHA | Configured image tag | Source tag SHA | Raw `RecordError` / `SetStatus` sites |
|---|---|---|---|---|
| cart | `bf8ddf7786030ecc6b52340857a2ad4bb2c32a7e` | `2.4.1` | `a70d34675039e58cc831d8282507fea31e090f4a` | 14 / 0 |
| checkout | `260495a479ff8b6c16e6193115988844e7d162e2` | `0.13.2` | `8afc6656329e3c77b4c1d455be1cd367a7d387f5` | 24 / 0 |
| inventory | `6f57cf4f27a8b7b632bac3fb492144b03b7ba1ae` | `0.9.1` | `b23fd378c58c43cc351d1bbd22ed764c1edf3b45` | 1 / 1 |
| notification | `befb5d4a3433f5c7a8a98c5f8251f8e1a2954f35` | `2.4.1` | `5a03ccebcc9c061c23914e2f5b856444081a25a2` | 18 / 0 |
| order | `e4067956bf465186e7cafa6702a1b9a149319d51` | `2.10.2` | `d1dafd5630f3abf8ca01062b95060223f07653e4` | 12 / 0 |
| payment | `adb7fe44b45949b6736d48172ad963f4db213eb3` | `2.8.0` | `14c1614dc55b31f1934c0b66758903b96e4896fa` | 12 / 0 |
| product | `f51792e085acfafe5048078226c1f5bb2153abe0` | `1.16.1` | `75417257728ba1959161d5f08e45df0b02efe72a` | 17 / 0 |
| review | `878fff12f332abe73a8c305d96486693e5b49bff` | `2.6.0` | `d14e06f98636521708c43838db593f02a35b746d` | 7 / 0 |
| shipping | `cddfd7a0b8720de119fbc6ee1a6ec3b35d071076` | `1.10.0` | `d2a85ce626b9876c4162531e56d3041082f7ea7d` | 7 / 0 |
| user | `35781d736e74f29284565c89070c99b6dde64fa3` | `2.5.1` | `bb6c9f86b2ffb7f5d7779f38b8af02451e549519` | 5 / 0 |

Counts are lexical sites in production `internal/**/*.go`, excluding tests; they are not counts of defective paths. Inventory and analytics use explicit bounded error handling. Raw `RecordError` is not inherently wrong, and transport instrumentation can set its own final status. The concrete failing logic paths are identified in F01.

| Other repository | Reviewed SHA | Scope |
|---|---|---|
| analytics-service | `8e4667fb5a2f00e6572a803efe451c9ea6470d82` | Planned reader; reviewed separately, not counted as deployed |
| pkg | `c2e8aa4c22beab580f6374895a8d30bb5c89a99b` | SDK, transport, DB, log, Temporal, registry modules |
| gha-workflows | `cc687b8a22c98ea19f33ca10f1958b47bf1b01ec` | The exact SHA pinned by service callers |
| frontend | `287797739864d38ebccfe727eff659ffa74dcef3` | Fetch client and OTel dependency inventory |
| admin-service | `bae236db821aba81a9180045210ee2c420d1e1ab` | Fetch client and OTel dependency inventory |

The pre-existing untracked `product-service/.DS_Store` and `gha-workflows/docs/review-tracker.html` were excluded and preserved. No service code was changed.

All eleven Go source repositories pin `obsx v0.48.0`, `logger/slogx v0.4.0`, and `httpmw v0.4.0`. The ten active services pin `dbx v0.40.1`; gRPC consumers use `grpcx v0.38.0`, and order/checkout use `temporalx v0.45.0`. The ten configured release tags also use those five telemetry module versions where applicable. `git diff <consumed-tag> HEAD -- <module>` is empty for all six shared modules reviewed, so shared HEAD inspection applies to those consumed versions. Their module-tag commits are `63ab9e1feb5999f1232c2ca04e1d7d66c5d54a0a` (the five telemetry modules) and `fd56ffb68c7fbce4bcff18c2d555df36cf57874b` (`dbx`).

The SDK/contrib pins are OTel core/trace/metric **v1.46.0**, log API/SDK/exporter **v0.22.0**, and transport/runtime contrib **v0.71.0**. Semantic conventions and Weaver registry dependency are **v1.41.0**. Independent version lines are intentional; no blanket “all modules must share a version” finding is made.

Collector contrib is **0.161.0** in Compose and cluster. The cluster chart constraint is `<0.176.0`; its resolved chart version was not inspected. Compose config identifies VictoriaMetrics/vmagent/vmalert `v1.154.0`, VictoriaTraces `v0.11.1`, VictoriaLogs `v1.53.0`, ClickHouse `26.9`, Vector `0.59.0-alpine`, Pyroscope `2.4.0`, Grafana `13.2.3`, and the optional Weaver `v0.26.1`. These are configuration facts, not compatibility certification.

Evidence paths in findings are repository-relative and anchored to the SHA tables above. Homelab paths use the audit baseline. Historical runtime statements in existing docs were read as prior evidence, never as tests repeated on this date.

## What already works well

| Control | Assessment | Evidence / limitation |
|---|---|---|
| Shared SDK ownership | Pass in inspected production imports | Providers/exporters stay in shared modules; SDK imports in service tests are allowed. A `go.mod` SDK entry alone is not a violation. |
| HTTP/gRPC instrumentation | Partial fleet coverage | `httpmw`/`grpcx` own transport spans and RED. Inventory gRPC is instrumented, but its Backoffice HTTP router omits tracing/RED (F17). Manual logic behavior remains partial. |
| Context propagation with tracing disabled | Pass in shared setup/tests | `pkg/obsx/setup.go:417-450` installs W3C propagation after successful setup independently of the trace flag. This is not a guarantee after total setup failure. |
| Logs | Strong baseline; cross-signal privacy partial | `slogx` redacts before stdout and OTLP with one level gate and context IDs. Trace error values do not pass through this boundary (F02). |
| Metrics | Strong baseline; business semantics partial | Mandatory Views, bounded transport attributes, resource promotion allowlist, SDK cardinality cap. Checkout unique-outcome count is wrong on one recovery path. |
| DB/cache | Shared DB instrumentation and bounded cache signals | `dbx` configures otelpgx without query-parameter/connection-detail capture; product disables Redis statement/caller capture. Service error strings still need review. |
| Temporal | Replay-aware instrumentation present | Workflow metrics guard replay; catalog events use `temporalx.WorkflowEvent`; saga/history replay tests pass. Attempt counters are not durable financial totals. |
| Profiling | Shared setup and closed identity labels | All service modes use `obsx`; profiling remains direct-to-Pyroscope. Temporal span/profile linking is intentionally limited. Runtime overhead and delivery not measured. |
| Collector architecture | Appropriate for the lab | Limiter first in cluster pipelines, privacy transforms, bounded batching, independent exporters, schema bootstrap outside cluster exporter. Queues remain best-effort. |
| SLO source | Correct separation | Application SDK metrics feed SLOs; sampled span metrics serve separate exploration dashboards. No sampling-based undercount finding for current SDK RED SLOs. |
| Governance | Useful controls, incomplete behavior coverage | Blocking import policy, registry/codegen checks and release conformance gate exist. They do not prove error semantics, privacy, counter idempotency, or all expected emissions. |

Product's `redisotel` adapter is a vendor instrumentation dependency outside the literal “all instrumentation is in shared modules” narrative. It is not an OTel contrib import banned by the current policy. Document the exception/ownership rather than infer a forbidden import.

## Confirmed code and delivery findings

### F01 — P1: failed business spans can remain Unset

**Evidence.** `user-service/internal/logic/v1/service.go:73-76`, cart `service.go:37-40`, product `service.go:79-89`, order `service.go:81-91`, review `service.go:42-51`, shipping `service.go:39-47`, notification `service.go:60-63`, and checkout `confirm.go:175-178` record errors without setting the manual span status. Payment also records directly on active transport spans; those spans may later receive status from the transport layer. No internal service production call uses `obsx.RecordError` or `obsx.RecordOutcome` in this snapshot. The shared helper at `pkg/obsx/span.go:105-117` already sets status and `error.type`.

**Observed.** A disposable test called the real `GetProfile` logic with a failing repository fake and an in-memory span recorder: `failure span name=user.profile status=Unset events=1`. The SDK's behavior is expected: recording an exception does not set Error status [S1]. The defect is application error classification, not the continued use of the span-event API.

**Impact and remedy.** Queries filtering failed business spans miss failures. Service owners should classify expected domain rejections separately and route unexpected failures through a sanitized shared error helper. Do not blindly mark every not-found/conflict/decline as Error. Add logic tests for status, bounded `error.type`, and expected-outcome behavior. Fix F02 alongside helper adoption so classification does not increase sensitive-data export.

### F02 — P1: exception values bypass the log redaction boundary

**Evidence.** Payment `internal/core/provider/httpclient.go:116` and `:191-192` include a decoded provider response's error string. The charge error flows through `internal/logic/v1/service.go:335,375-383`, `resolve.go:370-377`, then `internal/web/v1/router.go:246-249` calls `span.RecordError(err)` before its redacted log. `pkg/obsx/privacy.go:15-22` removes five exact attribute keys, not exception text or span status descriptions. `obsx.RecordError` bounds text but does not redact it. Cluster `transform/privacy` deletes selected attributes only; it does not sanitize span-event messages or status text.

**Observed.** In a disposable copy of the consumed `obsx`, an error containing `password=AUDIT_SYNTHETIC_SECRET` survived `ForceFlush` through the actual privacy exporter in both `exception.message` and `status.description`. No real credential was used, and no deployed-store leakage was investigated.

**Impact and remedy.** Redacted logs do not make the trace copy safe. Sanitize provider/driver errors into safe classes at the boundary; share the reviewed value-redaction policy with trace error handling and cover event/status values as well as attributes. Test credential-bearing provider errors, nested causes, URLs and truncation boundaries through every enabled trace sink. The broader data-minimization principle is [S2]. Owner: `pkg` plus service error adapters.

### F03 — P1: checkout retries overcount completed sessions

**Evidence.** `checkout-service/internal/logic/v1/confirm.go:192` increments `checkout.sessions.confirmed` before `finishConfirm` at 196. If `Finish` fails, the session is already completed; a same-key retry enters recovery at 270 and increments again at 274 before another `Finish`. These logic files are unchanged between configured tag `v0.13.2` and inspected main.

**Observed.** The real Confirm logic, existing fakes and metric reader produced `orders.calls=1, confirmed delta=2` when `fakeIdem.finishFailNext` failed once and the caller retried. Existing business tests pass but do not assert this invariant.

**Impact and remedy.** Conversion/KPI metrics can exceed unique completed sessions during idempotency-store failures. Move recording to a successful completion boundary in both paths, and test repeated Finish failures and recovery. Document the remaining process-crash window: an SDK counter is best-effort and cannot be made transactionally exactly-once by moving one line. Durable financial reporting should read domain state/CDC. Owner: checkout.

### F04 — P2: arbitrary baggage crosses outbound HTTP boundaries

**Evidence.** `pkg/obsx/setup.go:426-428` installs `TraceContext` plus `Baggage`; `pkg/httpmw/client.go:17-21` uses the default global propagator with no destination/key filter. Payment `internal/core/provider/httpclient.go:49,65` uses that transport and request context. The app tracing contract says external provider calls must strip baggage keys. No application creating baggage is required for this path: an incoming carrier can supply it.

**Observed.** An isolated HTTP receiver received the synthetic `customer.email=audit-example@example.invalid` baggage extracted from an incoming carrier and forwarded by the shared transport. This proves the shared path, not acceptance through the deployed edge; gateway behavior was not exercised. Current mockpay is controlled by the platform, so actual third-party disclosure is not claimed. OTel explicitly documents this propagation risk [S3].

**Remedy.** Define trusted internal versus external destinations. Default-deny application baggage at ingress and strip it for external egress unless a reviewed allowlist exists; retain approved trace context separately. Test untrusted inbound keys and both destination classes. Owner: shared HTTP/propagation packages and gateway policy.

### F05 — P2: GetUser loses the logic span as repository parent

**Evidence.** `user-service/internal/logic/v1/service.go:35` discards the returned context (`_, span := ...`), then invokes the repository at line 40 with the old context.

**Observed.** A test of the real method inspected the context received by the fake repository: `equals server=true, equals logic=false`. The trace ID survives, but DB spans become siblings of `user.get`, obscuring its children.

**Remedy.** Retain the returned context and assert the repository child parent ID. Other discarded contexts, such as pure shipping calculations, must be evaluated by their actual child work rather than mechanically flagged. Owner: user-service.

### F06 — P2: configured releases lack the main-branch shutdown fix

**Evidence.** All ten configured service source tags differ from main in `cmd/main.go`: main now runs telemetry shutdown under a fresh five-second context instead of reusing the HTTP drain context. For example, user `v2.5.1` → main changes the `tp.Shutdown(shutdownCtx)` call; checkout `v0.13.2` → main also replaces worker `tp.Shutdown(context.Background())` with bounded `shutdownTelemetry`. Worker manifests pin order `2.10.2` and checkout `0.13.2`.

**Impact.** At the configured versions, an exhausted HTTP drain budget can leave no time for final telemetry, and checkout worker shutdown lacks its own deadline. This is a source-tag/configuration gap; the actual running image may differ and was not inspected.

**Remedy.** Ship the already-implemented lifecycle fixes through the normal release gate, then update API/worker pins together. Verify the full drain + DB/profiler stop + five-second telemetry budget against pod termination grace. `pkg/obsx/profiling.go:125-129` still ignores its supplied stop context, and synchronous gRPC/pool shutdown can block; do not describe a timeout argument as a strict bound on the entire process. Owner: service releases and homelab delivery. No tags or deployments were changed by this audit.

### F07 — P2: product enrichment logs the same failure twice

**Evidence.** `product-service/internal/web/v1/review_client.go:42-47` logs Error and returns a wrapped failure; the optional fallback in `internal/logic/v1/details.go:102-110` logs it again at Warn and returns degraded success. The inventory pair (`inventory_client.go:46-51`, `details.go:142-147`) repeats the pattern.

**Remedy.** Adapters should return classified errors and let the fallback decision boundary own the application log. Retain transport spans and one bounded degradation signal. Assert one application failure record with the intended severity; a separate HTTP access summary is not a duplicate business-error record. Owner: product-service.

### F08 — P2: the controlled mockpay callback breaks trace causality

**Evidence.** `payment-service/internal/mockpay/emitter.go:20-22` accepts only an event; line 81 starts a goroutine, line 115 creates its request with `context.Background()`, and line 54 constructs a bare HTTP client. The initial request can be instrumented while the callback has neither propagated context nor a span link. Shared `httpmw/client.go:24-28` overstates same-trace coverage for that webhook.

**Remedy.** For this controlled callback, preserve a SpanContext with a bounded detached lifetime, use shared client instrumentation, and decide whether to continue the trace or start a linked asynchronous trace. Keep event-ID correlation as a fallback. Real external providers need not support this contract; require links/correlation appropriate to their capabilities. Add a charge → emitter → webhook causality test. Owner: payment/mockpay.

## Pipeline and governance findings

### F09 — P2: queue pressure and some exporter failures lack alerts

**Evidence.** The Collector is independently scraped (`kubernetes/infra/configs/observability/metrics/servicemonitors/otel-collector.yaml:13-23`). Existing rules cover Collector down, metrics export failure and ClickHouse log/trace export failure. The active rule tree in the repository has no exporter queue utilization/enqueue failure or receiver/processor refusal alerts; non-ClickHouse trace/log exporter failures lack equivalent direct coverage. Local dashboard queue plots exist, so this is an alert gap, not total invisibility.

**Remedy.** Add pressure, refusal/enqueue loss and sink-specific export-failure coverage using the actual 0.161.0 emitted metric names [S4]. Exercise queue growth, backend outage and target disappearance before calling the alerts operational. Keep monitoring on its independent scrape path. Owner: platform observability.

### F10 — P2: the CI version floor permits excessive dependency lag

**Evidence.** The pinned shared policy `.github/lint/golangci-policy.yml:79-95` rejects versions below obsx `0.46`, slogx/httpmw `0.2`, grpcx `0.36`, temporalx `0.43`. Observed released versions are respectively `0.48`, `0.4`, `0.4`, `0.38`, `0.45`. Thus it permits two-minor lag despite the stated one-minor policy. Current fleet dependencies are aligned; the finding concerns future admission.

**Remedy.** For these observed releases, floors become `0.47`, `0.3`, `0.3`, `0.37`, `0.44`; release the workflow update and bump callers. Couple floor updates to shared releases and test a deliberately too-old fixture. Policy execution is configured blocking; actual GitHub Actions runs were not audited. Owner: `gha-workflows` and `pkg` release process.

### F11 — P2: Compose lacks the cluster memory safety envelope

**Evidence.** `local-stack/compose.yaml:378-388` has no Collector memory constraint, and `local-stack/observability/otel-collector-config.yaml` has no memory limiter; traces/logs also wire the debug exporter. Cluster values set a 1Gi container limit and limiter first, with hard 800MiB and spike 200MiB (soft 600MiB). Delta conversion and span-metric aggregation have no explicit measured cardinality budget.

**Remedy.** Give Compose an explicit memory envelope and limiter, gate verbose export, and size state/cardinality budgets from representative load. Local happy-path E2E cannot validate cluster overload behavior. No OOM was observed. Owner: local-stack/platform.

### F12 — P2 before production: the telemetry trust boundary is broad

**Evidence.** Cluster Collector receivers bind plaintext `0.0.0.0:4317/4318/4319` without authentication; zpages binds `:55679`. The monitoring namespace lacks the app-tier label targeted by generated default-deny policies, and no active monitoring ingress policy was found in the repository. Exporters use internal HTTP; ClickHouse uses the `default` credential via a Secret. The Service is ClusterIP and Compose host ports bind loopback: this is not evidence of public internet exposure.

**Remedy.** Document the trusted lab network, restrict producer/scraper/Vector ingress, constrain debug endpoints, and use a least-privileged ClickHouse ingest role. Require authenticated TLS for untrusted network or tenant boundaries. Verify CNI enforcement and permissions at runtime in a separate task. Owner: platform security/observability; the proposed production environment is not installed.

### F13 — P2 before production: loss tolerance is not quantified

**Evidence.** Collector has only health/zpages extensions and no persistent queue storage. ClickHouse uses queue size 1000 with four consumers and finite 300s retry in cluster. Other exporter queue/retry settings are mostly defaults, **not disabled**. Vector's four sinks explicitly use memory buffers with `drop_newest` (`kubernetes/infra/configs/observability/logging/vector/vector.yaml:420-515`). Edge access logs have only the ClickHouse store.

**Assessment.** A single Collector and volatile queues are documented lab tradeoffs. Restart/full-queue/outage loss is possible, but no loss measurement was run. Redundant stores do not make every stream durable. Official resilience guidance distinguishes bounded retry, in-memory queues and persistent storage [S5].

**Remedy.** Define an acceptable loss window first. If durable retention is required, size selected persistent exporter queues/PRW WAL from volume and outage budget, then test restart/full-queue recovery. Kafka and extra replicas are not prerequisites for this lab. Owner: platform observability.

### F14 — P3: conformance evidence covers a sanitized subset

**Evidence.** `local-stack/observability/otel-collector-weaver.yaml:24-78` rewrites/removes Redis legacy fields, removes capitalized Temporal log keys, and excludes edge/Keycloak. C22 documents these exceptions in `local-stack/docs/e2e-audit.md:2209-2232`. Registry/codegen checks run in pkg CI, while live-check is a required manual release gate, not a shared service workflow job.

**Remedy.** Keep an owned, versioned exception list; report exactly which producers and attributes the gate validates. Add assertions that required signals exist, not merely that observed names are registered. Track vendor telemetry separately before tightening the raw-emission claim. Weaver registry checks and live checks establish different evidence [S6]. Owner: registry/release tooling.

### F15 — P3: inventory trace scope violates the package-path rule

**Evidence.** `inventory-service/internal/logic/v1/tracing.go:20` uses `tracerScope = "inventory"`; the application contract requires the instrumented package path. Resource `service.name` already carries deployment identity.

**Remedy.** Use the package path and assert emitted scope. Assess consumer impact before any wider metric-scope renaming: several business meters also use service names, but that is distinct from the explicit manual-trace rule. Owner: inventory-service.

### F16 — P3: documentation mixes current, historical and planned behavior

| Location | Drift or ambiguity | Correct disposition |
|---|---|---|
| `docs/api/observability.md:10,209` and pillar introductions | Current-sounding fleet version claims still say slogx `0.2` / obsx `0.45` | Keep dated release evidence; link current versions to manifests/go.mod instead of duplicating a live inventory |
| `docs/api/observability.md:204-205` | Payment described as directly importing otelhttp with no shared helper | Shared `httpmw.Transport` exists and is used in main and configured tag |
| `docs/api/observability.md:115-116` | Checkout worker described as unbounded | True at configured tag, fixed on main: label the delivery state explicitly (F06) |
| `docs/observability/opentelemetry/README.md:16,70,204-205` | Current logs described as zap/otelzap | Current main and configured releases use slogx/otelslog |
| `docs/observability/opentelemetry/fundamentals.md:526` | Present-day concept map references removed `obs.ZapCore` | Preserve RFC-0014 history as historical; replace present-day mapping |
| `docs/observability/opentelemetry/collector.md:5,53,61,112,155` | Seven backends, no connectors, soft limit 800, simplistic scaling advice | Actual config has span_metrics and soft limit 600; distinguish stores, exporters and pipelines; scaling depends on stateful components |
| `docs/api/observability.md:683-710` | Compliance checklist promises behavior not enforced by current tests/policy | Link each requirement to executable check or explicitly mark review-only coverage |

Missing manual-span tests, value-redaction coverage and metric recovery invariants are implementation gaps, not reasons to weaken the contract. Correct stale descriptions only after classifying each mismatch using the existing API documentation ownership rules.

### F17 — P2: inventory Backoffice lacks HTTP server spans and RED

**Evidence.** `inventory-service/cmd/main.go:301-303` installs Logging and Recovery but no `httpmw.Tracing`; the protected Backoffice routes use this router. The configured `v0.9.1` tag has the same omission. The shared tracing middleware supplies both the server span and `http.server.*` metrics. Inventory gRPC remains instrumented. `docs/api/observability.md:280-285`, `tracing.md:103-106`, and `metrics.md:85-90` accurately document this exception.

**Assessment and remedy.** This is a documented coverage gap, not documentation drift or a newly discovered policy violation. Access logs and gateway telemetry remain available, but they do not supply the application's HTTP server spans/RED for admin requests. Consider mounting the shared tracing middleware before logging, retaining probe exclusions; verify Backoffice span parenting, access-log correlation and route metrics. Owner: inventory-service. No runtime request was exercised.

## Comparison with established large-platform practice

The comparison is about engineering properties, not company size or copying a vendor stack. Primary historical examples are Google Dapper (2010), eBay's OTel adoption, and Uber's tracing evolution (2017); they are context, not certification of modern SDK compliance [C1–C3].

| Principle | Homelab assessment | Next useful improvement |
|---|---|---|
| Instrument shared frameworks and clients once | Strong: obsx/httpmw/grpcx/dbx/temporalx | Test real semantic outcomes across boundaries, not imports alone |
| Separate platform signals from business KPIs | Good: SDK RED, domain counters, explicit catalog | Repair retry/count semantics and distinguish attempts from durable outcomes |
| Limit cost using deliberate sampling/cardinality | Good baseline; no measured fleet budget here | Quantify rates, retention and overflow; document ingress sampling trust |
| Treat telemetry as an operational pipeline | Partially implemented | Queue/loss monitoring, failure drills and explicit loss budgets |
| Govern schema and privacy centrally | Strong log boundary and registry, incomplete trace coverage | Extend value safety and behavior-level conformance |
| Make developer onboarding repeatable | Existing contract is substantial | Add a short task-based implementation guide and repair stale maps |

ParentBased sampling honors sampled remote parents; the edge ratio is not a hard cap for caller-supplied context. Current local/Kind sampling is intentionally 100%; the base 50% production value is planned and currently overridden. Choose an ingress trust policy before treating a ratio as a cost bound [S7]. Browser clients currently have no OTel dependencies/injection in the inspected fetch wrappers; the gateway CORS allowlist does not include `traceparent`/`baggage`. That is a current boundary, not a broken browser tracing feature. Adding RUM would require its own privacy and propagation design.

Version-specific safeguards against false positives:

- Go SDK v1.46.0 defaults to **2,000 datapoints per instrument per collection**, so absence of `WithCardinalityLimit` is not unbounded SDK metrics [S8]. Fleet time-series budgets and overflow alerting remain separate concerns.
- Collector span_metrics v0.161.0 includes `collector.instance.id` by default. Multiple replicas do not automatically collide; inspect downstream labels and aggregation before alleging a single-writer violation [S9].
- Delta-to-cumulative state affinity matters for actual delta inputs. Current Go producers use cumulative metrics; future scaling guidance must account for delta producers without claiming present corruption [S10].
- OTEP 4430 is a migration plan. Existing Go v1.46 `RecordError`/`AddEvent` usage is not itself a deprecation defect; F01 concerns missing status and F02 sensitive values [S11].
- No requirement to add tail sampling, Kafka, a different backend, universal HA, OCB, declarative SDK config or eBPF profiling was established by this audit.

## Documentation proposal

**Keep one normative owner:** `docs/api/observability.md`, with logs/metrics/tracing/profiling as its signal-specific contracts. Keep Collector/backend deployment and runbooks under `docs/observability/`. Keep ADR/RFC rationale and dated audits as evidence.

Propose one new, non-normative `docs/api/telemetry-implementation.md` as a task-based recipe for service authors. It should contain:

1. A reading map and prerequisites: shared packages, app/worker modes, and who owns each signal.
2. The complete bootstrap and shutdown sequence, linked to tested shared helpers and release-version context.
3. HTTP/gRPC/outbound/DB/Temporal examples, including context parenting and trusted versus external propagation.
4. A decision table for expected outcomes, unexpected errors, one-log ownership and domain metric recording points.
5. A PR verification recipe: in-memory span/metric/log assertions, privacy cases, retry/replay tests, and links to the actual release gates.

The guide must link the normative tables rather than copy their attribute lists, env catalogs or version numbers. Add it to the API learning path, service template and observability hub when implemented. In the same future docs change, refresh present-day OTel maps, clearly label historical examples, and attach coverage evidence to the compliance checklist. Do not rewrite past audit findings as if they were current or silently refresh historic measurement dates.

No new guide or policy changes are implemented by this report. A change in privacy boundaries, sampling policy, or storage durability should use its owning design record; the report does not allocate an RFC/ADR number.

## Verification performed and remaining evidence

Environment: **Go 1.27.3, darwin/arm64**, on 2026-10-23. Existing tests ran with `-count=1`, without race mode or integration tags. They use mocks or in-process HTTP/gRPC/Redis/Temporal fixtures and do not prove backend delivery.

| Check | Scope | Result |
|---|---|---|
| `go test -count=1 ./...` | Each of pkg obsx, httpmw, grpcx, logger/slogx, temporalx, dbx | Pass |
| `go test -count=1 ./internal/logic/...` | All ten active Go service repos | Pass |
| `go test -count=1 ./internal/telemetry/... ./internal/logic/... ./internal/core/repository/...` | Analytics | Pass |
| Saga/fulfillment/cancellation/reconcile suites | Order, including recorded-history replay | Pass |
| Cache and web suites | Product | Pass |
| Provider/mockpay/web suites | Payment | Pass |
| Workflow and cmd suites | Checkout | Pass |
| In-memory logic-span error and parent probes | Disposable user-service copy | Reproduced F01 and F05 |
| Finish-failure metric probe | Disposable checkout-service copy | Reproduced F03 |
| Privacy-exporter synthetic-secret probe | Disposable obsx copy matching consumed tag | Reproduced F02 |
| Incoming-baggage outbound HTTP probe | Disposable httpmw copy matching consumed tag | Reproduced F04 |

The reproduction tests deliberately assert the current faulty behavior; their “PASS” means the finding was reproduced, not corrected. Logs are local working evidence under `/private/tmp/audit-tests-*.log` and `/private/tmp/audit-extra-*.log`; the exact scenarios/results below remain in this report if those temporary files are removed.

### Reproduction protocols

- **F01/F05:** install an in-memory trace provider; have the existing user repository fake return `database unavailable`; call real `GetProfile` and inspect the ended `user.profile` span. Then call `GetUser` under a parent span and capture the SpanContext passed to its repository fake. Results: one exception with `Unset`; repository receives parent span ID, not the created logic span ID.
- **F02:** in a disposable copy of obsx, call `SetupObservability` with its internal `withSpanExporter(tracetest.NewInMemoryExporter())`, tracing enabled and ratio 1. Start a span, call `RecordError` with `errors.New("password=AUDIT_SYNTHETIC_SECRET")`, end and ForceFlush. Assert that the exporter receives the exact synthetic text in exception.message and status.description. This exercises the real privacy wrapper.
- **F03:** use checkout's existing `readySession`, `fakeRepo`, `fakeIdem{proceed:true, finishFailNext:true}`, `fakeOrders`, `confirmSvc` and `testMetricReader`. Snapshot `checkout.sessions.confirmed`, call Confirm twice with the same user/session/key, then collect again. First call fails Finish, second succeeds; the order fake is called once while the counter delta is two.
- **F04:** install the same TraceContext+Baggage composite, extract synthetic baggage from a MapCarrier, create an HTTP request with that context, and send through `httpmw.Transport(nil)` to an `httptest.Server`. The receiver sees the baggage header. No external system receives the synthetic value.

### Code-path coverage

All eleven bootstrap files, dependency manifests, service workflow callers and production telemetry import/call inventories were inspected. Deeper selected paths included:

| Service | Reviewed behavior |
|---|---|
| User | GetUser/GetProfile/UpdateProfile → logic → Postgres repository context and errors |
| Product | CRUD plus details aggregation → inventory/review clients → fallback; Valkey cache tracing/metrics |
| Inventory | Reservation claim/replay/rejection/cancellation, admin path, transaction boundary and bounded tracing |
| Cart | HTTP use cases, gRPC snapshot branches, repository mutation and counter outcomes |
| Order | API/worker bootstrap, order use cases, saga events/metrics/replay, fulfillment/outbox paths |
| Review | List/create, duplicate pre-check and unique-race paths, rating metric after insert |
| Shipping | Get/create/cancel/quote/estimate; documented attempt/idempotent outcome metrics |
| Notification | Email/SMS/read paths, delivery-key repository behavior and changed-row metrics |
| Payment | CreateIntent/driveCharge/release, unknown-outcome preservation, provider transport, reconciliation metrics, callback emitter |
| Checkout | Confirm/recovery/idempotency, promo/availability metrics, expiration workflow and lifecycle |
| Analytics | Overview/freshness instrumentation, ClickHouse error sanitization, cancellation and lifecycle |

This is deep selected-path review plus whole-fleet inventories, not proof that every branch or every SQL statement is correct. Known positive counterexamples were preserved: shipping deliberately counts successful idempotent calls, notification uses changed-row counts, inventory classifies bounded outcomes, and analytics sanitizes driver failures.

**Not performed:** Compose/Kind startup, Collector config acceptance against the actual image, rendered/resolved chart validation, live telemetry queries, fault injection into a deployed pipeline, binary/digest attestation, production traffic measurement, race/integration test runs, profiling benchmarks, or a release-tag qualification audit.

## Recommended sequence and acceptance checks

| Order | Work | Completion evidence |
|---|---|---|
| 1 | F02 value safety, then F01 classification; F03 counter recovery | Synthetic sensitive provider text absent from exported events/status; failed business spans classified; one completed session not double-counted on Finish retries |
| 2 | F04 trust-boundary propagation; F05/F07/F08/F17 call-path coverage | Baggage filtered at external boundary; correct child parent IDs; one owner log; callback parent/link evidence |
| 3 | Release existing lifecycle fixes (F06), tighten CI (F10/F15) | Exact merged-SHA release gate, coordinated image pins, old-dependency rejection fixture and scope test |
| 4 | F09/F11 monitoring and local safety | Queue/refusal/exporter fault tests; bounded memory behavior and recovery, verified alert routing |
| 5 | Decide F12/F13 production boundaries and budgets | Least-privilege ingest, network enforcement, measured outage/restart loss consistent with accepted budget |
| 6 | F14/F16 conformance scope and docs | Owned exceptions, required-emission assertions, one normative owner and task-based implementation guide |

Implementation changes affecting service code/shared modules/gateway/Compose require the repository's full API/browser/telemetry release audit against exact merged SHAs before tagging. The tests in this static report do not replace that gate.

## References

Primary sources were checked on 2026-10-23. Tagged code is used for version-specific behavior; rolling official guidance is a design reference. Company examples are historical first-party evidence, not a claim about their current complete stacks.

- **[S1]** [OTel Go instrumentation: errors and span status](https://opentelemetry.io/docs/languages/go/instrumentation/#record-errors) and [Go SDK v1.46.0 span implementation](https://github.com/open-telemetry/opentelemetry-go/blob/v1.46.0/sdk/trace/span.go).
- **[S2]** [OpenTelemetry handling sensitive data](https://opentelemetry.io/docs/security/handling-sensitive-data/).
- **[S3]** [OpenTelemetry baggage security considerations](https://opentelemetry.io/docs/concepts/signals/baggage/).
- **[S4]** [Collector internal telemetry](https://opentelemetry.io/docs/collector/internal-telemetry/).
- **[S5]** [Collector resiliency](https://opentelemetry.io/docs/collector/resiliency/) and [v0.161.0 exporter helper](https://github.com/open-telemetry/opentelemetry-collector/blob/v0.161.0/exporter/exporterhelper/README.md).
- **[S6]** [Weaver v0.26.1 usage](https://github.com/open-telemetry/weaver/blob/v0.26.1/docs/usage.md).
- **[S7]** [Go v1.46.0 sampler implementation](https://github.com/open-telemetry/opentelemetry-go/blob/v1.46.0/sdk/trace/sampling.go).
- **[S8]** [Go metric SDK v1.46.0 cardinality configuration](https://github.com/open-telemetry/opentelemetry-go/blob/v1.46.0/sdk/metric/config.go).
- **[S9]** [span_metrics v0.161.0 configuration and single-writer behavior](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/v0.161.0/connector/spanmetricsconnector/README.md).
- **[S10]** [Collector scaling](https://opentelemetry.io/docs/collector/scaling/) and [delta-to-cumulative v0.161.0](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/v0.161.0/processor/deltatocumulativeprocessor/README.md).
- **[S11]** [OTEP 4430 migration plan at specification v1.61.0](https://github.com/open-telemetry/opentelemetry-specification/blob/v1.61.0/oteps/4430-span-event-api-deprecation-plan.md).
- **[C1]** [Google Research: Dapper (2010)](https://research.google/pubs/dapper-a-large-scale-distributed-systems-tracing-infrastructure/).
- **[C2]** [eBay Engineering: Why and How eBay Pivoted to OpenTelemetry](https://innovation.ebayinc.com/stories/why-and-how-ebay-pivoted-to-opentelemetry/).
- **[C3]** [Uber Engineering: Evolving Distributed Tracing (2017)](https://www.uber.com/ci/en/blog/distributed-tracing/).
- In-house: [Application contract](../../api/observability.md), [logs](../../api/logs.md), [metrics](../../api/metrics.md), [tracing](../../api/tracing.md), [profiling](../../api/profiling.md), [shutdown](../../api/graceful-shutdown.md), [OpenTelemetry platform](../opentelemetry/README.md), [Collector](../opentelemetry/collector.md), [previous audit (2026-09-16)](2026-09-16-telemetry-standards.md).
