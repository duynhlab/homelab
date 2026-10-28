# Docs hygiene — cleaning up debug and troubleshooting notes

Cleanup mode consolidates stray debug/troubleshooting/known-issue scribbles into
the one place that already owns them, **without erasing operational evidence**.
Follow [AGENTS.md § Documentation history and evidence](../../../../AGENTS.md#documentation-history-and-evidence)
and [§ Manifest comments](../../../../AGENTS.md#manifest-comments).

## Four-way disposition

Classify every note you touch into exactly one disposition:

| Disposition | When | Action |
|-------------|------|--------|
| **Retain in place** | Describes a *current*, non-obvious constraint, reason, or consequence beside the thing it governs | Leave it; tighten wording only if it merely restates the YAML/code |
| **Promote** | A reusable diagnosis or mitigation step that belongs in a runbook/hub | Move it into the owning runbook ([observability](../../../../docs/observability/runbooks/README.md) / [databases](../../../../docs/databases/runbooks/README.md) / [secrets](../../../../docs/secrets/runbooks/README.md)); add/refresh the index row and `runbook_url` |
| **Move to evidence** | A dated finding, drill, measurement, or decision | Keep it in its owning record — an audit page, drill log, ADR/RFC, CHANGELOG entry, or the PR/commit — not loose in a guide |
| **Remove** | Duplicated or stale editorial residue that states nothing unique and no longer describes reality | Delete, only after confirming the knowledge survives elsewhere |

When in doubt between Remove and Move, Move. Deleting is the one irreversible
option.

## Guardrails

- **Check reality first.** Before changing any status claim, read the current
  manifest or source. Mark designed-but-undeployed things **planned**; keep
  **historical** and **known-gap** labels while they are still true.
- **Preserve unique knowledge and evidence.** Never delete the only copy of an
  operational constraint or a dated verification. Consolidate; do not relocate an
  editing diary verbatim.
- **One owner per fact.** Do not create a parallel note that competes with the
  authoritative runbook/hub — link it instead. `docs/api/` stays the API truth.
- **Preserve tooling directives.** Flux image-policy markers, license notices,
  and comments with their own semantics stay intact.

## Scope discipline

- Cleanup is **scoped to the requested domain or files**. Do not open a
  repo-wide rewrite.
- Leave unrelated gaps alone; collect them in a **deferred** list in your
  summary rather than fixing them silently.
- **Report index drift separately** — do not fold it into the cleanup diff.
  Known candidates to verify (not assume) at audit time:
  - Runbook index rows absent for the `gitops/`, `victoriametrics/`,
    `observability/`, and `keycloak/` folders in
    [runbooks/README.md](../../../../docs/observability/runbooks/README.md).
  - The cert-manager "no `runbook_url`" note vs the gitops runbooks that now
    cover `CertManager*`.
  Re-derive alert/runbook counts from the tree; never copy a cached number.

## Output

Produce a disposition table (file → note → disposition → where it went), the
applied edits within scope, and a separate list of deferred candidates and index
drift for the owner to decide on.
