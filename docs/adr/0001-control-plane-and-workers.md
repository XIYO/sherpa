---
id: ADR-0001
title: Rust Control Plane with Language-Native Workers
status: superseded
owner: maintainer
---

# ADR-0001: Rust Control Plane with Language-Native Workers

> **Superseded (2026-08-27).** Rust 제어 평면은 Swift 로 대체되었고, 언어별 워커 경계도
> 함께 사라졌다. 남은 것은 EventKit·Mail·iMessage·KakaoTalk 를 직접 다루는 단일 네이티브
> 실행 파일이다. 이 문서는 그 결정을 왜 내렸는지에 대한 기록으로만 남는다.

## Context

Sherpa must coordinate Apple frameworks, private optional macOS capabilities,
local communication sources, web extraction, LLM planning, approvals, and
recoverable multi-step mutations. Direct Rust bindings made the initial
EventKit vertical slice work but placed Apple ownership and conversion details
inside the control-plane workspace.

## Decision

Rust owns domain policy, use cases, orchestration, references, canonical local
state, journals, worker supervision, and presentation. Framework-native or
ecosystem-native implementations run as bounded child processes behind an
application-owned capability port and a versioned protocol.

- Swift owns public EventKit integration.
- A separate Swift/Objective-C process owns opt-in private Reminder capabilities.
- Python owns provider-specific web extraction.
- Rust embeds none of those language runtimes or framework bindings.

Sherpa permanently uses identity-free ad-hoc signatures rather than Developer
ID signing or notarization. The system must report that privacy permission
identity may not survive an unsigned rebuild or Homebrew upgrade.

## Consequences

- Process and wire-contract code becomes a permanent boundary.
- Worker startup, timeout, cancellation, crash, stdout contamination, and
  protocol mismatch must be first-class failures.
- Cross-worker mutations cannot be atomic and require explicit partial outcomes.
- Each worker can use its ecosystem naturally and can be replaced independently.
- Private framework instability cannot terminate the Rust process or EventKit worker.

## Rejected alternatives

- **Rust bindings for every integration:** concentrates foreign-function and
  runtime-specific complexity in the control plane.
- **Swift as the product core:** improves Apple integration but weakens the
  intended portable orchestration boundary and Python worker symmetry.
- **In-process Python or private framework loading:** expands the trusted
  process and defeats failure isolation.
- **One universal provider item:** erases domain semantics and capability limits.

## Related

- [System architecture](../architecture/README.md)
- [Planner requirements](../requirements/planner-authority.md)
- [Worker protocol](../contracts/worker-protocol.md)
- [Conservative Supply comparison](0002-conservative-supply-comparison.md)
- [Unsigned Homebrew distribution](0005-unsigned-homebrew-distribution.md)
