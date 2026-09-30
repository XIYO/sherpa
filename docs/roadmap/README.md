---
id: ROADMAP-SHERPA
title: Sherpa Core Roadmap
status: active
owner: maintainer
---

# Sherpa Core Roadmap

## Completion model

Each phase has two independent gates:

1. **Deterministic implementation** — builds, synthetic contracts, privacy
   tests, and black-box tests run without personal data or permission prompts.
2. **Owner-operated live validation** — the owner explicitly grants access and
   selects disposable or bounded real data. It is never run by the default gate.

Homebrew packaging is an active deterministic gate. Developer ID signing,
notarization, paid Apple developer membership, and App Store distribution are
permanently outside the product plan.

The active core goal spans Phase 1 and Phase 2: first obtain deterministic
Calendar/Reminders authority, then close the loop from personal communication
read/write through LLM analysis into approval-gated Event/Reminder creation. Phase 3
adds purchasing evidence after that loop is trustworthy.

## Phase 1 — Planner Authority

Deterministic implementation is present: Swift execution core, versioned
protocol, references, journal, presentation, Swift EventKit Calendar and basic
Reminders (including alarm and recurrence create/replace/clear), isolated
private Reminder capabilities, and the
PlanningCandidate-preview-approval-read-back workflow. Every candidate carries
one complete exact-kind Sherpa destination; approval never resolves a default
Calendar or Reminder list at execution time.

Owner-operated gate: authorize Calendar and Reminders, run disposable
schedule-aware CRUD
round trips, run the disposable synthetic tag verifier, then separately preview
and confirm each remaining private capability on a user-selected disposable
Reminder. Rebuilding an unsigned executable may require authorization again.

Calendar collaboration is a planned extension, not part of the current CRUD
claim. Organizer and attendee values are read-only observations today. A future
attendee, invitation-delivery, invitation-cancellation, or RSVP command first
requires the separate provider-authority and safety decisions proposed in
[RFC-0004](../rfc/0004-calendar-invitation-boundary.md); current Event commands
never send invitations. Invitation cancellation is distinct from the existing
exact-reference Event deletion command.

## Phase 2 — Context Intelligence

The existing archive-backed deterministic implementation is present for:

- bounded read-only iMessage, Mail.app aggregate, and KakaoTalk collection;
- owner-only immutable evidence revisions and token-aware transcripts;
- immutable outbound drafts for KakaoTalk text, iMessage/SMS/RCS text, and mail;
- safe `K...`/`I...` target aliases, exact single-use confirmation, journaled
  worker dispatch, and explicit `application_accepted` evidence.

On-device Foundation Models analysis, strict evidence-bound suggestions,
trusted destination binding, and approval-gated Planner handoff are **not**
present in that sense. The worker exists in `apple/foundation-models-service`,
but no CLI entry point reaches it, so the path cannot be run from the product.
The Rust control plane that spawned that worker was removed when the runtime
moved to Swift, and the Swift CLI never rebuilt the call site. The package is
retained rather than deleted: it is the only implementation of the approved
[Context Analysis Request V1](../contracts/context-analysis-v1.md) and
[Planning Suggestions V1](../contracts/planning-suggestions-v1.md) contracts,
its deterministic tests still run in the gate, and the Option B-R slice below
needs its semantic-triage specialist. Wiring an entry point back is planned
work, not a current claim.

The model neither receives nor selects Calendar/list destinations and cannot
reach an outbound sender. Context collection and analysis remain read-only even
though separately approved outbound capabilities exist.

The active replacement slice is Option B-R:

- branch bounded native reads before archive persistence;
- expose inventory, compact, detail, and exact fresh-read levels with typed
  freshness and completeness;
- persist a minimal control/provenance ledger rather than communication bodies;
- treat source watchers as wake-up hints plus overlap and reconciliation;
- route bounded EvidenceBundles through Sherpa-managed specialists;
- compare candidates with active and completed Reminders and relevant Calendar
  occurrences before proposal and mutation;
- re-read exact evidence and Planner state immediately before execution.

The current archive is retained as a compatibility path until review, evidence,
coverage, and outbound target consumers have replacements. Its purge is a later
explicit owner decision.

Owner-operated gate: select an explicit time range, authorize only the needed
source, inspect the export, then explicitly confirm one on-device analysis.
Separately, prepare a message to a controlled self/test conversation, inspect
its full draft, and consume its one-time confirmation. Analysis does not
automatically write Calendar/Reminders or send a communication.

Mail.app is first changed to a bounded header-first batch plus selected body
fetch and benchmarked. A direct per-account adapter is added only when that
aggregate path misses its documented latency or coverage gate. IMAP owns query
and mailbox-state changes; SMTP owns submission. Each account requires explicit
OAuth or app-password configuration because Mail.app does not expose reusable
credentials.

## Distribution gate

Build a relocatable, precompiled release archive or bottle and install it with
a checksum-pinned Homebrew Formula. The Formula declares no runtime dependency
and installs one executable.
The packaged CLI then offers a separate explicit agent-host installation
command. No distribution step may require Developer ID, notarization, or a
toolchain on the user's machine. A missing compatible prebuilt artifact fails
as an unsupported platform instead of falling back to a local source build.

## Related

- [System architecture](../architecture/README.md)
- [Planner requirements](../requirements/planner-authority.md)
- [Context requirements](../requirements/context-intelligence.md)
- [Test strategy](../testing/README.md)
- [Requirement verification matrix](../testing/verification-matrix.md)
- [Owner-operated live validation](../testing/live-validation.md)
- [Context outbound and hybrid mail ADR](../adr/0003-context-outbound-and-mail-access.md)
- [Distribution requirements](../requirements/distribution.md)
- [Unsigned Homebrew distribution](../adr/0005-unsigned-homebrew-distribution.md)
- [Native fresh-read ADR](../adr/0004-native-fresh-read-context.md)
- [Archive migration RFC](../rfc/0001-context-archive-to-fresh-read.md)
- [Calendar invitation boundary proposal](../rfc/0004-calendar-invitation-boundary.md)
