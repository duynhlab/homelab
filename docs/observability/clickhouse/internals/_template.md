<!--
Contributor template for every page in the ClickHouse internals learning path.
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

{One or two sentences connecting the mechanism to a query, failure, data part,
or operational decision the reader will recognize.}

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | {Foundation / practitioner / operator / mastery entry point} |
| **Prerequisites** | {Previous chapter names or specific concepts} |
| **Deployment status** | {Deployed / Reference — not deployed / Planned — owning accepted record} |
| **Platform scope** | {Database, table, component, signal, or topology} |
| **Evidence context** | {ClickHouse version; observed timestamp and timezone, or “Repository facts only”} |
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
where the analogy stops matching ClickHouse.
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
-->

### Invariants

- {Invariant that remains true across the mechanism's normal operation.}
- {Guarantee the mechanism provides.}
- {Guarantee the mechanism does not provide.}

### Lifecycle or sequence

{Walk through the state transition or data path in causal order. Name what is
read, written, acknowledged, queued, fetched, or replaced at each step.}

<!--
Add Mermaid only when it materially clarifies topology, lifecycle, sequence,
ownership, or failure propagation. One diagram answers one question.

Use the palette and state-label rules in AGENTS.md. Prefer:
- flowchart for topology or ownership;
- sequenceDiagram for query, insert, replication, or acknowledgement timing;
- stateDiagram-v2 for part, replica, or session lifecycle.

Render the diagram and inspect it. Never rely on color alone. Planned or
reference state must appear in the node or edge label.
-->

### What to notice

<!-- Required after a diagram; omit this heading when the page has no diagram. -->

- {The relationship the diagram makes visible.}
- {The tempting but incorrect conclusion the diagram does not imply.}

## How homelab uses it

<!--
Separate generic ClickHouse mechanics from deployment-specific facts. Link the
smallest canonical source. Do not copy large manifest or DDL blocks.
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
- database, table, and replica for replica-local system tables;
- exact query and abbreviated output;
- interpretation and limits.

Never include credentials or Secret values. Never promise exact dynamic values.
Do not use SELECT * in durable labs.
-->

### Prerequisites and safety

- Use the [secure ClickHouse client pattern](../operations.md#secure-client-pattern).
- Confirm the current context and the replica you will query.
- Run only the read-only commands shown below.

### Query

<!-- Commands and output always use separate, language-tagged fences. -->

```sql
SELECT
    {named_column},
    {named_column}
FROM {system_table}
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
| **Cluster/context** | `{safe context name}` |
| **ClickHouse** | `{SELECT version() result}` |
| **Database/table** | `{database.table}` |
| **Replica** | `{replica identity}` |

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
steps to operations/runbooks instead of duplicating them.
-->

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| {Failure or pressure} | {State transition or queued work} | {Impact} | {System table, metric, or log} | {Safe boundary and trade-off} |

State which invariant still holds during the failure and which guarantee is
temporarily unavailable. Separate measured current behavior from hypothetical
scale or multi-shard behavior.

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
Use current primary sources: official documentation, source code, specification,
or first-party paper. Put citations next to version-sensitive claims in the body
as well as listing the source here.
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

- [ ] Generic ClickHouse behavior and homelab behavior are visibly separated.
- [ ] Every non-trivial claim has the correct evidence class and source.
- [ ] Version-sensitive behavior cites a current official primary source beside the claim.
- [ ] Deployed facts link the manifest, DDL, or canonical platform page.
- [ ] Live observations include timestamp, version, context, database/table, and replica where applicable.
- [ ] Inferences name both their supporting evidence and their limit.
- [ ] Dynamic output is labelled as an observed example, not an expected constant.

### Lab safety and usefulness

- [ ] The observation is read-only, bounded, repeatable, and tested on the target Ubuntu Kind cluster.
- [ ] Commands and output use separate language-tagged fences and contain no shell prompt.
- [ ] Queries name columns instead of using `SELECT *`.
- [ ] No credential, Secret value, DSN, or sensitive environment output appears.
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
- [ ] Existing canonical explanations, audits, and runbooks are linked rather than copied.
- [ ] Changed Mermaid blocks render and receive visual inspection.
- [ ] Markdown links, fences, and repository validation pass.
