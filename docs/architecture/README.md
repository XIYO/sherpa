---
uuid: 01a0ed5f-2b59-779e-b766-9204357e1d42
type: spec
audience: "Maintainers and agents changing a Sherpa target boundary, journal, or external effect"
goal: "Place a change in the target that owns it and keep dependencies and mutation states correct"
tone: "Normative technical English. States the rule, then what it protects"
manner: "Name each target's role and dependency; defer contract detail to docs/contracts/"
---

# Sherpa System Architecture

## Purpose

Sherpa is a deterministic, local-first personal orchestration system. Humans
and language models may propose intent; only Sherpa itself validates,
authorizes, executes, journals, and verifies external effects.

## Quality goals

1. One public `sherpa` interface can coordinate replaceable capabilities.
2. A broken optional capability does not prevent healthy capabilities from running.
3. Language and framework types never cross the application boundary.
4. Every mutation is previewed, approved when required, journaled, and verified
   to the strongest boundary the provider exposes; weaker acceptance evidence is
   never presented as native read-back or delivery.
5. Untrusted source content is data, never execution authority.
6. Sensitive content is absent from diagnostics, logs, fixtures, and protocol metadata.
7. The repository is self-contained: every local package, skill, protocol, and
   build resource resolves beneath the Sherpa source root.

## System shape

```text
Human / LLM
    |
    v
sherpa — one native Swift executable
    |-- SherpaNative ---------------- argv parsing, bounded stdin, presentation
    |-- SherpaPlannerApplication ---- approval, idempotency, candidate freshness
    |-- SherpaMutationApplication --- journal state of each external mutation
    |-- SherpaPlannerContract ------- Worker Protocol V2 schemas
    |-- references, journal, canonical local store
    |
    +-- SherpaEventKitAdapter ------- official Calendar and Reminders
    +-- SherpaReminderKitShim ------- isolated optional private capabilities
    +-- SherpaMailShim -------------- Mail.app aggregate read / send
    `-- SherpaNativeCommandAdapter -- iMessage and KakaoTalk through their
                                      own installed CLIs
```

Sherpa is the only writer of Sherpa-owned databases. Apple remains the source of
truth for Calendar and Reminders; Messages, KakaoTalk, and Mail.app remain the
source of truth for communication content. Sherpa does not retain message or
mail bodies in a long-lived content archive. It stores a minimal owner-only
control/provenance ledger and keeps selected exact evidence in memory or an
encrypted hard-TTL spill for one workflow.

There is no separate worker process to supervise. What used to be a cross-
language boundary is now one executable: the same binary parses argv, validates
the request, reaches Apple frameworks through its adapters, and renders public
output. Worker Protocol V2 survives that collapse as the request/response schema
for `planner request`, `mail request`, and `reminder-kit request`, which read
strict JSON on standard input. It is a contract for callers, not a process
boundary, and it has no V1 runtime fallback.

Two external CLIs remain genuinely out of process — the installed iMessage CLI
and the official `kakaocli`. Sherpa invokes them with a fixed argv, bounds their
output, and never lets their bytes become execution authority.

## Dependency rule

Application code owns the ports it needs. Adapters depend inward to implement
those ports. The composition roots choose implementations.

```text
SherpaNative (composition root)
    -> SherpaPlannerApplication + SherpaMutationApplication + adapters + presentation

SherpaEventKitAdapter        -> SherpaPlannerApplication + SherpaPlannerContract
SherpaNativeCommandAdapter   -> SherpaMutationApplication + SherpaMailShim
SherpaPlannerApplication     -> SherpaPlannerContract
SherpaMutationApplication    -> no Sherpa target
SherpaPlannerContract        -> SherpaWorkerProtocol only
SherpaMailShim               -> Apple frameworks only
SherpaReminderKitShim        -> Apple frameworks only
```

No application or contract target imports EventKit, ReminderKit, CLI parsing,
terminal I/O, or provider-specific payloads. Those live in the adapter targets.
Private Apple framework code stays behind its own shim and is never a startup
dependency.

`SherpaMutationApplication` owns the journal state of every external mutation
the CLI makes itself: `planner request` mutations, `imessage send`, and
`mail send`. It defines the `MutationJournal` port, and the SQLite store in
`SherpaNativeCommandAdapter` implements it. The attempt and each journal write
are separate error boundaries. The terminal status comes from the attempt
alone: `failed` only when the effect never started, `uncertain` once a
mutation command was handed its input and its outcome could not be
established. A journal write that fails never changes that status and is never
retried as another one. The row stays `started`, and the command names the
journal failure in its output. The native command runner reports what happened
to a command and never writes the journal.

Context collection commands are compiled, read-only operations inside the same
executable. Every request names one source, an explicit half-open
time range, chat and per-chat limits, and a total message limit. Native command
output, request input, response output, and diagnostic streams are independently
bounded. The application validates the same range and volume invariants again,
assigns run-scoped references, and renders typed completeness and freshness
without persisting source bodies.

Native watchers and notifications are wake-up hints rather than truth. Sherpa
captures a source high-water, applies bounded overlap, records a processed or
skipped page receipt, and only then advances the source checkpoint. A periodic
reconciliation repairs watcher downtime, edits, deletes, and source rotations
where the native source makes those states observable.

Context outbound is a different application use case and policy boundary:

```text
UTF-8 stdin + safe target / exact mail headers
    -> validate and persist immutable expiring draft
    -> render full preview + one-time confirmation code
    -> atomically claim exact draft and confirmation
    -> resolve K001/I001 through a live target directory
    -> revalidate the exact native target
    -> journal a versioned write_with_verification request
    -> native application accepts the send command
    -> persist accepted / failed / partial outcome
```

The public and persistent action contains only a Sherpa thread alias. Provider
conversation names and Messages chat IDs are resolved from a live directory or
short-lived opaque target token at the last responsible moment and exist only
in the adapter request. KakaoTalk uses an exact Agent Messenger account and chat
identifier; iMessage validates the exact numeric chat before sending. Unknown,
expired, changed, or ambiguous targets fail closed.
Confirmation is single-use, so a timeout or process failure after native
invocation becomes `dispatch_uncertain` and is never automatically retried.
Current send adapters can prove only `application_accepted`, not provider
delivery, recipient receipt, or read status.

The explicit Mail permission request follows the same outer boundary:
`sherpa -> ContextMailAuthorizationPort -> SherpaMailShim`. It changes only
macOS automation consent and cannot collect or mutate source records. The other
verified-write route is `context.outbound.dispatch`, and the shim independently
accepts `mail.message.send`. The composition root is the only place that binds
a native adapter; application code sees ports.

Mail.app is the initial aggregate mail adapter. It can read the already
configured enabled accounts and submit through an exact configured sender
without asking Sherpa to acquire each provider credential. It does not expose
those credentials. A later direct-mail adapter is an independent capability:
IMAP supplies reads and mailbox-state mutations, SMTP supplies submission, and
each account requires its own OAuth or app-password setup. The direct adapter
must not be silently substituted for the aggregate adapter and cannot infer
credentials from Mail.app.

Context analysis is a second, separately confirmed boundary. Sherpa first
creates inventory and compact projections, then supplies only selected detail in a
bounded EvidenceBundle. Opaque source locators are replaced with one-based,
invocation-local handles. A specialist has no mutation capability and may ask
for more detail only through a scoped read grant. Sherpa rejects a finding that
cites evidence outside the invocation. Invalid generated entries
are omitted with content-free rule codes; an empty proposal array is a valid
non-hallucinating result.

Sherpa persists only the evidence-set digest, source high-water, analysis profile,
candidate references, and DecisionTrace. Before candidate creation and again
before mutation, it reads current active and completed Reminders plus relevant
Calendar series and occurrences. It records a typed reconciliation result and
re-reads exact evidence and selected Planner items immediately before executing.
A changed or missing fingerprint makes the candidate stale instead of closing a
revision or performing a mutation.


Agent skills are not an application port. They install from this repository's
plugin marketplace with each host's own command, and the CLI neither registers
nor inspects them. `plugins/sherpa/cli-contract.json` records the minimum CLI
version those skills need, and each skill verifies it before its first command.

## Trust and availability

Capability state and invocation outcome are separate contracts.

```text
CapabilityState = Supported | Unsupported | Unavailable | Incompatible | Disabled | Degraded
InvocationOutcome = Succeeded | Failed | TimedOut | Cancelled | Partial
```

An unavailable or private capability never becomes an empty successful result.
Private Reminder capabilities are opt-in, OS-version-gated, selector-probed,
crash-isolated, and verified independently from EventKit.
Their verification key includes both the active macOS version and the private
helper `implementation_revision`; replacing either invalidates old evidence.
If environment or revision discovery fails, the application does not make a
second probe or trust that provider's capability rows. It emits the complete
expected set as unavailable with the classified adapter error.
For private writes, verified compatibility and the current invocation policy
are also separate axes. A stored OS-scoped round trip can report a capability
as supported, but it never enables writes. Planner doctor reports the current
`private_write_policy` independently, and mutation calls still require the
exact `SHERPA_PRIVATE_WRITES=1` opt-in.

## Planning authority

Context findings first pass live Planner reconciliation. Only a candidate whose
kind, title, destination, schedule/due value, recurrence, evidence, current
completed/incomplete Reminder relation, and relevant Calendar occurrence
relation have been reviewed may become an Event or Reminder mutation.

```text
fresh evidence -> live Planner snapshot -> reconciliation
                  -> PlanningCandidate -> validation -> preview -> approval
                  -> exact evidence and Planner revalidation
                  -> started journal -> mutation
                  -> persist Sherpa reference -> native read-back
                  -> terminal journal state
```

Create operations persist the newly assigned Sherpa reference while the
journal entry is still `started`. If native read-back then fails, cleanup and
recovery can target the created record without retaining a provider-native
locator. The reference cannot be replaced after a terminal journal transition.
The Planning workflow copies that same safe reference and operation ID into a
partial candidate outcome. If the native mutation is verified but candidate
finalization fails, its error retains both values so journal-based recovery is
still possible; a storage failure must not erase knowledge of an Apple-side
effect.

Recurring Event changes require an explicit occurrence span. Destructive and
bulk changes require an exact target preview and explicit confirmation.

## Roadmap

1. **Planner Authority** — Swift execution core, EventKit Calendar and
   Reminders, isolated private Reminder capabilities, PlanningCandidate flow.
2. **Context Intelligence** — bounded native fresh reads for iMessage, mail, and
   KakaoTalk; minimal control ledger; progressive evidence; live Planner
   reconciliation; approval-gated text/mail outbound; evidence-bound
   PlanningCandidate proposals. Mail.app is benchmarked header-first and direct
   per-account IMAP is added only when its SLA or coverage gate fails; SMTP is a
   separate capability.

Homebrew is the canonical product installer. A release contains one relocatable
executable and nothing else; a prebuilt archive prevents compilation on the
user's Mac and the Formula declares no runtime dependency. Agent skills are not
part of that archive — they install from this repository's plugin marketplace,
and the Formula never registers them.

Homebrew's Formula catalog is distinct from the release archive it references.
The catalog is the public `XIYO/homebrew-tap` repository, so users install with
`brew install xiyo/tap/sherpa`, and the Formula's checksum-pinned URL names the
release asset of this repository for that version. For development on one
machine, the same generated Formula may point at a checksum-pinned `file://`
archive in a local tap; that does not change the installer boundary. In either
mode, the release version must be incremented and the generated Formula
published before `brew upgrade` can discover it.

Developer ID, Team ID, paid Apple developer membership, hardened-runtime
distribution, and notarization are permanently excluded. Compiler-produced
identity-free ad-hoc signatures remain an operating-system requirement on
Apple silicon, so privacy permissions may need owner reauthorization after a
Homebrew upgrade.

## Related

- [Incremental hexagonal modularization RFC](../rfc/0003-hexagonal-modularization.md)
- [Planner requirements](../requirements/planner-authority.md)
- [Context requirements](../requirements/context-intelligence.md)
- [Distribution requirements](../requirements/distribution.md)
- [Fresh-read design](../design/native-fresh-read-context.md)
- [Worker protocol](../contracts/worker-protocol.md)
- [Fresh Context contract](../contracts/fresh-context-v1.md)
- [Context analysis contract](../contracts/context-analysis-v1.md)
- [Test strategy](../testing/README.md)
- [Homebrew release runbook](../testing/local-homebrew-release.md)
- [Roadmap](../roadmap/README.md)
- [Native fresh-read ADR](../adr/0004-native-fresh-read-context.md)
- [Archive migration RFC](../rfc/0001-context-archive-to-fresh-read.md)
- [ADR-0001](../adr/0001-control-plane-and-workers.md)
- [ADR-0002](../adr/0002-conservative-supply-comparison.md)
- [ADR-0003](../adr/0003-context-outbound-and-mail-access.md)
- [Unsigned Homebrew distribution](../adr/0005-unsigned-homebrew-distribution.md)
