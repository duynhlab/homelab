# KyvernoAdmissionDenying

| | |
|---|---|
| **Severity** | warning |
| **Category** | errors |
| **Source** | [`kyverno/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/kyverno/alerts.yaml) |
| **Metrics** | `kyverno_admission_requests_total{request_allowed="false"}` |
| **Status** | active |
| **Dashboard** | GitOps → Kyverno |
| **Local-stack** | not present — no Kubernetes admission layer in the compose stack |

## Meaning

Kyverno has denied admission requests continuously for 10 minutes. On a healthy
cluster every series of `kyverno_admission_requests_total` carries
`request_allowed="true"` — verified on 2026-08-21, where all 448 series did.

**Firing is not automatically a defect.** Only one policy can deny:
`disallow-default-namespace`, the sole rule with `validationFailureAction:
Enforce`. A denial can mean the policy is doing exactly its job on a genuinely
bad manifest. The 10-minute `for` is what separates the two cases: a human
applying something wrong fixes it and moves on, while a **controller** retrying
a rejected manifest denies forever.

## Impact

Something cannot be created, and whatever is retrying it will keep failing. The
shape that matters here is a **GitOps stall**: Flux applies a manifest, Kyverno
refuses it, the Kustomization never goes Ready, and everything `dependsOn` it
parks behind a message that names the dependency rather than the denial. The
reader sees `dependency ... is not ready` and never learns a policy said no.

## Diagnosis

### PromQL

```promql
sum(rate(kyverno_admission_requests_total{request_allowed="false"}[5m])) > 0

# Which kind and webhook — the fastest narrowing available from metrics alone
sum by (resource_kind, request_webhook) (
  rate(kyverno_admission_requests_total{request_allowed="false"}[10m])
)

# Which policy and rule produced failures, and where
sum by (policy_name, rule_name, resource_namespace) (
  rate(kyverno_policy_results_total{rule_result="fail"}[10m])
)
```

### Grafana

- **GitOps → Kyverno** — admission requests split by `request_allowed`; the
  denial series appearing at all is the signal.

### kubectl / logs

```bash
kubectl -n kyverno logs -l app.kubernetes.io/component=admission-controller --tail=200 \
  | grep -i -E 'denied|blocked|failed'

# The authoritative verdict list, including Audit-mode findings
kubectl get policyreport,clusterpolicyreport -A 2>/dev/null | head -20
kubectl get clusterpolicyreport -o json \
  | jq -r '.items[].results[] | select(.result=="fail")
           | "\(.policy)/\(.rule)  \(.resources[0].namespace)/\(.resources[0].name)"' | sort -u

# Is Flux the one being refused?
flux get kustomizations -A | grep -v True
```

### VictoriaLogs / traces

```logsql
_time:30m namespace:"kyverno" | filter _msg:~"denied|not allowed" | limit 50
```

## Mitigation

1. Identify the refused resource from the PolicyReport query above. Fix the
   **manifest**, not the policy — a namespace-less workload is a real defect, and
   `disallow-default-namespace` exists because it is.
2. If the refusal is legitimate but the workload must ship now, the sanctioned
   route is a `PolicyException` under
   [`configs/kyverno/exceptions/`](../../../../kubernetes/infra/configs/kyverno/exceptions/)
   carrying `platform.duynhlab.dev/owner` and `expires-at`, plus a row in
   [`policy-exceptions.md`](../../../security/policy-exceptions.md). Add a
   **skip** case to the policy's fixture under `configs/kyverno/tests/` in the
   same PR, so the exception's blast radius is pinned rather than assumed.
3. Only then consider whether the policy itself is wrong.

**Do not** flip the policy to `Audit`, and **do not** loosen its pattern, to
clear the alert. That is the documented anti-pattern in
[`policy-catalog.md`](../../../security/policy-catalog.md): the exception
mechanism exists precisely so the guardrail stays intact and the waiver expires.

## Escalation

**Ticket** in the ordinary case — a rejected manifest is feedback working. It
becomes an **incident** when a Flux Kustomization is stalled behind the denial
(the platform cannot converge) or when the denied resource is a platform
component rather than an application.

## Related

```bash
git log --oneline -5 -- kubernetes/infra/configs/kyverno/
```

- [KyvernoPolicyRuleErrors](./KyvernoPolicyRuleErrors.md) — the opposite
  failure: the rule could not decide at all, so nothing is denied and nothing is
  protected.
