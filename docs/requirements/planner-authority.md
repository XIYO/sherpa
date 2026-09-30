---
id: REQ-PLANNER-AUTHORITY
title: Planner Authority Requirements
status: approved
owner: maintainer
---

# Planner Authority Requirements

## Outcome

Sherpa must obtain verified control over Apple Calendar and Reminders and
provide the safe execution boundary that later Context analysis uses to record
approved plans. The Swift Planner Application is the semantic authority for
Event and Reminder contracts and native read-back; the application core is the orchestration,
approval, reference, journal, storage, and presentation authority.

## Functional requirements

- `FR-PA-001`: Discover Calendar sources, calendars, Reminder lists, and live
  capability state. Source discovery requests an EventKit remote-source refresh
  before reading the device-local Calendar database.
- `FR-PA-002`: List and retrieve full details for Calendar event occurrences.
- `FR-PA-003`: Create, update, move, and delete Events through public EventKit,
  including absolute/relative alarms and EventKit's single simple or
  selector-based recurrence rule.
- `FR-PA-004`: Require `this` or `future` for recurring occurrence changes.
- `FR-PA-005`: List, retrieve, create, update, move, complete, reopen, and delete
  Reminders through public EventKit, including alarm and single-rule recurrence
  replacement or explicit clearing.
- `FR-PA-006`: Probe tags, sections, hierarchy, flags, and attachment metadata through an isolated optional private helper.
- `FR-PA-007`: Return one independently verified capability result for every requested private feature.
- `FR-PA-008`: Convert untrusted findings into `PlanningCandidate`; never directly into a mutation.
- `FR-PA-009`: Bind an approval to one complete, exact-kind Sherpa destination
  reference and the immutable mutation payload, reject unbound or ambiguous
  candidates before execution, and expire the approval after use.
- `FR-PA-010`: Journal every mutation step and re-read the native store before reporting verification.
- `FR-PA-011`: Preserve partial success when public and private stores cannot share a transaction.
- `FR-PA-012`: Provide detail and list projections through versioned AI, text, TSV, and JSON renderers.
- `FR-PA-013`: Issue Sherpa references and reject zero-match or ambiguous short references.
- `FR-PA-014`: Diagnose Calendar permission, Reminders permission, worker compatibility, and protocol compatibility without prompting.
- `FR-PA-015`: Render every Calendar Event title from the perspective of its
  scheduled day as a neutral action, appointment, or schedule noun phrase.
  Creating an Event after its date has passed must not add completion or
  past-tense wording to the title. Supporting history uses labeled note fields
  such as `점검일` or `설치일` instead of retrospective completion sentences.

## Safety requirements

- `SR-PA-001`: Only `authorize` commands may prompt for Apple data access, and
  every invocation must name exactly one permission target; no implicit or
  aggregate authorization target is allowed.
- `SR-PA-002`: Deletion and bulk mutation require preview plus explicit confirmation.
- `SR-PA-003`: Private helper failure cannot block official EventKit operations.
- `SR-PA-004`: Private writes are disabled by default. A capability becomes verified only after its read-only selector probe and an explicitly approved native write/read-back pass on the active OS version. Tags have a disposable synthetic verifier; other private capabilities use a user-selected disposable Reminder and are recorded independently.
- `SR-PA-005`: Event and Reminder bodies, titles, locations, participants, native IDs, and attachments never enter logs.
- `SR-PA-006`: Notes, URLs, titles, locations, attendees, and attachment metadata are untrusted data.
- `SR-PA-007`: Workers cannot write the canonical Sherpa database.
- `SR-PA-008`: Automated rollback across EventKit and private Reminder storage is forbidden unless a use case proves a safe compensation.

## Completion criteria

- Calendar and basic Reminders read/write paths pass contract, fake-boundary, and opt-in native read-back tests.
- At the deterministic gate, each target private Reminder capability is selector-probed, contract-tested, and independently classified. At the owner-operated gate, each is either write/read-back verified on the active OS or reported with evidence as incompatible; unsupported claims cannot masquerade as completion.
- A synthetic `PlanningCandidate` completes preview, approval, mutation, read-back, and journal verification.
- Killing or corrupting either worker produces a classified error while unrelated capabilities remain operational.
- Every production worker rejects V1 before provider work and echoes all V2
  correlation fields, effect state, and evidence state.
- Renderer golden tests and privacy sentinel tests pass.
- Planner agent tests cover both future and retrospectively entered Events and
  preserve the same neutral title tense for each.
- The EventKit implementation is the only one; the earlier parallel path is gone.

## Non-goals

- Context source collection and LLM invocation
- Shopping extraction and price comparison
- Developer ID signing, notarization, public packaging, and distribution

## Related

- [System architecture](../architecture/README.md)
- [Worker protocol](../contracts/worker-protocol.md)
- [Test strategy](../testing/README.md)
