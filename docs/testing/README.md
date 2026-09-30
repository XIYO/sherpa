---
uuid: 01a0f253-cd8b-73c9-87fb-f7cfed9ab710
type: spec
audience: "Maintainers deciding which test level must prove a Sherpa change before it merges"
goal: "Pick the deterministic or owner-operated proof a change needs and know what each gate covers"
tone: "Normative technical English. States what each level proves and what it cannot"
manner: "One level per bullet; live evidence and the verification matrix stay in their own files"
---

# Sherpa Test Strategy

## Levels

- Domain invariants use deterministic unit tests.
- Application use cases use fake capability ports and cover denial, ambiguity,
  partial mutation, approval mismatch, and failed read-back.
- Public-verification integration tests exercise wrong confirmations and
  malformed destinations with zero writes, exact destination binding, Event
  future-series update/delete, Reminder complete/reopen, schedule clearing,
  partial-create reference recovery, cleanup failure, recurrence residue, and
  false native delete success. Separate source-mode tests create, use, re-list,
  and remove a disposable Calendar and Reminder list while journaling only safe
  references.
- EventKit gateway contract tests decode the exact Swift `reminders` and
  `reminder` response envelopes for list, get, and verified mutations, and
  reject the obsolete wrapper names.
- SQLite storage tests open the same fresh canonical path from twelve
  barrier-synchronized threads. Schema-version discovery and migration share
  one immediate transaction, and only bounded `BUSY`/`LOCKED` WAL-transition
  failures are retried.
- Worker clients use fixture executables for crash, timeout, cooperative
  cancellation, malformed output, oversized output, protocol mismatch, and
  nonzero exit behavior. A real CLI black-box test sends SIGINT while a worker
  and descendant are active, then requires exit code 130 and zero surviving
  process-group members.
- Cross-language JSON contracts are compiled against the Draft 2020-12
  meta-schema. Tests then validate the actual serialized Worker envelope,
  Context analysis request and suggestion DTO contracts.
- Mapping logic uses synthetic fixtures without live accounts.
- Release artifact checks prove the EventKit, private Reminder, and Mail usage
  descriptions remain embedded, native executables have valid ad-hoc linker
  signatures, and no Developer ID team identity is required by the core gate.
- The built private Reminder helper receives one valid synthetic request for
  each of tags, flags, URL attachments, sections, subtasks, and image
  attachments while writes are forced off. Every route must reject at the
  write gate, and credential-bearing URLs must fail payload validation before
  that gate; this exercises the real helper without reading or mutating data.
- Renderer contracts use golden fixtures with Korean text, multiline values,
  absent fields, unsupported capabilities, and escaping edge cases.
- CLI behavior uses black-box tests with fake worker registries.
- Privacy tests run the real Planner CLI and isolated Context worker at debug
  verbosity with unique sentinel content and native identifiers. They prove
  the sensitive values traverse the data result while stderr contains only
  safe boundary metadata; Planner public output must replace native IDs with
  Sherpa references. Context covers iMessage, KakaoTalk, and the nested
  Context-to-Mail worker boundary, including deliberately noisy reader stderr.
- Planner process-isolation tests corrupt each worker protocol in turn through
  the real `sherpa capabilities` command. The failed provider must be reported
  as unavailable while the other provider remains supported. A missing
  EventKit executable is tested separately so gateway construction cannot
  abort capability diagnosis before the healthy private provider is probed.
  A real Reminder-list path also proves corrupt private enrichment retains the
  EventKit item and marks only advanced fields unavailable.
- Planner doctor v2 keeps authorization observation independent per worker.
  Missing or malformed workers produce a stable error code in the affected
  authorization rows while healthy provider diagnostics are still rendered.
  The simpler public `status` command reads only EventKit Calendar and
  Reminders state; optional-helper state belongs to `doctor`.
  Doctor also renders the current private write policy independently from
  stored OS-scoped compatibility evidence; evidence never enables the gate.
- The application registry reconstructs the exact expected capability set.
  Missing and duplicate worker rows become explicit unavailable states, and
  unregistered rows cannot enter the public registry. Provider failures retain
  stable reasons such as `worker.unavailable` and `worker.protocol_failure`;
  failed environment discovery stops the provider before a second probe.
- Capability evidence record input has no caller-owned timestamp. The canonical
  store assigns `verified_at_epoch`, and only retrieved verification results
  expose that persisted observation time.
- Private evidence environment keys combine macOS and the helper's declared
  implementation revision. A stale or mismatched helper cannot inherit proof
  produced by another adapter build. The lint gate synchronizes the contract
  revision across its source file, Objective-C helper, and
  release-process assertion.
- Context contract tests use fixture `imsg` and Kakao rows, traverse the real
  worker process, and verify half-open time and three-dimensional collection
  bounds without reading a user's archive.
- Context outbound tests separate three proofs. Application/orchestration tests
  prove wrong confirmations dispatch zero times and exact confirmations dispatch
  once. Real Context worker process tests cross the native Messages, KakaoTalk,
  and nested Mail sender boundaries with fixture executables. A CLI black-box
  test syncs a synthetic
  safe thread, persists a draft, rejects a wrong code, dispatches exactly once,
  and rejects confirmation reuse without sending any real communication.
- Mail release-process tests compile the embedded AppleScript, require the
  verified-write policy for `mail.message.send`, reject malformed send payloads
  before authorization or native invocation, and enforce the 2 MiB envelope
  needed for a bounded 1 MiB body.
- Foundation Models tests compile the real `@Generable` schema and exercise
  payload and mapping logic with synthetic values. Default gates call only the
  non-inference `capabilities` path; live model generation requires explicit
  Context analysis confirmation.
- Context storage tests bind presentation and analysis to exact immutable
  revisions, prove unchanged input leaves `pending`, and prove a newer
  concurrent revision re-enters `pending` instead of being closed accidentally.
- Distribution checks package the release archive and verify it holds the CLI
  and nothing else — no agent marketplace, no worker runtime. `scripts/package.sh`
  refuses to package a binary whose `--version` does not match `sherpa X.Y.Z`,
  because the plugin's version guard parses exactly that shape. Packaging also
  renders two Formulas from one template: `Formula/sherpa.rb`, whose URL names
  the public release asset and which is copied as a whole into
  `XIYO/homebrew-tap`, and `local-tap/Formula/sherpa.rb`, which points at the
  `file://` archive for development installs. The release smoke installs the
  local one and fails unless the two differ only in that URL line; Homebrew
  performs the actual install or upgrade. The [Homebrew release
  runbook](local-homebrew-release.md) defines the owner-operated sequence and
  post-upgrade checks.
- Agent integration tests use fake `codex` and `claude` executables. They pin
  fixed argv, status parsing, post-install verification, partial host
  availability, and restoration after a failed marketplace replacement; the
  deterministic gate never changes a real host configuration.
- The lint gate checks the exact dependency graph for every Swift target
  and fails if private ReminderKit framework loading appears outside the
  crash-isolated helper. This turns the inward dependency rule into an
  executable architecture contract.
- The traceability gate extracts every Planner and Context requirement
  identifier and requires exactly one matching verification-matrix row. A new,
  removed, or duplicated requirement therefore fails the gate until its
  evidence and status are reviewed explicitly.

## Live tests

Live Apple or provider tests are opt-in and operate only on an explicitly
selected disposable list/calendar/account. A mutation test follows create,
native read-back, and cleanup. Partial create errors retain only the safe Sherpa
reference needed for recovery; recurring Calendar cleanup uses the future-series
span and checks every synthetic occurrence window. A cleanup failure is
reported and never hidden.
Private Reminder tests remain disabled until their capability probe passes.
The exact owner-operated sequence is documented separately; it is a runbook,
not a default test dependency.

Every approved Planner and Context requirement is mapped to its
implementation, deterministic evidence, and remaining owner-operated evidence
in the [verification matrix](verification-matrix.md).

## Gates

Every change runs format, lint, unit, contract, golden, black-box, privacy, and
architecture checks. Live checks are a separate local/release gate and never a
default CI dependency.

Worker Protocol V2 contract tests share the fixtures under
`protocols/fixtures/worker-v2`. They cover strict required and unknown fields,
V1 rejection, application-contract and correlation echoes, policy/evidence
compatibility, and every succeeded/failed/partial/uncertain outcome. Supervisor
tests distinguish failure before stdin dispatch from timeout, cancellation,
crash, malformed output, and oversized output after dispatch. Effectful
post-dispatch boundary loss must retain `may_have_applied` and retry `never`.
Planner adapter tests additionally pin DST, exclusive all-day ends, UTC/GMT
aliases, alarms, recurrence, clear patches, native mismatch, duplicate native
locators, and zero native calls after invalid preflight.

## Related

- [System architecture](../architecture/README.md)
- [Hexagonal modularization test plan](hexagonal-modularization.md)
- [Incremental hexagonal modularization RFC](../rfc/0003-hexagonal-modularization.md)
- [Planner requirements](../requirements/planner-authority.md)
- [Worker protocol](../contracts/worker-protocol.md)
- [Context requirements](../requirements/context-intelligence.md)
- [Distribution requirements](../requirements/distribution.md)
- [Unsigned Homebrew distribution](../adr/0005-unsigned-homebrew-distribution.md)
- [Homebrew release runbook](local-homebrew-release.md)
- [Public output contracts](../contracts/public-output-v1.md)
- [Owner-operated live validation](live-validation.md)
- [Requirement verification matrix](verification-matrix.md)
- [Public output v1 contract](../contracts/public-output-v1.md)
