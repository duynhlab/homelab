# Teaching

Apply this reference to a tutorial, an explanation, or a learning chapter:
any page whose reader is raising their level rather than looking something up.
The owner reads these pages to learn how the platform works, so a page that
only records a fact is worth less than one that lets the reader reproduce it.
The shapes live in [`docs/_templates/`](../../../../docs/_templates/README.md);
this file says how to fill them so that they teach.

## Build the page in layers

- Open with the smallest example that produces an observation on Kind or
  local-stack. The reader who stops after it holds a correct, if partial,
  model.
- Add one idea per section. When a section needs two headings to explain
  itself, it is two sections.
- Order the ideas basic → complex, and the deployed path before alternatives.
  Put a limitation next to the idea it constrains, not in a list at the end.
- Use the platform's own components as the worked example: the order saga,
  `product-db`, the `apps-local` wave, an `EdgeRequestLatency` alert. A
  generic example teaches the mechanism; the platform example also teaches
  where to look.
- Reuse the reading depths from the learning hubs and say which section
  serves which depth when the page is long:

  | Depth | Reads through | Can afterwards |
  |---|---|---|
  | Foundation | Mental model | Define the terms and describe the mechanism |
  | Practitioner | Mechanism + platform evidence | Map the model to the manifests and the data path |
  | Operator | Observation + failure modes | Read real evidence and name the failing layer |
  | Mastery | Challenges + teach-back | Predict behaviour in a new scenario and defend the trade-off |

## Open with outcomes

- State what the reader can do afterwards as observable verbs: run, read,
  find, change, recover, predict. "Understand" and "learn" say nothing the
  reader can check.
- Three to five outcomes. A page with more is two pages.
- The hook before the outcomes names the situation where the reader meets
  this mechanism on this platform: an alert, a stuck wave, a slow query.

## Write a step

Every step in a tutorial, and every observation in an explanation, has the
same shape, in this order:

1. **Action**: one imperative sentence, with the condition first when there is
   one.
2. **Command**: a `bash`, `sql`, `promql` or `logsql` fence. Placeholders for
   anything the reader substitutes. A state-changing command carries an
   `<!-- example-policy: ephemeral -->` or `review-only` marker on the line
   before the fence.
3. **Output**: a separate `text` fence with the real, abbreviated output, and
   the environment and date it was observed (the quick-facts Evidence context
   row, or a line beside the fence).
4. **What to notice**: the field or line that carries the result, what its
   value means, and the tempting wrong reading when there is one.
5. **Checkpoint**: the one condition that must hold before the next step, and
   the one check that tells the reader what went wrong when it does not.

Never invent output. When the real output is not stable, show the shape with
the unstable values replaced and say so.

## Define before you use

- Define each term on first use, or link the area glossary. A reader who
  arrives at a section from search must not need the page above it.
- Keep a local "Essential terms" table small; do not create a page-specific
  glossary.
- An analogy is allowed only when it is precise, and the next sentence names
  where it stops matching the real system.
- Repeat the full noun in a key statement instead of "it" or "this".

## Diagrams

- One Mermaid diagram answers one question, in the AGENTS.md palette; planned
  nodes carry the word planned.
- The mental model comes before the first diagram, in prose.
- Every diagram is followed by **What to notice**: the relationship it makes
  visible, and the wrong conclusion it does not support.

## Callouts

GitHub renders `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]` and `> [!CAUTION]` as
alerts. Use one only for:

- a deviation from the behaviour the reader expects from upstream docs;
- a command that changes state or needs approval.

A few per page at most. A callout that restates the paragraph above it is
removed.

## Close with a next step

- End with **Next steps**: one or two links in reading order, each with what
  it adds. End on the link, not on a summary.
- A learning chapter also ends with challenge questions, each with a model
  answer, and a teach-back list, as its series template requires.
- A tutorial ends with **Clean up** before the next steps, so the reader's
  environment matches the starting state of the next page.

## Check that it teaches

Before the review passes in [review-framework.md](review-framework.md):

- Can the reader act after the first example?
- Is every term defined on this page or linked?
- Does each step carry a command, an output, and an observation?
- Does the order run basic → complex, with the deployed path first?
- Is there a next step, and does the hub link this page?
