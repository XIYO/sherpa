---
id: DESIGN-NATIVE-FRESH-CONTEXT
title: Native Fresh Read Context Design
status: active
owner: maintainer
---

# Native Fresh Read Context Design

## Component flow

```text
native source
  → source worker: bounded provider query
  → FreshReadCoordinator: validate, sort, infer coverage
  → deterministic inventory and compact triage
  → Ephemeral EvidenceStore: selected detail/exact only
  → specialist manager: scoped EvidenceBundles
  → live Planner snapshot and reconciliation
  → approval
  → exact evidence and Planner revalidation
  → journaled native mutation and read-back
```

The control ledger sits beside this flow. Workers never write it and models
never see its cursor, source epoch, locator token, or secret used for keyed
fingerprints.

## Application ownership

The application core owns `FreshContextSource`, `FreshReadCoordinator`,
`ControlLedgerPort`, `EvidenceStore`, `SpecialistPort`, `PlannerSnapshotPort`,
`ReconciliationService`, and `DecisionTracePort`. Adapter names such as EventKit,
`imsg`, KakaoTalk SQLCipher, Mail.app, or IMAP do not appear in those port names.

The first implementation reuses the existing bounded chat and mail adapters.
The fresh path branches before `ContextArchive` and `ContextMailArchive` and
therefore performs no content persistence. Adapter-specific cursor support is
added behind the same application port after shadow reads are correct.

## Conservative completeness inference

For a source without an exact native count, the coordinator declares
`partial_limit` when any of these conditions is true:

- emitted records equal the total-record limit;
- distinct emitted sessions equal the session limit;
- any emitted session equals its per-session record limit;
- emitted bytes or estimated tokens reach their budget;
- the adapter reports truncation.

Otherwise a bounded query may be `complete_in_scope` only if the adapter states
that its discovery step considered the full requested scope. Unknown source
coverage remains `unknown` or `source_incomplete`, never complete.

## Progressive evidence

Inventory contains counts, times, source lane, change signal, estimated cost,
freshness, and completeness. Compact contains run reference, time, session
alias, direction, record kind, attachment presence, and deterministic signal
flags. Detail adds the selected body and bounded neighbors. Exact contains only
the minimum source record and metadata needed for the final decision.

Page boundaries occur at a record or session boundary. Sherpa preflights tokens
using the actual model tokenizer and reserves output and tool-schema capacity.
The main conversation is not copied into specialist runs.

## Trigger processing

```text
wake-up hint
  → deduplicate trigger job
  → validate source instance and checkpoint
  → capture high-water
  → apply bounded overlap
  → read and triage pages
  → commit processed-or-skipped receipt
  → advance checkpoint
```

A crash before the receipt replays the page. A crash after the receipt but
before checkpoint advancement replays safely through the receipt/idempotency
check. Periodic reconciliation bypasses trigger deduplication and repairs missed
wake-ups.

## Agent routing

Sherpa does not fan every review out to multiple models.

1. Deterministic rules remove clearly irrelevant records and identify explicit
   dates, actions, cancellations, completion language, and links.
2. A semantic triage specialist runs only for unresolved relevance.
3. A planning specialist runs only when an actionable commitment remains.
4. A verifier runs only when specialists disagree or Planner matching is
   ambiguous.
5. The user is asked only when a material ambiguity remains after bounded
   additional reads.

All specialist outputs are schema-bound findings. Source text cannot grant a
tool, change a policy, select a destination, approve a mutation, or invoke
another agent.

## Planner snapshot policy

At the current measured size, every reconciliation reads all authorized active
and completed Reminders into an ephemeral compact snapshot. Calendar queries use
the evidence time, proposed time, and recurrence neighborhood rather than one
hard-coded global window. Sherpa sorts and validates EventKit results.

Match features include subject/action, counterpart, source thread, proposed
interval, location, recurrence, series and occurrence identity, completion or
cancellation chronology, current state, and exact references. A specialist may
propose a semantic relation; Sherpa decides whether deterministic preconditions
permit an outcome.

## Exact revalidation

Approval captures the evidence fingerprint, Planner match fingerprint,
candidate version, and Planner observation time. Immediately before mutation:

1. re-read each exact evidence record through its opaque locator token;
2. re-read every selected Planner item;
3. recompute the candidate and idempotency key;
4. abort as `stale` if any required fingerprint differs;
5. otherwise journal intent, mutate, and perform native read-back.

## Mail policy

Mail.app uses one native operation to limit accounts/mailboxes and return
headers, followed by one bounded operation for selected bodies. Host-side
per-message property traversal is not the target implementation. Latency,
coverage, and timeout rates determine whether direct IMAP is added; repeated
timeout workarounds do not replace the decision gate.

## Privacy and retention

- exact communication content: memory or encrypted TTL spill only;
- control ledger: encrypted owner-only durable state;
- DecisionTrace: references, fingerprints, rules, and outcomes only;
- operational telemetry: safe identifiers, counts, latency, and error classes;
- raw shopping artifact: bounded TTL.

## Related

- [Context requirements](../requirements/context-intelligence.md)
- [Native fresh-read ADR](../adr/0004-native-fresh-read-context.md)
- [Fresh Context contract](../contracts/fresh-context-v1.md)
- [Archive migration RFC](../rfc/0001-context-archive-to-fresh-read.md)
- [System architecture](../architecture/README.md)

