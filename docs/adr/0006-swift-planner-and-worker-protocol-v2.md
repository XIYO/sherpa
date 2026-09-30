---
id: ADR-0006-SWIFT-PLANNER-WORKER-V2
title: Swift Planner Semantic Authority and Worker Protocol V2
status: accepted
owner: maintainer
---

# Swift Planner Semantic Authority and Worker Protocol V2

> **완료되었고, 그 이상으로 갔다 (2026-08-27).** Planner 를 Swift 로 옮기고 Worker
> Protocol V2 를 세운다는 결정은 달성됐다. 그 뒤 Rust 제어 평면 자체가 사라져 본문의
> "Rust 가 오케스트레이션 권한을 유지한다"는 더 이상 사실이 아니다. 지금은 Swift 실행
> 파일 하나가 그 권한을 갖고, Protocol V2 는 프로세스 경계가 아니라 stdin JSON 계약으로
> 남았다. 현재 구조는 [아키텍처 문서](../architecture/README.md)에 있다.

## Decision

Sherpa uses Worker Protocol V2 for every production worker, with no V1 runtime
fallback. The machine-readable schema is the sole wire source of truth.

The Swift Planner Application is the semantic authority for Event and Reminder
commands. It decodes strict capability DTOs, validates the whole command or
candidate batch, invokes EventKit through a port, performs a fresh native read,
and compares native state with the requested semantics.

The Rust control plane remains the orchestration authority. It owns CLI syntax,
approval, idempotency, candidate freshness, worker supervision, correlation and
policy validation, safe-reference conversion, mutation journaling, canonical
SQLite storage, and public presentation. It does not independently reinterpret
Planner time, recurrence, alarm, URL, or read-back semantics.

Both sides independently validate the strict envelope and capability policy.
Context provenance and Supply capture integrity/provider parsing stay in Rust.

## Consequences

- Every request explicitly declares application contract, effect, evidence,
  artifact policy, deadline, correlation, and idempotency.
- Responses separate processing status, external effect, and evidence.
- A post-invocation boundary loss becomes `uncertain/may_have_applied` and is
  never automatically retried.
- A native effect followed by failed comparison remains `partial/applied`; a
  safe reference is persisted before the terminal journal transition.
- Capability discovery is the only response containing descriptors.
- EventKit imports and Apple-native vocabulary stay inside the adapter target.

## Rejected alternatives

- V1 fallback or dual dispatch, because it makes policy and retry meaning
  ambiguous during a mutation.
- Repeating semantic comparison in Rust, because two authorities can disagree
  on EventKit normalization and turn a verified effect into the wrong outcome.
- Letting Swift open Sherpa storage, because it would bypass reference,
  approval, and journal ownership.

## Related

- [System architecture](../architecture/README.md)
- [Worker protocol](../contracts/worker-protocol.md)
- [Planner authority requirements](../requirements/planner-authority.md)
- [Verification matrix](../testing/verification-matrix.md)
