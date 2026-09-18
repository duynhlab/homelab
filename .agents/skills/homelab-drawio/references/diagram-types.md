# Which diagram am I drawing?

[AGENTS.md § Diagram workflow](../../../../AGENTS.md#diagram-workflow) step 1 says
to choose **one question**. This file makes that choosable: it names the five
questions a homelab diagram may answer, and for each one says what goes in and —
harder, and more often got wrong — what stays out.

Pick a row before placing a single box. If two rows both look right, you have two
diagrams.

## The rule that decides what goes in

Every diagram has a **scope**, and inside that scope its elements split in two:

- **Primary elements** — what the diagram is *about*. Drawn in full: named, given
  their role colour, given their technology, given their logo if the catalog has
  one.
- **Supporting elements** — things that touch the primary ones and whose absence
  would make the picture a lie. Drawn plainly, with just enough label to be
  recognised, and **never expanded**.

Everything else is out. A box that is neither primary nor supporting is the most
common way a diagram stops being readable: it is always defensible on its own
(*"but the platform does have that"*) and always costs the reader.

This is also the test for the mistake that looks like thoroughness — **mixing
levels of abstraction**. If one box is a whole subsystem and its neighbour is a
single container inside another subsystem, the reader cannot tell what scale they
are reading, and the diagram answers no question cleanly.

## The five questions

| Question | Scope | Primary elements | Supporting elements | Keep out |
|---|---|---|---|---|
| **Platform landscape** — what is deployed, in one frame | The whole platform, one cluster | Every domain as a frame, with the deployed components inside at one level | The browser and any off-platform third party | Request ordering, per-route detail, anything inside a component |
| **Domain topology** — how one area hangs together | One domain (observability, databases, secrets, edge) | Every deployed component of that domain, its protocols and its stores | The neighbouring domains it talks to, as single boxes | Other domains' internals; the control plane unless it is the subject |
| **Request path** — how one journey travels | One journey, edge → response | The components the request actually traverses, in order | Stores read or written on the way; the identity provider if consulted | Components not on this path, however important elsewhere |
| **Delivery / lifecycle** — how it gets there, and what gates on what | One delivery graph (Flux waves, a rollout, a migration's steps) | Each wave or step, its ordering edges, and the condition that releases it | The artefacts a wave applies, when the gate is the point | Runtime request flow — that is a different question, and a different file |
| **Migration** — what changed and why | One before/after pair | The end state, plus what it replaced | The record (ADR/RFC) that decided it | Anything still true in both states and therefore not the story |

A **historical** diagram says so in the surrounding text. A diagram of something
not yet deployed follows the design record's status — the label table in
[AGENTS.md § Diagram workflow](../../../../AGENTS.md#diagram-workflow) step 2 —
and `planned` nodes are dashed **and** carry the word.

## Review it before you export

Run through this with the rendered SVG open, not the XML. Every line is something
a reader has actually been unable to work out from a diagram:

1. **Title and scope on the canvas.** A reader who opens the file alone, with no
   surrounding prose, can say what it covers and what it does not.
2. **Type is obvious.** One of the five rows above, recognisable without being
   told.
3. **Legend present**, listing exactly the roles this diagram uses — no more.
4. **Every element named**, and named specifically. `product-db` and
   `checkout-service`, never `database` or `the API`.
5. **Technology visible** where it is a choice a reader needs: the engine, the
   protocol, the port when it disambiguates.
6. **Every relationship says what flows** — calls, reads, deploys, owns. Two
   ways to satisfy this, and only one is mechanical: label the arrow, or, when
   *every* arrow in the diagram means the same thing, say so once in the legend
   and leave them bare. `validate_house.py` only enforces the dashed case
   (AGENTS.md step 5), because a dotted arrow means optional, indirect, planned
   or an exception and the reader cannot guess which. Mixed meanings with no
   labels is the failure to avoid.
7. **One level of abstraction.** No subsystem sitting beside a single process.
8. **No unexplained acronyms.** Ours are fine (CNPG, ESO, VM) *if* the legend or
   the label expands them once.
9. **Colour is never the only signal.** State is in the label too — that is why
   `planned` is a word as well as a dash.
10. **Nothing is decoration.** Every box earns its place as primary or
    supporting; a box you cannot classify is a box to delete.

The last check is the one worth being strict about: this repo treats a diagram as
an executable summary of itself, so a box that is merely plausible is a box that
will be wrong after the next change and nobody will notice.

## Why this shape

The primary/supporting split, the review checklist and the "mixed abstraction"
warning are the C4 model's contribution to this repo's convention, restated for
our five question types and our palette. The model itself is notation-independent
— it prescribes what a diagram must make unambiguous, not how to colour it — so
the homelab house style supplies the notation and this file supplies the scoping
discipline.
