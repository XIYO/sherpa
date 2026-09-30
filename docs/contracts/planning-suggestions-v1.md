---
id: CONTRACT-PLANNING-SUGGESTIONS-V1
title: Planning Suggestions V1
status: approved
owner: maintainer
---

# Planning Suggestions V1

## Boundary

Producer: isolated LLM analysis worker  
Consumer: `ContextPlanningSuggestionService`

The contract transports proposals, never privileged commands. Every non-manual proposal
must cite an exact Sherpa record and immutable revision reference. Provider-native IDs,
message bodies, credentials, prompts, and model reasoning must not appear in evidence
metadata. A locator is a short structural path such as `body` or `subject`; it is not a
quote.

The current Foundation Models adapter uses small one-based evidence handles only inside
its guided-generation process. Handles and source quotes are not fields in this contract.
The worker restores each handle to the exact allowlisted Sherpa record/revision pair before
serialization, so changing that internal grounding strategy does not change Version 1.

The consumer rejects unknown fields, unsupported actions, invalid dates, duplicate
proposal IDs, missing or mismatched revisions, and revisions that were never presented to
the analysis boundary. Valid suggestions become expiring `PlanningCandidate` previews.
They still require the exact `ap1_…` confirmation before EventKit or Reminders mutation.

The model never selects a native destination. This schema has no
`calendar_reference` or `list_reference` field, and its strict payload objects reject either
name as unknown. Before analysis, the user must select one complete `cal1_…` Calendar
reference and one complete `rl1_…` Reminder-list reference. Sherpa keeps those references
outside the model request and binds the appropriate exact destination into each validated
candidate. A candidate with a missing, short, ambiguous, or wrong-kind destination is
invalid and cannot be approved or executed.

The proposal array may be empty. That is the successful, non-hallucinating result when the
selected evidence contains no sufficiently supported Event or Reminder. Every non-empty proposal
must cite at least one exact evidence pair from the current analysis request.

Event timestamps in this contract are already deterministic projections, not unverified model
text. The current worker resolves explicit dates from the selected evidence content, verifies
timed start/end clocks against that same content, and normalizes all-day dates to a local
half-open range. An invalid generated entry is omitted before this contract is serialized and
is reported only by a content-free warning; every entry that reaches the consumer
must still pass the complete strict schema and allowlist checks.

Event and Reminder payloads may optionally carry provider-neutral `alarms` and
`recurrence_rules`. Their shapes mirror the writable EventKit concepts rather than Swift
types. The application validates frequency-specific selector combinations, bounds,
duplicates, and RFC 3339 instants before a candidate can be persisted. EventKit supports
one recurrence rule per item, so `recurrence_rules` contains at most one value. Omission
means no alarm or recurrence is requested; an empty array has the same meaning only on creation.

All proposals from one batch are persisted atomically. Validation and evidence checks finish
before the transaction begins; if any candidate conflicts or storage fails, no newly-created
candidate from that batch remains and the Context revisions are not marked analyzed.

Retries use `llm:<analysis_id>:<proposal_id>` as the candidate idempotency key. Reusing the
same key with different content is rejected. The unreleased V1 baseline was tightened to
remove destination fields entirely; no external V1 producer was supported before this
correction. After public release, Version 1 is additive only within optional fields;
removing fields, changing action semantics, or relaxing the evidence pair requires a new
major schema.

This contract has no checked-in machine-readable schema. The
`protocols/planning-suggestions-v1.schema.json` it used to cite was deleted with
the Rust control plane when the runtime moved to Swift, and no gate validates
this payload against a JSON Schema today. The producing shape lives in
`GeneratedPlanning.swift` in `apple/foundation-models-service`, which serializes
the `sherpa.planning-suggestions.v1` batch and whose tests the repository gate
runs. The `ContextPlanningSuggestionService` consumer named above has no Swift
implementation, and no CLI entry point reaches the producing worker, so nothing
consumes this contract today; see Phase 2 of the [roadmap](../roadmap/README.md).

## Related

- [Context Analysis Request V1](context-analysis-v1.md)
- [Context requirements](../requirements/context-intelligence.md)
- [Planner requirements](../requirements/planner-authority.md)
