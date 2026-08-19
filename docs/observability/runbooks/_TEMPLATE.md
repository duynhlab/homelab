# AlertName

<!--
The ONE canonical runbook template (there is deliberately no per-folder copy —
the two that existed drifted apart within a month). Rules of use:

  * File name and H1 are the exact `alertname` label, verbatim casing, so the
    file is greppable straight from a page. One file per alert; a High/Critical
    pair MAY share a file when the procedure is identical (the envoy-gateway
    precedent) — name the file after the common stem and say so in line 1.
  * Every alert that has a runbook carries a `runbook_url` annotation pointing
    at it (absolute GitHub URL, the house convention). An alert without a
    runbook is a recorded gap, not a default.
  * DOMAIN SPECIFICS — extra quick-facts rows, the preferred diagnosis dialect,
    domain dashboards — live in the folder README's "Domain specifics" section,
    never in a forked template.
  * Sections marked (required) must exist in every runbook. Optional sections
    are dropped, not left as placeholders.
-->

| | |
|---|---|
| **Severity** | warning / critical — and for a shared file, which threshold makes it which |
| **Category** | the alert's `category` label (availability / latency / saturation / errors / data / platform) |
| **Source** | repo path of the rule manifest that defines the alert |
| **Metrics** | the metric families the expr reads |
| **Status** | active / inactive on Kind / gated (`flag`) / not deployed — same vocabulary as the folder index |
| **Dashboard** | the Grafana board (folder → title) where verification starts |
| **Local-stack** | only when the compose twin differs: job name, port, or "not present locally" |

<!-- Optional domain rows (folder README defines which apply): Clusters,
     Custom queries, Applies to (version range). Drop rows that add nothing —
     an empty cell is noise, a missing row is a decision. -->

## Meaning

(required) What fires and when: threshold, `for` duration, and what the metric
actually measures — including the honest qualifier when firing is not always an
incident.

## Impact

(required) The business or operational consequence if this is ignored — what
the shopper/operator experiences, not a restatement of the expr. Say when the
impact is conditional ("only during a deploy", "only if X co-fires").

## Diagnosis

(required) Evidence-gathering, cheapest first. Use the sub-headings that apply:

### PromQL

```promql
# The alert expr verbatim, then the drill-down queries that localize the cause
```

### Grafana

- **Folder → Dashboard** — the one question this board answers here.

### kubectl / logs

```bash
# Export identifiers from the alert labels FIRST, then the commands.
```

### VictoriaLogs / traces

LogsQL or a trace pivot, when the metric alone cannot name the culprit.

## Mitigation

(required) Safe immediate actions, cheapest and most reversible first, numbered.
Name the parameters that must NOT be touched casually. Link procedural runbooks
instead of inlining multi-step surgery.

## Escalation

(required) The page-vs-ticket call: what makes this an incident, what stays a
ticket, and **what not to do** (the action that looks helpful and makes it
worse). If another alert co-firing changes the answer, say which.

## Related

(optional) Sibling alerts that share a cause, dependencies that fail together,
and the recent-changes check when config drift is a plausible cause:

```bash
git log --oneline -5 -- <path to the manifest this alert guards>
```
