---
id: ADR-0004
title: Native Fresh Read Context and Minimal Control Ledger
status: accepted
owner: maintainer
---

# ADR-0004: Native Fresh Read Context and Minimal Control Ledger

## Context

Sherpa currently performs bounded native reads, then copies normalized message
and mail content into an owner-only SQLite archive. Stable aliases, pending
review, immutable evidence revisions, analysis usage, and outbound target
resolution all depend on that archive.

The archive makes repeated analysis convenient, but it also creates a second
long-lived copy of highly sensitive communication and allows stale content to
become the default review path. It does not solve the more important planning
error: a plausible message can still create a duplicate Event or resurrect a
completed Reminder when current Planner state is not compared first.

Native sources expose different change hints. `imsg` and KakaoTalk have
monotonic new-record cursors, EventKit has coarse change notifications, and
Mail.app has no reliable durable change cursor. None is a common exactly-once
change log. A notification or cursor can reduce work but cannot prove that a
source range is complete or unchanged.

## Decision

Adopt **Native Fresh Read + Minimal Control/Provenance Ledger + Mandatory
Reconciliation**, abbreviated **Option B-R**.

Communication bodies and attachment content are not written to a long-lived
Sherpa archive. A read session obtains a bounded native snapshot and keeps exact
evidence in memory. An encrypted temporary spill is permitted only behind an
explicit byte limit and hard TTL. Inventory and compact projections are produced
deterministically before any model receives detail.

Rust persists only state required to resume or explain work:

- source checkpoint and source epoch;
- page/range completion receipt and short-TTL overlap digest;
- trigger job and retry state;
- analysis-profile and evidence-set receipt;
- PlanningCandidate, approval, DecisionTrace, and workflow/mutation journal.

The ledger must not become a per-message history of irrelevant content. A source
item gets durable provenance only when a surviving workflow needs it. A keyed
fingerprint and opaque locator token replace a durable body copy.

Watchers and notifications enqueue only a bounded wake-up hint. The coordinator
re-reads the source with overlap, periodically reconciles wider ranges, and
advances a checkpoint only after the corresponding processed-or-skipped receipt
is durable. Source instance or schema changes invalidate incompatible cursors.

Rust owns code-driven orchestration. It performs filtering, pagination, token
budgeting, evidence scoping, Planner reads, reconciliation, approval, mutation,
and read-back. Semantic specialists receive bounded EvidenceBundles and no
mutation capability. They may request additional detail only through a scoped,
limited read grant. The user-facing manager owns the final answer and approval
boundary.

Before a Context-derived candidate is proposed or executed, Sherpa fresh-reads
active and completed Reminders and relevant Calendar occurrences. It records one
typed reconciliation outcome. Immediately before mutation it re-reads exact
evidence and matched Planner items; a fingerprint change aborts execution and
requires re-planning.

The existing Context archive remains a compatibility implementation during the
migration. No automatic migration step deletes it. Purge remains a separate,
explicit owner operation after all consumers and rollback gates are closed.

This decision supersedes the archive-backed evidence and target-resolution
parts of [ADR-0003](0003-context-outbound-and-mail-access.md). ADR-0003's
two-phase outbound approval, exact target requirement, Mail.app-first strategy,
and `application_accepted` semantics remain in force.

## Consequences

- Every decision is based on a bounded current source read rather than a stale
  communication copy.
- Durable state is smaller and less sensitive, but still sufficient for crash
  recovery, duplicate suppression, approval, and mutation reconciliation.
- Byte-for-byte replay of deleted or later-edited historical source content is
  intentionally unavailable. DecisionTrace explains the observed scope,
  fingerprint, rules, findings, alternatives, approval, and outcome instead.
- Completeness becomes source- and scope-specific. KakaoTalk can be complete in
  the local database while account-wide completeness remains unknown.
- Exactly-once external mutation is not promised. Sherpa provides a durable
  intent, idempotency key, optimistic precondition, read-back, and
  `outcome_unknown` recovery.
- Outbound aliases require a live target directory or short-lived locator token
  because the content archive is no longer their permanent resolver.
- Supply remains different: normalized price, stock, shipping, and option
  observations are durable domain facts, while raw web artifacts remain TTL
  bounded.

## Rejected alternatives

- **Completely stateless reads:** cannot safely resume, suppress duplicate
  triggers, detect source epochs, preserve approvals, or recover uncertain
  mutations.
- **Keep the normalized content archive as the primary read model:** improves
  replay but preserves duplicate sensitive data and makes freshness a secondary
  concern.
- **Let every specialist search native sources freely:** weakens token, privacy,
  prompt-injection, and capability boundaries.
- **Treat streams as authoritative change logs:** misses edits, deletes,
  downtime, rotations, and source-specific incompleteness.
- **Delete the archive at cutover start:** breaks evidence, aliases, analysis
  coverage, and outbound target resolution before replacements are proven.

## Related

- [System architecture](../architecture/README.md)
- [Context requirements](../requirements/context-intelligence.md)
- [Fresh Context contract](../contracts/fresh-context-v1.md)
- [Fresh-read design](../design/native-fresh-read-context.md)
- [Archive migration RFC](../rfc/0001-context-archive-to-fresh-read.md)
- [Context outbound and hybrid mail ADR](0003-context-outbound-and-mail-access.md)

