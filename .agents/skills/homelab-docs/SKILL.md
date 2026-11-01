---
name: homelab-docs
description: >-
  Write, edit, review, or audit documentation in the homelab repository:
  pages under docs/, runbooks, area hubs and README files. Use for a new
  page, a correction, a restructure, a docs review, or a request to make a
  page clearer, shorter, or less AI-sounding, while verifying every claim
  against the manifests, the running cluster, and the owning record.
metadata:
  version: "1.0.0"
---

# Homelab docs

Write accurate, task-focused documentation for the platform. The readers are
operators, service authors and AI agents: each section must scan in seconds,
stand on its own when retrieved, and leave no unstated context.

This skill owns how a page is written, edited and reviewed. The repository
conventions it builds on stay in their owners and are not restated here:

- [AGENTS.md § Docs conventions](../../../AGENTS.md#docs-conventions): English,
  Mermaid by default, the house shape, **planned** vs deployed, synthesize
  without third-party links, one hub per area, history and evidence rules.
- [AGENTS.md § Diagram workflow](../../../AGENTS.md#diagram-workflow) and
  [homelab-drawio](../homelab-drawio/SKILL.md) for diagrams.
- [homelab-proposals](../homelab-proposals/SKILL.md) for research, RFC and
  ADR files; they have their own templates and gates.
- [git-pr](../git-pr/SKILL.md) for the commit and PR text, and for the
  sentence rules that commit bodies and pages share.

## Choose a workflow

- New page or full rewrite: [references/page-shapes.md](references/page-shapes.md)
  to pick the shape, then the writing order in
  [references/editing-workflow.md § Write a new page](references/editing-workflow.md#write-a-new-page).
- Targeted or structural change: [references/editing-workflow.md](references/editing-workflow.md).
- Before finishing any change: [references/review-framework.md](references/review-framework.md).
- Terms, formatting, commands, tables: [references/style-rules.md](references/style-rules.md).
- Wording, voice, AI patterns: [references/prose-quality.md](references/prose-quality.md).

## Verify before writing

Do not rely on memory for platform behaviour. Use this source order, and cite
the source beside the claim when the page records evidence:

1. The manifests: `kubernetes/**`, `local-stack/**`, `terraform/**`, and a
   running Kind or local-stack when the claim is about runtime behaviour.
2. [`docs/api/`](../../../docs/api/README.md) for routes, payloads and
   service ownership. It is normative; service READMEs are not.
3. `CHANGELOG.md` and merged PRs for what shipped and when.
4. RFCs and ADRs **by status**. `Accepted` is a decision, not a deployment;
   read the ADR's Adoption row and the RFC's Implementation History.
5. Issues, PR threads and chats for the reader's problem, never for behaviour.

For upstream tool behaviour (Flux, CNPG, ClickHouse, VictoriaMetrics, Envoy
Gateway and the rest), query Context7 before stating a version, default or
limit. A claim with no source is omitted or reported as a gap, never guessed.
Never leave a `[VERIFY]` marker in a finished page.

## Write for the task

- Lead each page and section with the answer, the definition, or the outcome.
- Address the reader as `you`; use imperative verbs for steps.
- One page, one primary job. Extend the page that owns a task before creating
  a new one; [references/page-shapes.md § Create a page](references/page-shapes.md#decide-whether-to-create-a-page)
  has the test.
- Happy path first, then alternatives, then failure modes.
- Write self-contained sections: repeat the full noun instead of a pronoun in
  a key statement, and keep the critical fact on the page rather than only
  behind a link.
- Label every not-deployed thing by its record's status, as AGENTS.md's
  diagram table does: **planned** (Accepted, not applied), **planned —
  ADR-NNN, not installed** (Proposed), **reference — not deployed**.
- State a limitation once, on the page that owns it, and link to it.

## Avoid common failures

- Describing a target state, a research shape or an Accepted-but-unapplied
  decision as current behaviour.
- A command or query that was not run on Kind or local-stack, or output that
  was not observed.
- Pasting a password, token or key, even a local-stack default. Use a
  placeholder.
- Embedding a third-party article or a comparative platform. Synthesize it;
  official product docs belong in § References only.
- Narrating the change instead of describing the result: `no longer`,
  `previously`, `has been removed`. The boundary with evidence records is in
  [references/style-rules.md § Current state and records](references/style-rules.md#current-state-and-records).
- Rewriting clear prose to match a preference, or normalizing text the
  request did not touch.
- Promotional language, rhetorical questions, filler, and claims that a task
  is easy, simple or quick.

## Finish the change

1. Re-read every changed page in full.
2. Verify each new technical claim against its source from the order above.
3. Search for contradictory statements and links to changed headings.
4. Confirm a new page has an inbound body link from its area hub and from
   [`docs/README.md`](../../../docs/README.md), in the same change.
5. Render every changed Mermaid block (AGENTS.md § Diagram workflow).
6. Run the [review framework](references/review-framework.md), then the
   [prose pass](references/prose-quality.md) when wording changed.
7. Run `make validate`; CI checks the Markdown links on the changed files.
