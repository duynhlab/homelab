<!--
Reference template (ADR-083 contract: "What is the exact contract or value?").
Copy the file, replace every {placeholder}, and delete all author comments and
the review gate before publishing.

A reference is neutral and complete: one row per thing, the same columns on
every row, exact names in code formatting, and a derived count with the
command that derives it. It explains nothing; it links the explanation page.
A service contract uses docs/api/_template-service.md instead.
-->

# {Thing} reference

<!-- One sentence: what this page lists and what the list mirrors in the system. -->

{What the rows are, and the manifest, registry, or output they mirror.}

| Quick facts | |
|---|---|
| **Page type** | Reference |
| **Mirrors** | {Manifest path, CRD, registry, or command output this page is derived from} |
| **Count** | {N, derived by the command in § How this page is derived} |
| **Deployment status** | {Deployed / mixed — status column per row} |
| **Evidence context** | {Repository SHA and date the rows were derived} |
| **This page owns** | {The exact names and values listed here} |
| **Not this page** | {The explanation page; the how-to that changes these values} |

## How to use this page

<!--
Two or three lines: how the rows are grouped, what the status column means,
and the lookup the reader most often makes.
-->

{Grouping, status vocabulary (deployed, **planned**, **reference — not
deployed**), and the common lookup.}

## {Group 1}

| Name | Value or shape | Default | Owner | Status | Record |
|---|---|---|---|---|---|
| `{exact name}` | {value, type, or shape} | {default, or "required"} | {manifest path or component} | {deployed / **planned**} | [{ADR/RFC}]({link}) |

## {Group 2}

| Name | Value or shape | Default | Owner | Status | Record |
|---|---|---|---|---|---|
| `{exact name}` | {…} | {…} | {…} | {…} | {…} |

## How this page is derived

<!--
The command that produces the count and the names. The alert catalog's
`scripts/alert-catalog-counts.sh` is the model: derive, never increment by
hand.
-->

```bash
{command that lists the rows or counts them}
```

```text
{abbreviated real output}
```

## Related

- [{Explanation}]({link}) — why these values are set this way.
- [{How-to}]({link}) — how to change one safely.

<!--
## Review gate — delete before publishing

- [ ] Every row has the same columns; names match the manifest or output
      exactly.
- [ ] The count is derived by the stated command on the stated date.
- [ ] Every not-deployed row carries its status label and its record.
- [ ] The page explains nothing that the explanation page owns.
- [ ] `scripts/docs-check.sh <this file>` exits 0.
-->
