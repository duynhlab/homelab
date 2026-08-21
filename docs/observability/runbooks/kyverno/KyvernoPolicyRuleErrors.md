# KyvernoPolicyRuleErrors

| | |
|---|---|
| **Severity** | warning |
| **Category** | errors |
| **Source** | [`kyverno/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/kyverno/alerts.yaml) |
| **Metrics** | `kyverno_policy_results_total{rule_result="error"}` |
| **Status** | active — **arms when emitted**: the live label set on 2026-08-21 was `rule_result={pass,fail,skip}` only |
| **Dashboard** | GitOps → Kyverno |
| **Local-stack** | not present — no Kubernetes admission layer in the compose stack |

## Meaning

A policy rule returned **`error`** rather than a verdict: Kyverno could not
evaluate it. This is not a stricter `fail` — it is the **absence of a decision**.

The reason this alert exists at all is that an `error` is *invisible*. Four of
the five validate policies run in `Audit` mode, where a `fail` is a report entry
and nothing more; an `error` is also just a report entry, and on a dashboard or
in a `grep` it reads exactly like a compliant resource. The policy appears to be
protecting something and is protecting nothing.

Two concrete instances, both from this repo:

- **Autogen path rewriting.** `require-probes` produced **28** `error` results
  because Kyverno's autogen rewrote `request.object.metadata.ownerReferences`
  into `request.object.spec.template.metadata.ownerReferences`, which does not
  exist on a controller. Fixed with `autogen-controllers: none` (#848).
- **A null in a JMESPath.** The same rule then measured
  `ownerReferences[?kind=='Job'] | length(@)` with no default, so any Pod
  carrying **no** `ownerReferences` — a bare manifest, anything `kubectl run`
  creates — made the expression measure a null and error out. Real workloads are
  ReplicaSet-owned, so the field exists and the cluster never showed it. Found
  by the policy fixtures on their first run, fixed with a `|| ` + backtick-`[]`
  default, and pinned by `tests/require-probes`.

Both were found by *running* something, never by reading the manifest.

## Impact

Whatever the rule was supposed to enforce is unenforced, for the resources that
error. In `Audit` mode nothing breaks and nothing warns — the finding is simply
never made. In `Enforce` mode the consequence flips: `failurePolicy` decides
whether an un-evaluable rule admits or refuses the request.

## Diagnosis

### PromQL

```promql
sum(rate(kyverno_policy_results_total{rule_result="error"}[10m])) > 0

# Which policy and rule, and on which resources
sum by (policy_name, rule_name, resource_kind, resource_namespace) (
  rate(kyverno_policy_results_total{rule_result="error"}[10m])
)

# Sanity that the selector shape works at all — this returns data today
sum by (rule_result) (rate(kyverno_policy_results_total[10m]))
```

### Grafana

- **GitOps → Kyverno** — policy results split by `rule_result`; `error` should
  be a flat zero line, and its appearance is the whole signal.

### kubectl / logs

```bash
POLICY="<from the alert's policy_name label>"

# The report carries the evaluation message, which the metric does not
kubectl get clusterpolicyreport -o json \
  | jq -r --arg p "$POLICY" '.items[].results[]
      | select(.result=="error" and .policy==$p)
      | "\(.rule)  \(.resources[0].namespace)/\(.resources[0].name)  \(.message)"' | sort -u

kubectl -n kyverno logs -l app.kubernetes.io/component=admission-controller --tail=200 \
  | grep -i -E 'error|failed to evaluate|jmespath'

# Reproduce offline against the exact resource -- this is the fast loop
kubectl get pod -n <ns> <name> -o yaml > /tmp/r.yaml
kyverno apply kubernetes/infra/configs/kyverno/cluster-policies/$POLICY.yaml --resource /tmp/r.yaml
```

### VictoriaLogs / traces

```logsql
_time:1h namespace:"kyverno" | filter _msg:~"jmespath|failed to evaluate|variable substitution" | limit 50
```

## Mitigation

1. Reproduce with `kyverno apply` against the offending resource. An
   un-reproducible error is a Kyverno bug; a reproducible one is a policy bug,
   and almost always a **missing default** in a variable expression.
2. Fix the expression, and add the failing shape to the policy's fixture under
   [`configs/kyverno/tests/`](../../../../kubernetes/infra/configs/kyverno/tests/)
   **in the same PR**. `make validate` then keeps it fixed — that is the whole
   point of the fixtures, and how the second instance above was caught.
3. Common causes, in the order they have actually occurred here:
   - an absent field measured without a default (`|| ` + backtick-`[]`)
   - autogen rewriting a path the rule depends on → `autogen-controllers: none`
   - a `context` lookup (API call, ConfigMap) that is unavailable

**Do not** silence this by narrowing the rule's `match` until the erroring
resources fall outside it. That converts a visible error into invisible
non-coverage, which is strictly worse and much harder to find later.

## Escalation

**Ticket**, with one exception: if the erroring policy runs `Enforce` — today
only `disallow-default-namespace` — escalate, because `failurePolicy` is now
deciding admission on a rule that cannot evaluate.

## Related

```bash
git log --oneline -5 -- kubernetes/infra/configs/kyverno/cluster-policies/
```

- [KyvernoAdmissionDenying](./KyvernoAdmissionDenying.md) — the opposite: the
  rule decided, and said no.
- [`configs/kyverno/tests/`](../../../../kubernetes/infra/configs/kyverno/tests/)
  — the offline gate that catches this class before it reaches a cluster.
