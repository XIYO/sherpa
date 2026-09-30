---
id: CONTRACT-FRESH-CONTEXT-V1
title: Fresh Context Contract V1
status: active
owner: maintainer
---

# Fresh Context Contract V1

## Boundary

This contract describes Sherpa-owned requests, source-page metadata, ephemeral
evidence, agent findings, Planner reconciliation, and durable decision records.
It does not replace Worker Protocol V2. Source-specific worker payloads remain
inside the adapter boundary and map into these owned types.

## Shared coverage types

```text
CountV1
  value: optional non-negative integer
  quality: exact | lower_bound | estimated | unknown

CompletenessV1
  complete_in_scope
  partial_limit
  partial_timeout
  partial_source_unavailable
  source_incomplete
  permission_denied
  unsupported
  unknown

FreshnessV1
  observed_at
  source_as_of: optional timestamp
  revalidated_at: optional timestamp
```

`complete_in_scope` is legal only when the adapter can prove that every record
inside the declared scope was considered. A result that exactly meets any chat,
thread, record, byte, or token limit is conservatively `partial_limit` unless a
source-native exact count proves otherwise.

## `FreshReadRequestV1`

```text
schema: sherpa.fresh-read.request.v1
request_id
source
lane
scope:
  from_utc
  to_utc
  thread_reference: optional run or Sherpa reference
level: inventory | compact | detail | exact
page_budget:
  max_records
  max_bytes
  max_estimated_tokens
cursor: optional RunPageCursorV1
freshness_requirement
deadline_ms
```

Validation rejects invalid half-open ranges, empty identifiers, unknown source
lanes, zero or excessive budgets, an expired cursor, and a cursor whose query
digest differs from the request.

## `FreshReadPageV1`

```text
schema: sherpa.fresh-read.page.v1
request_id
read_session_id
source
source_instance
scope
observed_at
source_as_of
matched_count: CountV1
emitted_count
remaining_count: CountV1
completeness: CompletenessV1
truncated
next_cursor: optional RunPageCursorV1
warnings
unavailable_lanes
records
page_digest
```

Inventory and compact records cannot contain raw bodies or native locators.
Detail and exact records move immediately into the Ephemeral EvidenceStore; a
public renderer receives run references only.

## Cursor separation

`RunPageCursorV1` is an expiring, query-bound position inside one read session.
It may be shown to a trusted caller but is never a source checkpoint.

`SourceCheckpointV1` is durable, adapter-owned control state:

```text
source
lane
source_instance
cursor_kind
native_high_water: opaque encrypted value
last_committed_receipt
overlap_start
captured_at
last_reconciled_at
adapter_version
source_schema_signature
```

It is not exposed to a model or public output. Changing `source_instance` or an
incompatible schema signature invalidates the native high-water.

## `TriggerEnvelopeV1`

```text
schema: sherpa.context-trigger.v1
trigger_id
source
lane
source_instance
source_checkpoint_hint
observed_at
reason
scope_hint
priority
analysis_profile
dedup_key
expires_at
```

It contains no body and grants no read, model, or mutation authority. Consuming
it always starts a fresh bounded read.

## Evidence contracts

`EvidenceManifestV1` contains scope, coverage, compact signals, estimated sizes,
freshness, keyed fingerprints, contradictions, missing lanes, budget, and
expiry. It contains no raw body.

`EvidenceBundleV1` contains the allowlisted exact or surrounding source data for
one specialist. Every content field is labelled `untrusted_source_data`. Its
optional read grant restricts source, scope, record references, bytes, tokens,
calls, deadline, and expiry.

`AgentFindingV1` contains claims, typed candidate facts, evidence and
counter-evidence references, assumptions, ambiguities, missing information,
confidence band, suggested next read, and suggested outcome. It cannot contain
a mutation approval, native locator, command, hidden reasoning, or copied full
transcript.

## Planner reconciliation

`ReconciliationOutcomeV1` has exactly one of:

```text
create
link_existing
already_completed
already_scheduled
cancelled
superseded
reopened
ambiguous
insufficient_evidence
```

It also records selected and rejected Planner matches, deterministic rules,
coverage, freshness, preconditions, required approval, idempotency key, and
expiry. Semantic similarity alone cannot select `create`.

`PlanningCandidateV2` adds the evidence-set digest, reconciliation outcome,
Planner references, expected evidence and Planner fingerprints, risk, approval
state, idempotency key, and expiry. Its execution states are `draft`,
`awaiting_approval`, `approved`, `executing`, `completed`, `stale`, `rejected`,
and `failed`.

## `DecisionTraceV1`

DecisionTrace is an explainable provenance record, not a log or hidden
chain-of-thought. It stores:

```text
trace and candidate references
outcome and confidence band
source coverage and unavailable lanes
evidence references and keyed fingerprints
Planner matches
deterministic rule evaluations
structured agent findings
assumptions, alternatives, uncertainties, missing information
approval, mutation, and read-back status
policy, adapter, and agent-profile versions
raw_content_retained: false
```

Operational logs may contain trace ID, capability, counts, latency, safe error
code, and outcome class only.

## Retry and idempotency

- Fresh reads are side-effect-free and may retry within the same captured
  high-water.
- A page receipt commits before its source checkpoint advances.
- Trigger deduplication suppresses repeated wake-ups but never suppresses a
  required periodic reconciliation.
- A candidate idempotency key covers semantic intent, evidence-set digest,
  Planner snapshot digest, and recurrence occurrence.
- External mutation uses at-least-once recovery semantics with an idempotency
  key, optimistic precondition, durable journal, and native read-back.
- A lost mutation response becomes `outcome_unknown`; blind retry is forbidden.

## Related

- [Worker protocol](worker-protocol.md)
- [Planning suggestions](planning-suggestions-v1.md)
- [Context requirements](../requirements/context-intelligence.md)
- [Native fresh-read ADR](../adr/0004-native-fresh-read-context.md)
- [Fresh-read design](../design/native-fresh-read-context.md)
