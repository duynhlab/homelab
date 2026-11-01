# Editing workflow

## Triage the edit

Choose the smallest effective change:

| Level | Signal | Action |
|---|---|---|
| Quick fix | Wrong command, broken link, typo, stale name or path | Correct the affected text |
| Copy edit | Ambiguous wording, weak hierarchy, inconsistent terms | Improve clarity without changing scope |
| Structural edit | Missing stage, missing failure mode, misplaced content | Reshape the affected page |
| Rewrite | The page no longer serves its primary job | Follow [Write a new page](#write-a-new-page) |

Frequency ranks work, but severity also matters. One wrong `kubectl delete`,
one secret in a snippet, or one planned feature described as deployed is a
high-priority correction on its own.

## Preserve context

Before editing:

- Read the full page and its hub.
- Search for inbound links and for the same claim on other pages.
- Keep heading anchors when possible; `docs/` links target them.
- Decide whether the request is a docs gap, a platform gap, or both. A
  platform gap becomes an issue, not a sentence that documents a workaround.
- Identify the exact manifest, record or observation that verifies each
  changed claim.

## Edit around the reader's task

- Keep the established shape unless it blocks the task.
- Make the deployed happy path primary; alternatives follow it.
- Put a limitation next to the workflow it constrains.
- Put troubleshooting on the page that owns the failing workflow.
- Prefer one focused example over a new page.
- Replace change narration with the resulting state; move the history to
  CHANGELOG or the owning record if it is not already there.
- Cut while you edit: merge restated sentences, move option lists into
  tables, drop internals the reader cannot act on.
- Leave strong prose and unrelated sections alone.

When an incident or a chat drove the edit, reduce it to the reader's problem
first. Do not quote the discussion or expose the debugging history unless it
helps the reader act.

## Verify

Check each changed claim against the source order in
[SKILL.md § Verify before writing](../SKILL.md#verify-before-writing). Run
changed commands and queries on Kind or local-stack. For an upstream default
or limit, query Context7. If a behaviour is still unsettled, document only the
stable boundary and report the open question to the owner.

## Check adjacent content

Search for:

- Contradictory statements on other pages.
- Old names, paths, flags or alert names.
- Pages that describe the same workflow.
- Links to a heading you changed.
- Reference rows that need the same limitation.
- The hub row and `docs/README.md` entry for a page you added or renamed.

## Write a new page

1. **Research the task.** What the reader must accomplish, where the task
   begins and ends, which manifests and records verify it, which pages
   overlap, and which failures are known.
2. **Choose one shape and one job** from [page-shapes.md](page-shapes.md),
   and confirm the page passes the create-a-page test there.
3. **Outline first.** Write the headings in the reader's order: outcome or
   definition, prerequisites or boundaries, deployed path, alternatives,
   limitations, related tasks. Drop a heading that adds nothing.
4. **Draft and verify together.** Verify each command, name and value before
   adding it. Separate deployed behaviour from planned work with the labels
   in [style-rules.md § Homelab terms](style-rules.md#homelab-terms).
5. **Self-edit.** Remove repetition, filler, unsupported qualifiers and
   internals the reader cannot act on. Confirm each section reads on its own.
6. **Link it in.** Add the row in the area hub and in `docs/README.md`.
