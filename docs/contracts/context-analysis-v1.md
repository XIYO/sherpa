---
id: CONTRACT-CONTEXT-ANALYSIS-V1
title: Context Analysis Request V1
status: approved
owner: maintainer
---

# Context Analysis Request V1

## Boundary

Producer: `ContextAnalysisService`  
Consumer: isolated on-device analysis worker

The request sends one explicitly selected, bounded CCT or MCT transcript to a
model adapter. It includes the complete allowlist of immutable evidence pairs
contained in that transcript. The adapter has no Calendar, Reminders, source
reader, shell, network, or database capability.

The exact writable `cal1_…` Calendar and `rl1_…` Reminder-list destinations are
selected at the CLI boundary but never enter this request. Sherpa retains them in
the trusted application flow. Destination fields do not exist in the strict
model-output schema, and Sherpa binds the appropriate full reference only after
the response passes schema and evidence validation. Thus neither transcript
content nor model output can redirect an approved mutation to another native
container.

The current adapter uses Apple Foundation Models on-device guided generation.
Its `capabilities` request checks availability without sending content or
running inference. `context.planning.analyze` is invoked only after the exact
`ANALYZE_CONTEXT_WITH_LOCAL_MODEL` confirmation.

Before generation, the Swift boundary validates every CCT/MCT row against the
request allowlist and removes the opaque record/revision suffixes. It replaces
each pair with a one-based ephemeral integer in request order. The guided model
selects only those small integers; it never sees or reproduces a provider ID or
Sherpa reference. These handles exist only inside the worker. The deterministic
mapper rejects zero, duplicate, and out-of-range handles and restores the exact
immutable pair before constructing the public suggestion response.

The model may suggest a normalized date or clock, but that value is not trusted
as source evidence. For all-day and timed Events, the mapper reads only the
content selected by the ephemeral handles, resolves an explicit calendar date
there, verifies both timed clocks there, and emits a canonical local range. A
single grounded date can correct a model date guess; absent or ambiguous dates
and ungrounded clocks reject that intermediate proposal. All-day ranges use an
exclusive next-day boundary calculated with the local calendar, including DST
transitions.

Guided generation may contain both valid and invalid intermediate proposals.
The worker maps them independently, omits invalid entries with content-free
`analysis.omitted.<rule>` warnings, and returns one strict Planning Suggestions
V1 batch containing only validated proposals. The public batch itself remains
atomic; partial validation is never delegated to the storage layer.

The application core requires every restored evidence
pair to belong to this exact request. A revision presented by an older analysis
is insufficient. A valid analysis may return zero proposals; absence is safer
than inventing a plan. Non-empty results must conform to
[Planning Suggestions V1](planning-suggestions-v1.md) and become approval-gated
PlanningCandidates rather than native mutations.

Hard limits are 1 MiB of UTF-8 transcript data, 4,096 distinct evidence pairs,
and 64 proposals. The implementation enforces those byte and semantic limits in
addition to the strict decoded shape.

After Sherpa validates a response, it first stores the complete PlanningCandidate
batch in one transaction. Only after that succeeds does it store a safe
analysis-run record and link it to every exact record/revision pair presented in
this request. Candidate persistence failure therefore leaves the evidence
pending instead of losing actionable findings. The link, rather than the
mutable item's current row, is the source of analysis coverage. A replay of
unchanged revisions is therefore no longer pending, while a revision created
before or after completion remains pending until that exact revision is
separately presented and analyzed. Run metadata contains only the analysis ID,
source, adapter, proposal count, completion time, and revision links; it does
not contain transcript text or model output.

This contract has no checked-in machine-readable schema. The
`protocols/context-analysis-request-v1.schema.json` it used to cite was deleted
with the Rust control plane when the runtime moved to Swift, and no gate
validates either payload against a JSON Schema today. The strict shapes now
live in Swift: `AnalysisPayload` decodes `sherpa.context-analysis-request.v1`
against a closed key set and enforces the byte and semantic limits above, and
`GeneratedPlanning` serializes the `sherpa.planning-suggestions.v1` batch. Both
are in `apple/foundation-models-service`, whose tests the repository gate runs.

The `ContextAnalysisService` producer named above has no Swift implementation.
No CLI entry point reaches this worker, so the deterministic evidence covers
the worker's inside only; see Phase 2 of the [roadmap](../roadmap/README.md).

## Related

- [Context requirements](../requirements/context-intelligence.md)
- [Planning Suggestions V1](planning-suggestions-v1.md)
- [Worker protocol](worker-protocol.md)
