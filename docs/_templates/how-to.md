<!--
How-to template (ADR-083 contract: "How do I accomplish or recover from this
task?"). Copy the file, replace every {placeholder}, and delete all author
comments and the review gate before publishing.

A how-to serves a reader who already knows the platform and has a task:
rotate a credential, add a database, promote a replica, change a limit. It is
not an alert runbook (those use docs/observability/runbooks/_TEMPLATE.md) and
not a tutorial (it assumes the reader, so it explains less and verifies more).
Keep the title as the task in sentence case.
-->

# {Do the task}

<!-- One sentence: the goal and the state the platform is in afterwards. -->

{What this procedure changes and the observable end state.}

| Quick facts | |
|---|---|
| **Page type** | How-to |
| **Audience** | {Practitioner / Operator} |
| **Prerequisites** | {Access, tools, pages that explain the mechanism} |
| **Environment** | {Kind / local-stack / both} |
| **Changes state** | {Yes — list what; or No} |
| **Approval** | {None / owner approval before step N, per [homelab-troubleshooting](../../.agents/skills/homelab-troubleshooting/SKILL.md)} |
| **Deployment status** | {Deployed / Planned — owning Accepted record} |
| **Evidence context** | {Repository SHA and date of the run behind the outputs below} |
| **This page owns** | {This task} |
| **Not this page** | {The explanation page for the mechanism; the runbook for the alert} |

## Goal

{The outcome in one or two sentences, with the check that proves it.}

## Assumptions

<!-- Each line is checkable. Say what to read if one does not hold. -->

- {Condition, and the command that confirms it.}
- {Condition.}

## Steps

<!--
Numbered steps, one imperative action each. Command and output in separate,
language-tagged fences. Put the condition before the instruction ("If the
pooler is …, then …"). Mark state-changing commands with
`<!-- example-policy: ephemeral -->` or `review-only`. Fix in Git and let Flux
reconcile; never `kubectl apply` over Flux.
-->

1. {Action.}

   <!-- example-policy: ci-safe -->
   ```bash
   {command}
   ```

   ```text
   {abbreviated real output}
   ```

   {What the output must show before the next step.}

2. {Action.}

3. {Action.}

## Verify

<!--
The checks that prove the goal, from a second angle when possible: the
object's status, the metric, the request that now succeeds.
-->

```bash
{verification command}
```

```text
{expected output, real and abbreviated}
```

## If something goes wrong

<!--
Symptom-first table. State a cause only when evidence supports it; when two
causes share a symptom, name the check that distinguishes them.
-->

| What you see | What to do |
|---|---|
| {Observable failure or error text} | {Imperative fix, with the cause folded in through "because"} |

## Related

- [{Explanation of the mechanism}]({link}) — why the steps are in this order.
- [{Reference}]({link}) — the fields and defaults this task touches.
- [{Runbook}]({link}) — when the alert for this component fires.

<!--
## Review gate — delete before publishing

- [ ] Every command was run on the stated environment and date; outputs are
      real and abbreviated.
- [ ] State-changing steps are marked, have an approval note when needed, and
      are reversible or say they are not.
- [ ] "Verify" proves the goal, not just that the command returned.
- [ ] Failure rows name a check, not a guess.
- [ ] No `kubectl apply` over Flux; no secret or default password.
- [ ] `scripts/docs-check.sh <this file>` exits 0.
-->
