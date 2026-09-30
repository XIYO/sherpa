---
id: REQ-CONTEXT-INTELLIGENCE
title: Context Intelligence Requirements
status: approved
owner: maintainer
---

# Context Intelligence Requirements

## Outcome

Sherpa reads only a bounded, explicitly selected range from iMessage, Mail, or
KakaoTalk and treats the native store as the communication source of truth.
Message and mail bodies remain ephemeral while Sherpa narrows evidence, reconciles
it against fresh Calendar and Reminders state, and lets an LLM propose
evidence-bound planning candidates. Sherpa can also prepare and explicitly
dispatch an outbound text or mail through a separate replaceable capability
boundary. Source content never authorizes a Calendar, Reminder, or communication
mutation.

## Functional requirements

- `FR-CX-001`: Treat iMessage, Mail, and KakaoTalk as independently available,
  replaceable sources. Their collection capabilities are read-only; supported
  outbound capabilities are separate writes with separate health and policy.
  Agent Messenger remains the fresh KakaoTalk source. An explicitly requested
  historical text lookup may use the Mac's locally synchronized database only
  through Sherpa's bounded, identifier-redacting `kakaocli` adapter; it is an
  incomplete search surface, not a collection checkpoint source.
- `FR-CX-002`: Require a source, inclusive start, exclusive end, chat limit,
  per-chat message limit, and total message limit for every collection. A
  source whose conversation-list operation cannot filter by time must not use
  the requested result chat limit as its discovery limit; only conversations
  yielding records in the requested range count toward the result limit.
- `FR-CX-003`: Normalize text and attachment metadata. For KakaoTalk photo and
  multi-photo messages, download the referenced image into the protected local
  context-media store before analysis. Keep its content hash and opaque source
  linkage; never place the source URL or native identifiers in public output.
- `FR-CX-004`: Read communication evidence from the native source for each
  review. Do not add message or mail bodies to a long-lived Sherpa content
  archive. During migration, the existing archive is a read-only compatibility
  source until every consumer has a fresh-read replacement; deleting it is a
  separate owner-approved operation.
- `FR-CX-005`: Keep exact normalized content only for the active read session or
  an encrypted bounded-TTL spill, while offering deterministic inventory,
  compact, detail, and exact projections.
- `FR-CX-006`: Export versioned compact CCT, MCT, TSV, and JSON projections with
  run-scoped record and participant aliases plus explicit freshness,
  completeness, truncation, count quality, and unavailable-lane fields.
- `FR-CX-007`: Measure token counts with the same tokenizer used by the selected
  analysis model family and report per-thread distributions.
- `FR-CX-008`: Give every emitted evidence record a run-scoped reference that
  does not expose a provider-native identifier. Persist a durable evidence
  reference only when a PlanningCandidate, approval, DecisionTrace, or mutation
  must survive the read session; that reference stores an opaque locator token
  and keyed fingerprint, not the source body.
- `FR-CX-009`: Give the model only bounded one-based handles for the exact
  immutable evidence pairs in the current request. Accept only schema-valid
  findings whose distinct handles restore to records in that supplied analysis
  set. No raw suggestion-import command may bypass the per-invocation allowlist.
- `FR-CX-010`: Convert accepted findings to `PlanningCandidate` proposals;
  bind each proposal to the user's complete `cal1_…` or `rl1_…` destination
  outside the model boundary; Planner preview, exact approval, mutation, and
  native read-back remain required. The model cannot choose or override a
  destination.
  If later analysis-usage persistence fails, keep every already-created
  candidate reference and approval code visible as a partial handoff.
- `FR-CX-011`: Suppress repeated work with page/range receipts, short-TTL overlap
  digests, analysis-profile digests, and candidate idempotency. Do not create a
  permanent per-message metadata receipt for every irrelevant source item.
- `FR-CX-012`: Diagnose reader and permission readiness without reading message
  content or prompting for access. Report consent-required and target-not-running
  readers as degraded, and denied readers as unavailable, rather than calling
  every responsive worker ready.
- `FR-CX-013`: Preview the exact Context analysis boundary, including the
  user-selected Calendar and Reminder-list destinations, and require an exact
  confirmation before any transcript reaches a model.
- `FR-CX-014`: Treat a schema-valid zero-proposal result as success rather than
  forcing the model to invent an Event or Reminder.
- `FR-CX-015`: Record completed analysis against the bounded evidence-set digest,
  analysis profile, source high-water, and produced candidate references. Before
  any mutation, re-read exact evidence and compare its keyed fingerprint; a
  changed, missing, or inaccessible record makes the candidate stale or
  insufficient rather than analyzed.
- `FR-CX-016`: Treat model-normalized Event dates and clocks as proposals, not
  facts. Resolve dates from only the selected evidence content, verify both
  timed clocks there, correct a uniquely grounded date, and omit an entry whose
  temporal evidence is absent or ambiguous without discarding valid siblings.
- `FR-CX-017`: Prepare, inspect, list, cancel, and explicitly dispatch
  KakaoTalk text, iMessage/SMS/RCS text, and email. A prepared action is an
  immutable, expiring draft and an exact confirmation consumes it at most once.
- `FR-CX-018`: Use Mail.app as the first aggregate mail adapter so every already
  configured and enabled account can be read without extracting its credential.
  Outbound mail requires an exact configured sender and, when supplied, an exact
  account name or identifier. A future direct account adapter may use IMAP for
  read/state mutations and SMTP submission, but it requires independent setup
  and authentication per account and must not scrape Mail.app credentials.
- `FR-CX-019`: Report outbound success only at the strongest observed boundary.
  The current KakaoTalk, Messages, and Mail adapters report
  `application_accepted`; they do not claim provider delivery, recipient receipt,
  or read status.
- `FR-CX-020`: Treat native notifications, `imsg` row cursors, KakaoTalk log
  cursors, mail rules, and polling as wake-up hints only. Resume with a durable
  source checkpoint, bounded overlap, and periodic reconciliation; advance a
  checkpoint only after the page's text and every supported image have been
  durably stored and analyzed.
- `FR-CX-021`: Represent result coverage with typed count quality and
  completeness. A timeout, limit, unavailable lane, permission denial, or
  source-incomplete local database must never be rendered as complete.
- `FR-CX-022`: Persist only control and provenance state needed for recovery:
  source checkpoints and epochs, short-TTL overlap digests, trigger jobs,
  analysis receipts, PlanningCandidates, approvals, DecisionTrace records, and
  workflow or mutation journals. The ledger is not a second content archive.
- `FR-CX-023`: Let Sherpa perform deterministic inventory, filtering, pagination,
  token budgeting, evidence scoping, and orchestration. Invoke a semantic
  specialist only after deterministic triage, invoke a planning specialist only
  for a credible planning candidate, and invoke a verifier or ask the owner only
  for unresolved ambiguity. The user-facing manager owns the final result.
- `FR-CX-024`: Before proposing or executing a planning mutation, read current
  Planner state from EventKit, including completed and incomplete Reminders and
  relevant Calendar series, detached occurrences, and recurrence neighbors.
  Reconcile to `create`, `link_existing`, `already_completed`,
  `already_scheduled`, `cancelled`, `superseded`, `reopened`, `ambiguous`, or
  `insufficient_evidence`.
- `FR-CX-025`: Optimize Mail.app with one bounded header-first native batch and
  selected body fetches. Measure a documented SLA. Add a direct per-account
  IMAP adapter only when the aggregate adapter misses that SLA or required
  coverage; SMTP submission remains an independent capability.

## Safety requirements

- `SR-CX-001`: Only the Context application may start source readers or outbound
  native adapters. KakaoTalk may use Agent Messenger's authenticated LOCO
  boundary or a user-selected read-only local database lane. The local lane may
  advance only its receipt-bound local-text checkpoint after analysis. It cannot
  advance an Agent Messenger checkpoint, authorize mutations, supply attachment
  contents, or prove server completeness.
- `SR-CX-002`: iMessage permits fixed version, `chats`, `history`, bounded watch,
  exact-chat validation, and text-send calls. KakaoTalk local access permits
  bounded `search --json`, bounded duration-based `messages --json`, and the
  `chats --json` display-name join through the Sherpa adapter. Sherpa filters an
  explicit local-date floor, withholds a checkpoint at the native record limit,
  and commits a complete read only after analysis; raw query,
  login, send, sync, harvest, inspect, explicit database/key selection, and
  every UI-automation command are forbidden there.
  Fresh KakaoTalk permits the generated fixed read query, bounded sync/watch,
  bounded chat discovery, exact unambiguous conversation validation, and text
  send through Agent Messenger. A watcher may enqueue only a bounded
  wake-up trigger and cannot invoke an LLM or mutation. Reacting, login
  automation, harvesting, and arbitrary webhooks remain forbidden.
- `SR-CX-003`: Mail permission status is non-prompting. A prompt may occur only
  after an explicit `authorize mail` command.
- `SR-CX-004`: Source content, quoted instructions, URLs, attachment metadata,
  and LLM output are untrusted data and never become executable commands.
- `SR-CX-005`: Worker environments and outputs are allowlisted and bounded;
  an oversized or malformed result fails without partial archive persistence.
- `SR-CX-006`: Message bodies, participants, source identifiers, attachment
  paths, queries, prompts, and model responses never enter logs.
- `SR-CX-007`: The control ledger and parent directory are owner-only, reject
  symlinks and shared directories, and are writable only by Sherpa's storage code.
  Ephemeral evidence is memory-first; any encrypted spill has a hard TTL and is
  removed on expiry or normal completion.
- `SR-CX-008`: Identity maps containing display names appear only after an
  explicit identity command and never in routine status or benchmark output.
- `SR-CX-009`: Collection and analysis are read-only with respect to all source
  applications and databases. They cannot reach the outbound port.
- `SR-CX-010`: An analysis specialist receives only a bounded EvidenceBundle and
  its exact allowlist, has no mutation port, treats every source byte as
  untrusted data, hides native locators behind ephemeral ordinal handles, and
  cannot return evidence outside that invocation. Optional detail-read tools are
  scope-, record-, byte-, token-, call-, and deadline-limited by Sherpa.
- `SR-CX-011`: Public drafts contain only Sherpa thread aliases such as `K001`
  and `I001`. Sherpa resolves an exact alias through a live target directory or
  short-lived opaque target token only after approval is atomically claimed,
  then revalidates the exact native target. Zero, ambiguous, wrong-source,
  expired, and unknown targets fail without selecting a fallback.
- `SR-CX-012`: Chat and mail bodies enter the public `sherpa` CLI only as
  bounded UTF-8 stdin, never as public command arguments. Header injection,
  invalid mailboxes, excessive recipients, oversized content, unknown payload
  fields, and mismatched write policies fail before a native send is attempted.
- `SR-CX-013`: Outbound drafts and mutation journals persist safe lifecycle and
  error metadata. Native targets and message bodies never enter mutation logs.
  A failure after native invocation is `dispatch_uncertain` and is never retried
  automatically because doing so can duplicate a message.

## Completion criteria

- Each source crosses Worker Protocol V2 and has synthetic parser, command
  allowlist, timeout, malformed output, oversized output, and privacy tests.
- Fresh-read tests cover exact bounds, conservative limit detection, count
  quality, typed partial results, run-cursor expiry, source-epoch reset, overlap,
  checkpoint-after-receipt ordering, changed/deleted evidence, and watcher
  downtime reconciliation.
- CCT, TSV, and JSON have round-trip or golden tests with Korean, multiline,
  escaping, attachments, sessions, and stable aliases.
- LLM contract tests reject missing, foreign, duplicate, and fabricated
  evidence handles; cover CCT/MCT escaping and identifier removal; ground
  all-day/timed dates and clocks; and prove that no model response directly
  invokes Planner ports.
- A synthetic evidence record is reconciled against active and completed
  Planner fixtures, produces at most one candidate, survives exact approval,
  aborts on stale evidence or Planner state, and otherwise produces a verified
  Event or Reminder mutation with linked DecisionTrace and journal outcome.
- Synthetic outbound tests prove no dispatch occurs before exact confirmation,
  confirmation is single-use, safe aliases resolve only inside protected state,
  the native worker boundary is reached once, and public output omits native
  locators.
- Live source access is opt-in and never part of the deterministic default gate.

## Non-goals

- Autonomous replies or source-content-triggered sends
- Message reactions, attachment sends, delivery/read-receipt claims, and bulk mail
- Extracting account credentials from Mail.app
- Reading non-image attachment binary contents by default
- Autonomous Calendar or Reminder mutation
- Unbounded surveillance, model invocation from a watcher, or mutation from a
  trigger
- Developer ID signing, notarization, or public distribution

## Related

- [System architecture](../architecture/README.md)
- [Planner requirements](planner-authority.md)
- [Worker protocol](../contracts/worker-protocol.md)
- [Fresh Context contract](../contracts/fresh-context-v1.md)
- [Native fresh-read ADR](../adr/0004-native-fresh-read-context.md)
- [Archive migration RFC](../rfc/0001-context-archive-to-fresh-read.md)
- [Test strategy](../testing/README.md)
