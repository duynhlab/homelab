# Page shapes

Pick the shape from what the reader needs, using the Diátaxis compass: does the
content inform **action** or **knowledge**, and does it serve **learning** or
**work**? Then use the homelab shape that owns that quadrant. Shapes order the
content a page has; they are not a list of sections to fill.

| Reader needs | Diátaxis type | Homelab shape | Model |
|---|---|---|---|
| Find the right page | — | Hub | [`docs/observability/README.md`](../../../../docs/observability/README.md) |
| Understand how a subsystem works here | Explanation | Architecture guide (house shape) | [`docs/observability/profiling/README.md`](../../../../docs/observability/profiling/README.md) |
| Act on an alert or incident | How-to | Runbook | [`MicroserviceDown.md`](../../../../docs/observability/runbooks/microservices/MicroserviceDown.md) |
| Look up a fact | Reference | Catalog or contract | [Alert catalog](../../../../docs/observability/alerting/alert-catalog.md), [`docs/api/_template-service.md`](../../../../docs/api/_template-service.md) |
| Learn a mechanism in depth | Tutorial or Explanation | Learning chapter | [`fundamentals/_template.md`](../../../../docs/databases/fundamentals/_template.md), [`internals/_template.md`](../../../../docs/observability/clickhouse/internals/_template.md) |
| Decide or record a decision | — | Research, RFC, ADR | [homelab-proposals](../../homelab-proposals/SKILL.md) |
| Promote accepted RFC research into an area guide (RFC process step 4) | Explanation | Domain doc, house shape | this skill; the RFC links it ([`rfc/README.md`](../../../../docs/proposals/rfc/README.md)) |

## Hub

A hub navigates; it does not explain. Open with one sentence on what the area
is, then a table or list of pages with one line each saying what the page
answers. Group by the reader's task, not by file location. Every page in the
area has one row. A hub holds no procedure and no fact that another page owns.

## Architecture guide

The house shape from AGENTS.md: hook → quick facts → concept → architecture →
platform behaviour → operations → references.

- **Hook**: two or three sentences on what the subsystem does here and why it
  exists. No preamble such as "This page covers".
- **Quick facts**: a two-column table of versions, backends, storage, defaults
  and the owning manifest, each with a path.
- **Concept**: the mental model in the reader's words, before any diagram.
- **Architecture**: one Mermaid diagram per question, labelled with the
  question it answers; planned nodes carry the word planned.
- **Platform behaviour**: what is deployed, with the manifest path beside each
  claim; limits and known gaps on this page, once.
- **Operations**: how to check it, where the alerts and runbooks are, how to
  change it safely.
- **References**: official product docs and the owning RFC or ADR.

## Runbook

The reader is on call and has the alert name. Copy
[`runbooks/_TEMPLATE.md`](../../../../docs/observability/runbooks/_TEMPLATE.md);
it owns the section order (header table, Meaning, Impact, Safety, Diagnosis,
Mitigation, Recovery validation, Escalation, Related). What each section must
do:

- **Meaning**: what the expression measures and what state fires it, in
  plain words. Say what does *not* fire it when that prevented noise before.
- **Impact**: link the alert catalog row instead of repeating it.
- **Safety**: which steps change state and need approval
  ([homelab-troubleshooting](../../homelab-troubleshooting/SKILL.md) owns the
  approval gates).
- **Diagnosis**: possible causes, then the commands and queries that
  distinguish them. Every command was run on Kind or local-stack. Use
  `$NAMESPACE`, `$APP` and `$POD_NAME` placeholders.
- **Mitigation**: numbered steps, one action each, keyed on the diagnosis.
- **Recovery validation**: the predicate false for two intervals and the user
  symptom gone.

A runbook names no cause the evidence does not support. When several causes
share a symptom, say which check tells them apart.

## Reference

A reference is neutral and complete: one row per thing, the same columns on
every row, exact names in code formatting. Derive a count from the source and
say how (the alert catalog's script is the model); never increment a number by
hand. When the thing has an owning record, link it in the row.

## Learning chapter

Copy the area's `_template.md` and keep its order: hook → quick facts →
questions the chapter answers → mental model → mechanism → homelab evidence →
bounded observation → review gate. Name the mechanism in the title. State the
deployment status in the quick facts and keep **reference — not deployed**
content clearly labelled.

## Decide whether to create a page

Create a page only when all four hold:

- The reader has a distinct goal or question.
- The behaviour is deployed, or has an Accepted record and is labelled planned.
- The content does not fit the page that already owns the topic.
- The page has enough substance to stand alone.

Otherwise add a section, a table row, a limitation, or a link to the owning
page. When you add a page, add its inbound links from the area hub and
`docs/README.md` in the same change.
