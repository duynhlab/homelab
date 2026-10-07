# ADR-NNN: {Imperative decision title}

<!--
Template v3: one decision, not a topic or implementation plan.
Aim for 1–2 readable pages, not a hard limit. Delete authoring comments.
See ../README.md for optional extensions and lifecycle rules.
-->

> **Decision summary:** We will {decision} because {decisive reason}. We accept
> {main cost or limitation} in exchange for {main benefit}.

| Attribute | Value |
|-----------|-------|
| **Status** | Proposed |
| **Decision date** | — |
| **Owner** | {person or team responsible for the record} |
| **Deciders** | {people who accept the decision} |
| **Adoption** | Not started |

<!--
Status and Adoption are independent; Accepted does not mean deployed.
Use Adoption: Not started / Partial / Complete.
Add RFC, research, tracking, affected-component or supersession links only when
relevant, here or in References. Omit unused metadata rather than filling dashes.
-->

## Context

{What problem or change makes a decision necessary now? State the scope,
constraints and most important drivers without announcing the chosen option.}

<!--
Distinguish observed facts from assumptions and unknowns; cite evidence with
its scope/date when available. Do not invent measurements.
For a learning-driven homelab choice, state learning value honestly rather
than presenting it as a production requirement. Link lengthy research.
-->

## Decision

We will {specific choice and architectural boundary} because {why it best
satisfies the decisive constraint compared with the closest alternative}.

{State any durable ownership, failure or compatibility rule needed to judge
compliance. Explain why the benefit warrants the additional cost.}

<!--
Add a rules list/table only when prose is insufficient.
Use a small Mermaid diagram only if it clarifies this decision.
-->

## Alternatives considered

{Describe the credible options actually considered and the concrete trade-off
that ruled each out, especially the closest alternative.}

<!--
No fixed option count or mandatory table. Include keeping the current approach
or deferring the change when viable. Do not manufacture straw-man alternatives;
if only one option is viable, explain the constraint that excludes the others.
-->

## Consequences

- {Expected benefit in this context.}
- {Accepted cost, limitation or remaining risk, and mitigation if applicable.}

<!--
Do not force positive/negative/neutral subsections.
When an important assumption could invalidate the decision, state an observable
revisit condition here; use a separate Revisit triggers section only if useful.
-->

## Confirmation

{How will we confirm implementation follows this decision, and what observable
result permits Adoption: Complete? Link tracking and, once available, evidence.}

{Identify the owning docs/runbook to update. API-touching decisions update
docs/api contracts; infrastructure decisions update the relevant platform docs.}

<!--
Choose relevant checks, e.g. manifest review, gateway route/contract tests,
database constraints or a failure drill. A planned test is not a passed test.
For phased work, add an obligations table (owner/tracking/completion signal);
keep the rollout schedule and detailed test output in their owning records.
-->

## References

<!-- Link only applicable RFC/research, alternatives evidence, contracts,
tracking and runbooks. No placeholder links or empty rows in a finished ADR. -->

- {Relevant source or owning-document link.}

## History

<!--
Record lifecycle/adoption milestones and important evidence only; editorial
changes belong in Git/PR history. Add acceptance/adoption rows when they happen.
After acceptance, preserve Context, assumptions, rationale and trade-offs.
Append new evidence with its scope/date, not as if known at acceptance. Typos, links, Adoption
and lifecycle annotations may change; a changed decision needs a new ADR with
Supersedes and a reciprocal Superseded by link on this record.
-->

| Date | Status / adoption | Change |
|------|-------------------|--------|
| YYYY-MM-DD | Proposed / Not started | Initial proposal |
