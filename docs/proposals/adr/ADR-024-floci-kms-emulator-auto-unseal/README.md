# ADR-024: floci KMS-emulator auto-unseal for OpenBAO on Kind

Replace OpenBAO's Shamir-key-in-a-Secret + unsealer CronJob with `seal "awskms"`
auto-unseal backed by a local **floci** KMS emulator, and revoke the persisted root
token — closing RFC-0008's top findings on Kind.

| Status | Date | Related RFC | Related research |
|--------|------|-------------|------------------|
| Accepted | 2026-07-19 | [RFC-0008](../../rfc/RFC-0008/) | [RFC-0008 research.md](../../rfc/RFC-0008/research.md) |

> **Every decision is a tradeoff.** We accept an extra emulator component (and a
> loose, zero-auth KMS stand-in) to remove the master key from a readable K8s Secret
> and rehearse the exact production auto-unseal path locally.

## Context

OpenBAO on Kind is unsealed by a Shamir key + root token stored in the plaintext
`openbao-init-keys` Secret, re-applied by a 60s **unsealer CronJob** — a
`kubectl get secret` from full compromise (RFC-0008 Criticals). Real auto-unseal was
believed untestable on Kind (no cloud KMS). The [RFC-0008 research PoC](../../rfc/RFC-0008/research.md#worked-examples)
proved otherwise: OpenBAO `seal "awskms"` pointed at a **floci** emulator self-unseals
at init and across restarts. Because everything binds by an AWS KMS **alias**, the
cluster config can be static.

## Decision

On Kind, OpenBAO uses **`seal "awskms"`** with `endpoint` → an in-cluster **floci**
emulator (Deployment + Service + **PVC**, ns `openbao`) and `kms_key_id =
"alias/openbao-unseal"`. A **dedicated `floci-kms-init` Job**, co-located with the floci
Deployment and the OpenBAO HelmRelease **in the same `controllers-local` Flux wave**,
creates the floci KMS key + that alias so it exists as OpenBAO boots (see the
startup-deadlock note in Consequences). The `openbao-bootstrap` Job then `operator
init`s with **recovery keys** (no unseal key) and **revokes the root token** after
configuring. The **unsealer CronJob and the `openbao-init-keys` unseal-key** are
removed; only a break-glass **recovery key** remains (the inert root-token copy is left
in place — see Consequences). Day-2 reconfiguration uses `operator generate-root` from
the recovery key, never a persisted root token. floci is fenced by **NetworkPolicy**
(zero-auth).

- **Storage:** floci PVC `standard` (`FLOCI_STORAGE_MODE=persistent`); the KMS key
  survives pod restarts within a cluster life.
- **Kind-only:** production still targets a real cloud KMS (`seal "awskms"`/`gcpckms`
  via IRSA/Workload Identity) — the config block is identical, only `endpoint` differs.

## Alternatives considered

- **Keep Shamir + unsealer CronJob** — no new infra, but the master key stays plaintext
  in a Secret and the pod is sealed ≤60s on re-seal. Lost (the finding itself).
- **SoftHSM + `seal "pkcs11"`** — fully self-contained, no emulator, key not in a Secret,
  OSS in OpenBAO; but new tooling and config differs from the prod KMS path. Viable
  future option; not chosen for the first slice (floci mirrors prod config 1:1).
- **Transit seal (a second OpenBAO)** — realistic but only relocates the chicken-and-egg
  (the transit vault still needs unsealing). Lost.
- **Cloud KMS on Kind** — impossible (no cloud); it is the production target, not local.

## Consequences

**Gain:** the Shamir unseal key and the persisted root token leave the cluster; pods
self-unseal at boot; the unsealer CronJob is deleted; the prod `seal "awskms"` path is
rehearsed on Kind (swap `endpoint` for prod).

**Accept (the cost):**
- **Startup deadlock → alias provisioned in the same Flux wave as OpenBAO.** OpenBAO's
  `awskms` seal resolves `alias/openbao-unseal` via `DescribeKey` **at server startup**
  and crash-exits if it is missing (`Error configuring seal "awskms": Alias not found`).
  The alias must therefore exist as OpenBAO boots, and it cannot be created by the
  `openbao-bootstrap` Job — that waits for OpenBAO `:8200` (chicken-and-egg). It is
  created by a dedicated **`floci-kms-init` Job placed in the `floci` overlay of the
  `controllers-local` wave**, next to the floci Deployment and the OpenBAO HelmRelease.
  **Placement is load-bearing:** if this Job lived in `secrets-local` (which
  `dependsOn: controllers-local`, `wait: true`) it could only run *after* the OpenBAO HR
  is Ready — which never happens without the alias → a hard deadlock on a clean boot.
  Co-located, the Job creates the alias (~10s once floci is up) while OpenBAO
  crash-retries, so both converge in one wave; verified on a clean `make down && make up`
  that OpenBAO then starts with **0 restarts** (alias lands first). `controllers-local`
  `wait: true` is satisfied meanwhile because OpenBAO's readiness probe is deliberately
  permissive (`sealedcode=200&uninitcode=200` → a running-but-sealed pod counts Ready).
  floci itself needs `enableServiceLinks: false`, else Kubernetes injects
  `FLOCI_PORT=tcp://…` and its Quarkus config crashes.
- **Root revocation must be node-pinned and exit-code-verified.** `bao token revoke -self`
  routed through the load-balanced HA **Service** can be dropped/misrouted during leader
  churn, and inferring success from `token lookup -self` *failing* is unsafe — a transient
  standby error is indistinguishable from "revoked". The bootstrap pins the revoke to a
  single stable node (`openbao-0`) and treats its **exit code 0** as the authoritative
  signal (idempotent), failing the Job otherwise. Without this the Job could report
  success while a **live** root token stayed in `openbao-init-keys` — caught in review by
  verifying the token explicitly rather than trusting the log.
- **The inert root-token copy is left in the Secret (not scrubbed).** After a verified
  revoke the `root_token` field is dead but still present: the bootstrap image's BusyBox
  `wget` can only GET/POST (no PATCH), so the field can't be removed in-script without new
  tooling. It is verifiably revoked, so this is cosmetic — **but** a read of
  `openbao-init-keys` still yields the **recovery key = full admin** via
  `operator generate-root`, so the Secret-read blast radius is essentially unchanged by
  the unseal→recovery swap. The real security win is the **revoked root token**, not the
  key swap. Beyond Kind: shard the recovery key (`-recovery-shares>1`) and store shares
  offline. For the same BusyBox-`wget` reason, K8s API calls use `--no-check-certificate`
  (no `--ca-certificate`) — acceptable in-cluster on Kind, documented.
- A new **stateful emulator** (floci) to run; its KMS key must persist (PVC). Losing that
  volume mid-life would brick unseal — **moot on Kind** (`make down` wipes all → fresh
  bootstrap), documented.
- floci is a **loose, zero-auth emulator** (decrypt not bound to key existence): a
  parity/rehearsal tool, **not** real crypto — fenced by NetworkPolicy; real security is
  cloud KMS/SoftHSM.
- **Revoking root** means day-2 ops need `operator generate-root` from the recovery key;
  the bootstrap must handle re-runs via that path (no persisted root token).
- A recovery key still exists (break-glass) — lesser risk than a live unseal key.

## Related

- [RFC-0008](../../rfc/RFC-0008/) · [research.md](../../rfc/RFC-0008/research.md) (auto-unseal spine + PoC)
- [`docs/secrets/openbao.md`](../../../secrets/openbao.md) · [ADR-005 (OpenBAO HA Raft)](../ADR-005-openbao-ha-raft/)
