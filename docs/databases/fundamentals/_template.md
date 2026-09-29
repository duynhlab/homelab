<!--
Contributor template for every page in the PostgreSQL internals learning path.
Copy the file, replace placeholders, and remove all author comments plus the
review gate before publishing. Keep the explanation-first progression:
mechanism → homelab evidence → bounded read-only observation.

Keep the title in sentence case. Name the mechanism, not the file number.
-->

# {Mechanism} — {concrete question or consequence}

<!--
One-line hook. State why the reader should care before defining the mechanism.
Use direct English, active voice, and no unexplained acronym.
-->

{One or two sentences connecting the mechanism to a query, commit, lag value,
alert, or operational decision the reader will recognize.}

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | {Foundation / practitioner / operator / mastery entry point} |
| **Prerequisites** | {Previous chapter names or specific concepts} |
| **Deployment status** | {Deployed / Reference — not deployed / Planned — owning accepted record} |
| **Platform scope** | {Cluster, database, pooler, component, or mechanism} |
| **Evidence context** | {PostgreSQL `SELECT version()`; observed timestamp and timezone, or “Repository facts only”} |
| **This page owns** | {The one question this chapter answers} |
| **Not this page** | {Canonical page that owns adjacent content} |
| **Previous / next** | {Previous chapter title} / {Next chapter title} |

## Questions this chapter answers

<!--
Write three to five observable questions. Avoid “understand” or “learn” because
neither says what the reader can explain or inspect after reading.
-->

- {What happens when ...?}
- {Where is ... persisted?}
- {Which evidence distinguishes ... from ...?}

## Mental model

<!--
Give the 60-second explanation. Introduce only the vocabulary needed for this
page. Define each term on first use and link the shared glossary when useful.

Use an analogy only when it is precise. Follow it immediately with the point
where the analogy stops matching PostgreSQL.
-->

{Plain-language explanation for a reader who knows basic SQL and Kubernetes.}

### Essential terms

<!-- Keep this local list small. Do not create a page-specific glossary. -->

| Term | Meaning here |
|---|---|
| `{term}` | {One-sentence definition} |

## How it works internally

<!--
Start with invariants, then explain implementation detail. Cover the applicable
items: state/data structures, ownership, lifecycle, persistence, coordination,
acknowledgement, retry, and concurrency.

For every statement, know whether it is an upstream invariant, a repository
fact, a live observation, an inference, or a reference/planned claim.
PostgreSQL 18 changed behavior in several areas (asynchronous I/O, skip scan,
eager freezing); cite the PG 18 documentation beside any claim those changes
touch.
-->

### Invariants

- {Invariant that remains true across the mechanism's normal operation.}
- {Guarantee the mechanism provides.}
- {Guarantee the mechanism does not provide.}

### Lifecycle or sequence

{Walk through the state transition or data path in causal order. Name what is
read, written, flushed, acknowledged, queued, replayed, or reclaimed at each
step.}

<!--
Add Mermaid only when it materially clarifies topology, lifecycle, sequence,
ownership, or failure propagation. One diagram answers one question.

Use the palette and state-label rules in AGENTS.md. Prefer:
- flowchart for topology or ownership;
- sequenceDiagram for commit, replication, or acknowledgement timing;
- stateDiagram-v2 for tuple, transaction, or recovery lifecycle.

Render the diagram and inspect it. Never rely on color alone. Planned or
reference state must appear in the node or edge label.
-->

### What to notice

<!-- Required after a diagram; omit this heading when the page has no diagram. -->

- {The relationship the diagram makes visible.}
- {The tempting but incorrect conclusion the diagram does not imply.}

## How homelab uses it

<!--
Separate generic PostgreSQL mechanics from deployment-specific facts. Link the
smallest canonical source (Cluster manifest GUC block, pooler HelmRelease,
monitoring-queries ConfigMap, alert rule). Do not copy large manifest blocks.
-->

| Upstream mechanism | Homelab setting or behavior | Evidence | Class/status |
|---|---|---|---|
| {Generic behavior} | {Deployed value or explicit absence} | {Descriptive link or live evidence ID} | {Repository fact / Live observation / Reference — not deployed / Planned} |

Explain why the deployed setting matters to the mechanism. Do not turn this
section into a configuration inventory.

## Observe it on the live cluster

<!--
This is one embedded evidence lab, not a general runbook. It must be bounded,
repeatable, read-only, and useful for testing the mental model above.

Record:
- observation time and timezone;
- repository SHA when relevant;
- Kubernetes context/cluster;
- SELECT version();
- CNPG cluster, instance pod, and its role (primary / sync standby /
  async standby / DR designated primary);
- database;
- exact query and abbreviated output;
- interpretation and limits, including the last reset time of any cumulative
  pg_stat_* counter you cite.

Never include credentials or Secret values. Never promise exact dynamic values.
Do not use SELECT * in durable labs. If the observation needs an extension that
is not installed (pageinspect, pg_buffercache, pg_visibility, pg_walinspect) or
file access such as pg_waldump, move it to a disposable lab and label it.
-->

### Prerequisites and safety

- Connect with `kubectl cnpg psql {cluster}`{, adding `--replica` for a standby};
  never through PgDog or PgBouncer.
- Open with the [safe session header](../observability-and-troubleshooting.md#safe-session-header)
  and `SET default_transaction_read_only = on;`.
- Confirm the kubeconfig context, the instance pod, and its role before reading.
- Run only the read-only commands shown below.

### Query

<!-- Commands and output always use separate, language-tagged fences. -->

```sql
SELECT
    {named_column},
    {named_column}
FROM {catalog_or_stat_view}
WHERE {bounded_filter}
ORDER BY {stable_order}
LIMIT {bounded_limit};
```

### Observed example

<!--
Use an abbreviated real result, not invented output. Replace identifying or
sensitive values if necessary and say what was sanitized.
-->

```text
{captured output}
```

Observation context:

| Field | Value |
|---|---|
| **Observed at** | `{YYYY-MM-DD HH:MM TZ}` |
| **Repository** | `{git SHA}` |
| **Cluster/context** | `{safe kubeconfig context}` |
| **PostgreSQL** | `{SELECT version() result}` |
| **Cluster/instance/role** | `{cnpg cluster / pod / primary or standby kind}` |
| **Database** | `{database}` |

### How to read the result

| Field or relationship | Interpretation | What it cannot prove |
|---|---|---|
| `{field}` | {What the observed value means} | {Limit of inference} |

### What to notice

- {Observation that confirms or challenges the mental model.}
- {Dynamic value that must not be treated as a platform constant.}

## Failure modes and trade-offs

<!--
Explain engine behavior, signals, and boundaries. Link task-focused recovery
steps to the databases runbooks and per-alert runbooks instead of duplicating
them. Failure behavior that was never induced on this platform is an upstream
invariant or an inference, never a live observation.
-->

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| {Failure or pressure} | {State transition or queued work} | {Impact} | {Catalog view, metric, alert, or log} | {Safe boundary and trade-off} |

State which invariant still holds during the failure and which guarantee is
temporarily unavailable. Separate measured current behavior from hypothetical
scale behavior.

## Misconceptions and challenge questions

<!--
Challenge category errors, not trivia. Each answer must be present in this page
or linked directly to the section that owns it.
-->

### “{Plausible but incorrect claim}”

{Concise correction, mechanism, and evidence.}

### Challenge: {new scenario}

{Question that requires predicting the mechanism rather than repeating a
definition.}

**Model answer:** {Short answer with a link to the relevant section if needed.}

## Teach-back checklist

Before continuing, explain these without rereading the chapter:

- [ ] {The mechanism in your own words.}
- [ ] {What is persisted, where it is persisted, and who owns it.}
- [ ] {The predicted result of one failure or retry scenario.}
- [ ] {One real output row and the limit of what it proves.}
- [ ] {The main cost or trade-off of this mechanism.}

## Related documentation

<!--
Link canonical in-repo owners. Use descriptive link text. Keep “read next” to
five deliberate choices or fewer.
-->

- {Canonical platform or operations page}
- {Previous or next learning chapter}

## References

<!--
Use current primary sources: the PostgreSQL 18 documentation, PostgreSQL
source code, or CloudNativePG documentation. Put citations next to
version-sensitive claims in the body as well as listing the source here.
-->

- {Official primary source}

---
_Last updated: YYYY-MM-DD — {what changed, not only the date}._

## Review gate — do not copy into the published chapter

### Purpose and progression

- [ ] The hook, audience, prerequisites, scope, and learning questions are explicit.
- [ ] The chapter follows mental model → mechanism → platform evidence → observation → failure reasoning → teach-back.
- [ ] A junior can stop after the observation with a correct model; an experienced reader still gets mechanisms and trade-offs.
- [ ] The page answers one owning question and links adjacent owners.

### Accuracy and evidence

- [ ] Generic PostgreSQL behavior and homelab behavior are visibly separated.
- [ ] Every non-trivial claim has the correct evidence class and source.
- [ ] Version-sensitive behavior cites the PostgreSQL 18 documentation beside the claim, including areas PG 18 changed (asynchronous I/O, skip scan, eager freezing).
- [ ] Deployed facts link the manifest, GUC block, ConfigMap, alert rule, or canonical platform page.
- [ ] Live observations include timestamp, version, context, cluster, instance pod, role, and database.
- [ ] Inferences name both their supporting evidence and their limit.
- [ ] Dynamic output is labelled as an observed example, not an expected constant, and cumulative counters name their reset time.

### Lab safety and usefulness

- [ ] The observation is read-only, bounded, repeatable, and tested on the target Ubuntu Kind cluster.
- [ ] The lab connects via `kubectl cnpg psql`, not a pooler, and opens with the safe session header plus `default_transaction_read_only = on`.
- [ ] Commands and output use separate language-tagged fences and contain no shell prompt.
- [ ] Queries name columns instead of using `SELECT *`.
- [ ] No credential, Secret value, DSN, or sensitive environment output appears.
- [ ] Anything needing an uninstalled extension or data-directory access is a labelled disposable-lab exercise, not a shared-cluster command.
- [ ] The text explains what each important field proves and cannot prove.

### Diagrams and writing

- [ ] Every diagram answers one named question, uses repository semantics, and renders without clipping or ambiguous crossings.
- [ ] State is carried by text labels, not color alone, and equivalent prose follows the diagram.
- [ ] Headings use sentence case; prose uses active voice, direct English, and one main idea per paragraph.
- [ ] Acronyms and specialist terms are defined on first use.
- [ ] The page avoids “easy”, “simple”, “just”, “currently”, and unexplained jargon.
- [ ] Links use descriptive text rather than “here” or raw URLs.

### Integration

- [ ] The learning hub links the published chapter and previous/next navigation is correct.
- [ ] The absorbed page(s) are deleted and every inbound link is repointed in the same pull request.
- [ ] Existing canonical explanations, runbooks, and DR documents are linked rather than copied.
- [ ] Changed Mermaid blocks render and receive visual inspection.
- [ ] Markdown links, fences, and repository validation pass.
