<!--
Tutorial template (ADR-083 contract: "Can you help me achieve a first success?").
Copy the file, replace every {placeholder}, and delete all author comments and
the review gate before publishing.

A tutorial walks a reader who has never done this to one observable result,
on Kind or local-stack, in a safe sequence with a checkpoint after every step.
The reader can stop after any step and still hold a correct model. Teach with
the platform's own components (an order, a CNPG cluster, a Flux wave), not a
generic example. Keep the title in sentence case and name the result.
-->

# {Do one concrete thing}: {the result the reader will see}

<!--
Hook: one or two sentences on what the reader will have at the end and why it
matters on this platform. No "This tutorial covers".
-->

{What you will have built or observed, and the operational question it answers.}

| Quick facts | |
|---|---|
| **Page type** | Tutorial |
| **Audience** | {Foundation / Practitioner / Operator} |
| **Prerequisites** | {Pages read first; tools; access} |
| **Environment** | {Kind / local-stack / both; the `make` target that brings it up} |
| **Time** | {Minutes, measured on a run} |
| **Deployment status** | {Deployed / Planned — owning Accepted record} |
| **Evidence context** | {Repository SHA and date of the run that produced the outputs below} |
| **This page owns** | {The one result this tutorial produces} |
| **Not this page** | {The page that owns the mechanism, the reference, or the runbook} |
| **Next page** | {Title of the page to read after this one} |

## What you will do

<!--
Three to five outcomes the reader can observe or do afterwards. Use verbs the
reader can check: "run", "read", "find", "change", "recover". Avoid
"understand" and "learn".
-->

- {Run … and read … in the output.}
- {Find where … is configured and change it.}
- {Confirm … with …}

## Before you start

<!--
Everything the reader needs in place, each as a checkable line. State the
safe boundary: which commands change state and what to do if something is
already running.
-->

- {`make up` has finished and `kubectl get kustomizations -A` shows every wave `Ready`.}
- {Tool and version, with the command that proves it.}
- {Access or credential path, as a reference to where it lives, never the value.}

> [!NOTE]
> {The one deviation from expected behaviour the reader is likely to hit, if
> any. Delete the callout when there is none.}

## Step 1: {Imperative action}

<!--
Each step has the same shape: what to do, the command, the real abbreviated
output, what to notice in it, and a checkpoint. Keep commands and output in
separate, language-tagged fences. Mark a command that changes state with
`<!-- example-policy: ephemeral -->` or `review-only`; read-only commands are
`ci-safe`. Replace anything the reader substitutes with `$NAMESPACE`-style
placeholders.
-->

{One or two sentences on what this step does and why it comes first.}

<!-- example-policy: ci-safe -->
```bash
{command}
```

```text
{abbreviated real output}
```

**What to notice.** {The field or line that carries the result, and what its
value means. The tempting wrong reading, if there is one.}

**Checkpoint.** {A single observable condition that must hold before Step 2.
If it does not hold: the one check that tells the reader what went wrong.}

## Step 2: {Imperative action}

{Repeat the step shape. Each step adds one idea; a step that needs two
headings is two steps.}

## Step N: {Verify the result}

<!--
The last step shows the result the hook promised, from a second angle when
possible (a metric after a kubectl change, a row after a request).
-->

## Clean up

<!--
Return the environment to its starting state. Omit the section, not the
heading text, only when every step was read-only; say so in one sentence.
-->

```bash
{commands that undo the change}
```

## What you did

<!--
Restate the outcomes from "What you will do" as facts the reader now has,
with the mechanism named once and linked to the explanation page that owns it.
No summary paragraph beyond that.
-->

- {You ran … and read … — this is {mechanism}, explained in [{page}]({link}).}

## Next steps

<!-- One or two links in reading order. Say what each adds. -->

- [{Next page}]({link}) — {what it adds to this result}.
- [{Related reference}]({link}) — {when to open it}.

<!--
## Review gate — delete before publishing

- [ ] Every command was run on the stated environment on the stated date; the
      output is real and abbreviated, not invented.
- [ ] Every step has a command, an output, "What to notice", and a checkpoint.
- [ ] A reader who stops after Step 1 holds a correct, if partial, model.
- [ ] Each term is defined on first use or linked to the area glossary.
- [ ] No "easy", "simple", "quick", "just"; no secret or default password.
- [ ] State-changing commands carry an example-policy marker and appear in
      "Clean up".
- [ ] "Next steps" has one or two links; the hub and docs/README.md link here.
- [ ] `scripts/docs-check.sh <this file>` exits 0.
-->
