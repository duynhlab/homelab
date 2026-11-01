# Review framework

Run the passes in order. Fix blockers and major issues before style nits.
Leave clear, correct prose unchanged.

## Pass 1: Purpose and structure

- Does the page have one primary job?
- Does the opening lead with the outcome or the definition?
- Does the page follow its shape from [page-shapes.md](page-shapes.md), with
  the deployed path before variants and edge cases?
- Does the heading order match the reader's workflow?
- Does the content belong on this page rather than on the owner page?

## Pass 2: Accuracy

- Do commands, queries, paths and names match the manifests and the running
  cluster?
- Does every not-deployed thing carry its status label, and does the label
  match the record's current status?
- Does any statement describe a research shape or an Accepted decision as
  current behaviour?
- Does any statement narrate history instead of the resulting state?
- Does the page describe what the reader configures and observes, not the
  controller's internals?
- Do upstream claims (versions, defaults, limits) have a Context7 or official
  source?
- Does `docs/api/` still agree when the page touches a contract?

**Blockers:** a wrong or unverified command, a planned thing described as
deployed, a page that contradicts its manifest, a secret or password in a
snippet, a third-party article embedded in the body.

## Pass 3: Completeness

- Can the reader complete the deployed happy path?
- Are prerequisites and environment assumptions stated (Kind, local-stack,
  both)?
- Are the known failure modes covered, with the check that distinguishes
  them?
- Does troubleshooting say what to inspect next?
- Are platform gaps separated from docs guidance and tracked as issues?

## Pass 4: Style and retrieval

- Are names exact and terms consistent with manifests and output?
- Do sentences follow the git-pr sentence rules?
- Does each section lead with its key fact, and does each heading work as a
  search result?
- Is the critical fact on the page, not only behind a link?
- Are options and outcomes in tables or example comments rather than long
  paragraphs?
- Is the prose free of promotional words, rhetorical questions, filler and
  mechanical rhythm ([prose-quality.md](prose-quality.md))?
- Did the edit preserve the author's meaning, nuance and uncertainty?

## Pass 5: Diff discipline

- Does every changed sentence fix an accuracy, usability, structure or style
  problem?
- Did the edit preserve unrelated content and heading anchors?
- Did it create a contradiction elsewhere?
- Is every new file necessary, and linked from its hub and `docs/README.md`?
- Did every changed Mermaid block render?
- Is the page shorter or the same length, unless it added required
  behaviour?

## Reporting a review

For a review-only request, report findings with a clickable file and line,
ordered blockers first. Give the corrected text for each finding. Do not
assign a score, and do not claim to know whether a tool wrote the text.
