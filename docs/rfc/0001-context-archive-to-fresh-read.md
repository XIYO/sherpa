---
id: RFC-0001
title: Context Archive to Native Fresh Read Migration
status: active
owner: maintainer
---

# RFC-0001: Context Archive to Native Fresh Read Migration

## Purpose

Move Context review and planning from an archive-backed pipeline to Option B-R
without losing existing outbound, approval, evidence, or recovery behavior.

This RFC authorizes additive implementation and shadow comparison. It does not
authorize deletion of the existing Context database or personal source data.

## Current coupling inventory

The current pipeline is:

```text
native bounded read
  → ContextCollectionService
  → ContextArchive/ContextMailArchive
  → stable aliases and immutable revisions
  → pending export
  → model allowlist
  → PlanningCandidate
```

The archive currently owns four distinct responsibilities that must be replaced
independently:

| Current responsibility | Replacement |
| --- | --- |
| Message/mail body read model | Ephemeral EvidenceStore populated by bounded native read |
| Pending and changed-revision coverage | Source checkpoint, page/range receipt, TTL overlap digest, analysis-profile digest |
| Stable K/I aliases and native outbound locator | Live target directory plus exact target revalidation |
| Durable evidence revision | Candidate-scoped opaque locator token, keyed fingerprint, evidence-set digest, DecisionTrace |

## Migration invariants

- Existing archive commands remain functional until their replacement is
  deterministic and live-validated.
- New fresh-read code never writes communication bodies to archive tables.
- Source workers never receive the control-ledger database path.
- The same native bounded-query safety limits apply to archive and fresh paths.
- Shadow comparison records counts, digests, completeness, latency, and errors;
  it never stores raw comparison content.
- No cursor advances before a processed-or-skipped page receipt commits.
- No Context-derived mutation executes without current Planner reconciliation
  and exact pre-mutation revalidation.
- Archive purge remains explicit and cannot be called by migration code.

## Delivery slices

### Slice 1: Contracts and shadow fresh read

Add the versioned fresh-read vocabulary, conservative completeness inference,
run-scoped references, and an application service that reads existing native
adapters without an archive. Expose an explicit shadow command or test boundary.

Exit gate:

- result limits cannot be described as complete;
- native IDs never enter public projection;
- no archive write occurs;
- deterministic chat and mail fixtures pass.

### Slice 2: Minimal control ledger

Add source checkpoints, source epoch, page/range receipt, trigger jobs, TTL
overlap digests, evidence-set analysis receipts, and DecisionTrace. Do not add a
durable row for every irrelevant source item.

Exit gate:

- crash before receipt does not advance the checkpoint;
- replay after receipt does not produce a second candidate;
- source epoch mismatch starts a bounded bootstrap;
- ledger and logs contain no source body or native identifier.

### Slice 3: Progressive evidence and orchestration

Implement inventory, compact, detail, and exact stages. Rust enforces byte,
record, token, tool-call, and deadline budgets. Deterministic triage precedes
semantic analysis. A planning specialist runs only for credible candidates.

Exit gate:

- specialist inputs contain only allowlisted run references;
- raw source instructions cannot change a tool grant;
- a zero-candidate review uses no planning specialist;
- context-too-large is rejected before model invocation.

### Slice 4: Planner reconciliation and stale protection

Read all currently authorized incomplete and completed Reminders for the present
scale and a candidate-dependent Calendar range. Add typed reconciliation
outcomes and exact evidence/Planner re-read immediately before mutation.

Exit gate:

- completed-item resurrection and duplicate proposal fixtures pass;
- new recurrence occurrence is not suppressed by an older completion;
- detached Calendar occurrence remains distinct from its series template;
- concurrent native change produces `stale`, not a mutation.

### Slice 5: Trigger lanes

Add source-specific bounded watchers only after the reconciliation path exists.
An `imsg` row ID or KakaoTalk log ID is an adapter checkpoint, not a public
cursor. EventKit and Mail use notification or polling wake-ups plus range
reconciliation.

Exit gate:

- watcher downtime is recovered by overlap and periodic reconciliation;
- duplicate and out-of-order triggers are harmless;
- watcher process cannot invoke a model or mutation capability.

### Slice 6: Consumer replacement

Replace archive dependencies in this order:

1. review/export and token benchmark;
2. model EvidenceBundle construction;
3. pending/analysis coverage;
4. PlanningCandidate evidence linkage;
5. K/I identity and outbound target resolution.

Archive commands then become explicitly legacy and read-only.

### Slice 7: Mail decision gate

Implement one Mail.app native batch for scoped headers and a second selected-body
batch. Benchmark representative ranges. If the documented p95 SLA or coverage
gate fails, add a direct IMAP adapter with mailbox, UIDVALIDITY, UID, optional
MODSEQ, and reconciliation state. SMTP stays separate.

### Slice 8: Archive retirement

Retirement requires all deterministic gates, owner-operated source validation,
a documented rollback period, and explicit owner approval. Only then remove
archive writes and later offer a separate purge command. Schema removal is a
subsequent release decision.

## Rollback

Until Slice 8, the composition root can select the legacy archive reader without
reingesting data. New ledger migrations are additive. A failed shadow or
fresh-read gate disables only that lane and leaves the existing archive path
available.

After archive purge there is no rollback to historical raw content. The purge
preview must state this explicitly.

## Measures

- source read latency p50/p95;
- source-read amplification;
- token per reviewed record and accepted candidate;
- actionable commitment recall and candidate precision;
- completed-Reminder resurrection and duplicate proposal rates;
- missed-trigger recovery and duplicate-trigger suppression;
- stale-evidence rejection and mutation read-back success;
- partial-as-complete rate, which must remain zero.

## Related

- [Native fresh-read ADR](../adr/0004-native-fresh-read-context.md)
- [Context requirements](../requirements/context-intelligence.md)
- [Fresh Context contract](../contracts/fresh-context-v1.md)
- [Fresh-read design](../design/native-fresh-read-context.md)
- [Verification matrix](../testing/verification-matrix.md)
