# Style rules

## Names and capitalization

- Use sentence case for headings.
- Match product, resource and object names exactly: `CloudNativePG`,
  `VictoriaMetrics`, `PgDog`, `homelab-ca`, `product-db`, `flux-system`.
- Write Kubernetes kinds as they appear in manifests: `HelmRelease`,
  `Kustomization`, `ResourceSet`.
- Use American English and the Oxford comma.

## Voice

Follow the sentence rules in [git-pr § Writing style](../../git-pr/SKILL.md#writing-style):
active voice, one topic per sentence, 25 words for a description and 20 for a
step, one meaning per term. In addition:

- Address the reader as `you` when the reader acts; use imperative verbs for
  steps.
- Put the condition before the instruction: "If the pod is CrashLoopBackOff,
  read its last log", not the reverse.
- Use neutral, instructional language. Avoid `easy`, `simple`, `quick`,
  `just`, `simply`, `obviously`, `leverage`, `robust`, `seamless`.
- Use `we` only for a deliberate decision by the platform owner, and prefer
  naming the record that made it.

## Homelab terms

Each term has one meaning. Use the term in code formatting when the reader
types it or reads it in output, and explain it the first time it appears on a
page.

| Term | Meaning on a page |
|---|---|
| deployed, as-built | Present in the manifests and observed on a cluster or local-stack |
| **planned** | Decided in an Accepted record, not yet applied; name the record |
| **planned — ADR-NNN, not installed** | Proposed under an Accepted RFC; direction set, decision open |
| **reference — not deployed** | A shape explored in research only |
| Accepted | An RFC or ADR decision status. It says nothing about deployment |
| Adoption | The ADR row that tracks shipping: `Not started`, `Partial`, `Complete` |
| gate | A check that must pass before a step: `make validate`, the research review gate, the E2E audit |
| wave | One Flux Kustomization in the `dependsOn` chain |
| pooler | The connection pooler in front of a CNPG cluster (PgDog on `product-db`) |
| DR replica | The `product-db-replica` cluster; off on Kind by local patch |
| contract | The normative API description in `docs/api/`; code and manifests are evidence |

## Current state and records

Guides, hubs, references and runbooks describe the resulting system. Do not
narrate how it changed: avoid `no longer`, `previously`, `has been removed`,
`renamed`, `legacy`, and `now` used as a change marker. Release changes go in
`CHANGELOG.md`; design rationale goes in the owning RFC or ADR.

Keep, per [AGENTS.md § Documentation history and evidence](../../../../AGENTS.md#documentation-history-and-evidence):

- Dates on decisions, incidents, releases and measurements.
- Verification records beside the claim they support: scope, date, source or
  environment and version, evidence reference.
- RFC and ADR lifecycle metadata, and Implementation History entries.

A runtime state is not change narration: "the replica is no longer in
recovery" is fine.

## Density

- Open a page with what the thing is and where it lives.
- Keep one fact per paragraph, in one to three sentences.
- State a default as what to omit: "Omit `wait` when the wave lists
  `healthChecks`."
- Name the exact value: the alert name, the status code, the label, the
  field path, the error string.
- Fold a reason in with `because` or `so`, and keep it only when the reader
  needs it to act.
- When several items share one rule, list them in one sentence.
- Cut a sentence that restates the previous one, or lists what a thing does
  not do, unless it prevents a likely mistake.

## Contract, not mechanism

Document what the reader configures and observes: the field, the default, the
limit, the error, the alert. Leave out the controller's internals unless the
reader needs them to configure, debug, or reason about a limit, and then
describe only the part they act on. A Flux gotcha such as `wait` disabling
`healthChecks` is a limit the reader acts on; the kstatus algorithm behind it
is not.

## Formatting

- Inline code for commands, flags, paths, resource names, labels and literal
  values.
- Bold for a critical fact or an interface label, not for routine emphasis.
- A language identifier on every fenced block: `bash`, `promql`, `logsql`,
  `sql`, `yaml`, `mermaid`.
- Descriptive link text; never `here` or a bare URL in prose.
- Relative links inside the repository, so CI can check them.

## Commands and queries

- Every command, query and expected output was run on Kind or local-stack, or
  the page says it was not.
- One canonical example per concept; add a variant only for a different task.
- Placeholders for anything the reader substitutes: `$NAMESPACE`,
  `<RFC-NNNN>`, `your_token_here`. Never a real secret, including a
  local-stack default password.
- Pass a password through stdin, a file, or `--ask-password`; never on the
  command line.
- Show real error text when the reader will meet it, followed by the fix.
- Do not invent expected output. Show it only when it is stable and useful.

## Lists and tables

- Numbered lists for ordered procedures; bullets for unordered items.
- Start each step with one imperative action.
- Tables for lookup: options, fields, identifiers, outcomes, symptoms. Keep
  the column schema the same on every row and the cells short.
- Complete sentences with periods when a list item explains something.

## Troubleshooting

When several failures share a workflow, use a symptom-first table:

| What you see | What to do |
|---|---|
| The observable failure or error text | The imperative fix, with the cause folded in through `because` |

State a cause only when evidence supports it. When several causes produce the
same symptom, say which check distinguishes them.
