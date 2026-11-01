# Page templates

Every page in `docs/` serves one dominant reader contract
([ADR-083](../proposals/adr/ADR-083-documentation-steward/README.md)). Pick the
contract from the reader's question, copy its template, and remove the author
comments and the review gate before publishing. The
[homelab-docs skill](../../.agents/skills/homelab-docs/SKILL.md) owns how a
page is written and reviewed; this directory owns only the shapes.

| Reader question | Contract | Template | Area variants that already implement it |
|---|---|---|---|
| Can you walk me to a first success? | Tutorial | [`tutorial.md`](tutorial.md) | — |
| How do I accomplish or recover from this task? | How-to | [`how-to.md`](how-to.md) | Alert runbooks: [`runbooks/_TEMPLATE.md`](../observability/runbooks/_TEMPLATE.md) |
| What is the exact contract or value? | Reference | [`reference.md`](reference.md) | Service contracts: [`api/_template-service.md`](../api/_template-service.md) |
| Why does the system work this way? | Explanation | [`explanation.md`](explanation.md) | Learning chapters: [`databases/fundamentals/_template.md`](../databases/fundamentals/_template.md), [`clickhouse/internals/_template.md`](../observability/clickhouse/internals/_template.md) |

An area variant wins over the generic template when the page belongs to that
area's series. A hub (an area `README.md`) is navigation, not a contract: it
lists pages with one line each and follows the hub rules in the skill.

## What every template shares

- A quick-facts table that states the audience, prerequisites, deployment
  status, evidence context, and the one question the page owns.
- Observable outcomes instead of "understand" or "learn".
- A command and its output in separate, language-tagged fences, with the
  environment and date the output was observed.
- Terms defined on first use; an analogy names where it stops matching.
- A **Next steps** section that points to one or two pages in reading order.
- A review gate at the end that the author deletes before publishing.

## Executable examples

ADR-083 classifies a fenced command with an HTML marker on the line before
the fence:

```markdown
<!-- example-policy: ci-safe -->
```

Allowed values are `ci-safe`, `ephemeral`, and `review-only`; a missing marker
means `review-only`. Destructive commands, production access, secret rotation,
Flux reconciliation, and real-data mutation are always `review-only`. No CI
job executes examples yet, so the marker records intent for the reader and
for a future check.

## Before publishing

Run `scripts/docs-check.sh <file>` (links and anchors, fence tags, Mermaid
render, token patterns, inbound links), then the review passes in
[homelab-docs § review framework](../../.agents/skills/homelab-docs/references/review-framework.md).
