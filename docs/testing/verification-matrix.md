---
id: TEST-SHERPA-TRACEABILITY
title: Sherpa Requirement Verification Matrix
status: active
owner: maintainer
---

# Sherpa Requirement Verification Matrix

> **재검증 결과 (2026-08-27).** 요구사항 70 개를 실제 테스트와 대조했다.
>
> 런타임이 Rust 에서 Swift 로 옮겨가면서 워커 프로세스 경계와 그 위에 얹혀 있던 테스트
> 인프라가 통째로 사라졌는데, 매트릭스는 여전히 그것들을 증거로 내세우고 있었다 —
> `probes.rs`, release probe, architecture gate, CLI black-box, cross-language fixture.
> `Tests/` 에서 프로세스를 띄우는 파일은 **0 개**다. 존재할 수 없는 증거를 `D ready` 로
> 두는 것은 검증되지 않은 것을 검증됐다고 말하는 것이다.
>
> **25 개를 `D stale` 로 낮췄다.** 사유는 각 행에 적었다. 이 항목들은 요구가 틀렸다는
> 뜻이 아니라 증거가 사라졌다는 뜻이다. 다시 증명하거나 요구를 접어야 한다.
>
> **배포 10 개는 실제 구현으로 다시 썼다.** `scripts/check-release.sh` 가 매 게이트마다
> 패키징·Formula 렌더·Homebrew 설치·`brew test` 를 실제로 돌리므로, 이 영역은 주장이
> 아니라 실행으로 뒷받침된다.
>
> **남은 `D ready` 는 표본 대조를 거쳤다.** EventKit locator·occurrence·filter, KakaoTalk
> bounds, DST, identity-map 등은 대응 테스트가 `Tests/` 에 실재한다. 다만 요구마다 어느
> 테스트가 무엇을 증명하는지 1:1 로 문서화되어 있지는 않다. 그 매핑이 다음 일이다.

> **추가 (2026-09-21).** `apple/foundation-models-service` 를 증거로 삼던 3 행
> (`FR-CX-009`·`FR-CX-016`·`SR-CX-010`)을 다시 낮췄다. 그 패키지의 테스트 34 개는 게이트가
> 실제로 돌리고 통과하지만, CLI 에 이 워커로 들어가는 진입점이 없다 — 증명되는 것은 워커
> 안쪽뿐이고 제품 경로는 아니다. 같은 이유로 그 3 행의 `L` 은 지금 없는 Rust 경로에서 얻은
> 것이라 `legacy` 로 적는다. 패키지는 승인된 계약 둘의 유일한 구현이라 보존한다
> (`docs/roadmap/README.md` Phase 2).

## Meaning of status

- `D`: deterministic implementation and synthetic evidence required by `scripts/check-all.sh`.
- `L`: owner-operated evidence from the unsigned binary, following
  [live validation](live-validation.md).
- `ready` means the implementation and deterministic test exist. `pending`
  means Sherpa deliberately waits for the owner to grant access, select data,
  invoke a model, or open a marketplace profile.

The live column is not a second implementation backlog. It is evidence about
TCC state, the current macOS/private framework, personal source availability,
or current marketplace behavior that cannot be manufactured by a deterministic
test.

## Planner Authority

| Requirement | Implementation evidence | Deterministic evidence | Status |
| --- | --- | --- | --- |
| `FR-PA-001` | Application ports in calendar.rs and reminder.rs; EventKit dispatch in [EventKitWorker.swift](../../apple/eventkit-service/Sources/SherpaEventKitAdapter/EventKitWorker.swift) | Swift protocol/capability tests and release process probes in probes.rs | D stale — evidence names test infrastructure that no longer exists; re-verification required |

| `FR-PA-002` | Occurrence-aware event locator and full snapshot mapping in [EventLocator.swift](../../apple/eventkit-service/Sources/SherpaEventKitAdapter/EventLocator.swift) and [Snapshot.swift](../../apple/eventkit-service/Sources/SherpaEventKitAdapter/Snapshot.swift) | Event locator round-trip tests plus application detail-preservation test | D ready; [L verified](live-evidence.md) |

| `FR-PA-003` | Calendar create/update/move/delete, alarm, and recurrence use cases and EventKit adapter; source-owned verification can create and remove its own disposable Calendar; read-back recognizes Foundation's `UTC`→`GMT` canonicalization without weakening non-UTC zone identity | Domain combination and UTC-alias tests, Swift parser tests, application read-back tests, safe-reference destination lifecycle tests, and owner-gated schedule-aware CRUD verifier | D ready; [L verified v4](live-evidence.md) |

| `FR-PA-004` | Explicit `EventSpan` validation and wire mapping | Occurrence locator and command validation tests | D ready; [L verified with future span](live-evidence.md) |

| `FR-PA-005` | Reminder list/detail/create/update/move/complete/reopen/delete plus alarm and recurrence use cases and EventKit adapter; source-owned verification can create and remove its own disposable Reminder list; ReminderDate read-back shares the strict UTC-link canonicalization rule | Filter, duplicate/limit/malformed output, schedule and date-component validation/read-back, UTC-alias, safe-reference destination lifecycle, protocol, and owner-gated schedule-aware CRUD verifier tests | D ready; [L verified v4](live-evidence.md) |

| `FR-PA-006` | Isolated private helper and private Reminder application service; section assignment resolves only an existing section and cannot create list structure | Selector/capability probes, scalar-ABI and section-creation-selector gates, all-six write-disabled release-process routes, credential-URL rejection, content-addressed image staging, and fake-port tests | D stale — evidence names test infrastructure that no longer exists; re-verification required |

| `FR-PA-007` | Per-capability state and verification in capability.rs, keyed by macOS plus helper implementation revision, with classified provider failures and separate write/read evidence types | Exact-environment/revision, no-probe-on-invalid-environment, stale-helper CLI rejection, persisted timestamp, report normalization, and evidence-store failure tests | D ready; [L all six verified for v8 environment](live-evidence.md) |

| `FR-PA-008` | Planning types and port in planning.rs | Context suggestion and workflow tests prove proposals do not mutate | D ready; L not required |

| `FR-PA-009` | Exact-kind destination validation in planning.rs, pre-claim execution validation, expiring single-use candidate storage in storage planning.rs, and candidate-level operation/outcome recovery metadata | Missing, short, wrong-kind, and legacy-unbound destination rejection plus exact confirmation, expiry, idempotency, single-use, partial-create, and post-mutation finalization-failure tests | D ready; L pending end-to-end |

| `FR-PA-010` | Journaled application mutations, application-owned history query, native read-back, and safe affected-reference retention across Calendar, Reminder, private Reminder, and PlanningCandidate partial-create paths | Journal transition, history-query validation, partial-create recovery across journal and candidate outcome, read-back mismatch, renderer, and Planning workflow tests | D ready; [L public and all private capabilities verified](live-evidence.md) |

| `FR-PA-011` | `MutationOutcome` partial state, separately reported capability-evidence persistence, and no cross-store rollback | Timeout/read-back/private evidence-store failure tests | D ready; [L partial native failures observed and recovered](live-evidence.md) |

| `FR-PA-012` | Versioned renderers in presentation with explicit public JSON projections; Planner detail v2 preserves full recurrence while AI uses a compact nested schema | Exact JSON contract plus AI/text/TSV renderer tests and generic-serialization architecture gate | D stale — evidence names test infrastructure that no longer exists; re-verification required |

| `FR-PA-013` | Reference decorator and store | Exact, unique-prefix, zero-match, wrong-kind, and ambiguity tests | D ready; L not required |

| `FR-PA-014` | Public `status` depends only on EventKit; private state belongs to non-prompting `capabilities` and degradable Planner doctor v2 diagnostics; authorization status and request results share the four public output formats | Renderer and CLI-format tests, release process probes, corrupt-private public-status test, and real CLI missing-worker doctor test with typed authorization errors and surviving provider results | D stale — evidence names test infrastructure that no longer exists; re-verification required |

| `SR-PA-001` | Permission calls are exposed only by `authorize`; one explicit target is required and no aggregate target exists; normal services check status | Missing/aggregate-target CLI rejection, denied-access application test, command routing, and release-binary usage-description/ad-hoc-signature checks | D stale — evidence names test infrastructure that no longer exists; re-verification required |

| `SR-PA-002` | Destructive commands and verification flows require either an explicit disposable destination or an explicit source for a Sherpa-owned disposable destination, plus exact previews/confirmations; approved recurring Calendar verification updates/deletes the future series and checks both occurrence windows for residue | CLI mutually exclusive destination/source parsing, preview projection, zero-write rejection, partial-create cleanup, future-span cleanup, Reminder deletion re-read, residue, and workflow confirmation tests | D ready; [L public v4 and private tags verified](live-evidence.md) |

| `SR-PA-003` | EventKit and private ReminderKit are separate worker processes; shared supervision classifies missing, corrupt, stale, timed-out, and failed providers without blocking healthy operations | Architecture gate; timeout, post-exit, cooperative-cancellation, and real CLI SIGINT descendant cleanup tests; protocol-failure, unavailable, stale-revision, public status, and Reminder output isolation tests | D stale — evidence names test infrastructure that no longer exists; re-verification required |

| `SR-PA-004` | Private write environment gate, separately rendered current policy, selector and scalar-ABI probes, OS-and-helper-revision-scoped evidence, read-back, and explicit `not_recorded` evidence state | All-six disabled-write process probes, stale-revision rejection, enabled/disabled doctor policy tests, orchestration confirmation, v2 renderer, and per-capability tests | D stale — evidence claims a process-level test; none exists in Tests/ |

| `SR-PA-005` | Safe structured logging omits payloads and native identifiers; CLI errors render only the reviewed outer message rather than expanding internal causes | Real CLI debug-log sentinel, internal-chain sentinel, and bounded worker-diagnostic tests prove Event content, native IDs, worker stderr, and nested causes stay out of public diagnostics | D stale — evidence names test infrastructure that no longer exists; re-verification required |

| `SR-PA-006` | Application validates titles, notes, URLs, locations, dates, zones, and attachment artifacts | Invalid optional field and artifact tests | D ready; L not required |

| `SR-PA-007` | Adapters receive protocol DTOs, never the canonical database path; canonical state uses the shared owner-only, non-symlink SQLite boundary | Dependency/source-boundary gates plus canonical directory, DB, and sidecar permission/symlink tests | D stale — evidence names test infrastructure that no longer exists; re-verification required |

| `SR-PA-008` | Partial outcomes are retained; no automatic cross-provider compensation exists | Partial mutation tests and journal assertions | D ready; [L private partial outcomes retained](live-evidence.md) |

## Context Intelligence

| Requirement | Implementation evidence | Deterministic evidence | Status |
| --- | --- | --- | --- |
| `FR-CX-001` | Source-neutral collection and outbound ports with independently resolved isolated implementations under macOS Context | Source identity, per-capability readiness, and process contract tests | D stale — evidence claims a process-level test; none exists in Tests/ |

| `FR-CX-002` | Collection limits and half-open ranges in Context domain, including range-aware iMessage chat selection and Mail's one-message-per-thread mapping | Bounds, range, out-of-range-newer-chat discovery, Mail native-limit, fixture-reader, malformed, and oversized tests | D ready; L pending |

| `FR-CX-003` | Normalized messages/mail retain text and attachment metadata without paths/binaries | Domain bounds and source mapping tests | D ready; L pending inspection |

| `FR-CX-004` | Archive-free fresh-read service branches before storage; legacy archive remains the rollback path under [RFC-0001](../rfc/0001-context-archive-to-fresh-read.md) | Fake-port no-storage construction and release CLI archive-stat evidence; consumer migration remains pending | D stale — evidence names a worker process boundary that no longer exists; re-verification required |

| `FR-CX-005` | In-memory fresh pages and explicit inventory/compact/detail/exact projection; encrypted TTL spill is not yet implemented | Level content-omission and native-identifier privacy tests | D memory path ready; spill pending |

| `FR-CX-006` | Explicit AI/text/TSV/JSON fresh projections include typed coverage and a declared compact UTC time schema | Compact/detail/inventory projection tests; broader golden set pending | D shadow ready |

| `FR-CX-007` | `o200k_base` measurement in Context benchmark service | Korean reference parity test | D stale — no tokenizer parity test exists in Tests/ |

| `FR-CX-008` | Fresh pages assign `E...` run references and project `T...`/`P...` aliases without native IDs; durable candidate-scoped locator replacement remains pending | Application and presentation native-ID sentinel tests | D run scope ready; candidate scope pending |

| `FR-CX-009` | Exact invocation evidence allowlist at the Foundation Models boundary; model-visible CCT/MCT uses only one-based ephemeral handles; no unbound raw-suggestion CLI ingress | Opaque-ID removal, ordinal restoration, duplicate/out-of-range rejection, CCT/MCT escaping, and CLI bypass-absence tests | D worker unit tests ready; product path pending — no CLI entry point reaches sherpa-foundation-models; [L legacy KakaoTalk verified](live-evidence.md) |

| `FR-CX-010` | Context handoff service binds user-selected exact destinations outside the model boundary, produces only PlanningCandidates, and returns their references even when later usage persistence fails | Model-selected destination rejection, exact destination injection, atomic handoff, explicit partial-report, and Planning workflow tests | D ready; L pending |

| `FR-CX-011` | Legacy pending indexes remain for rollback; page/range receipts and TTL overlap digests are specified by [RFC-0001](../rfc/0001-context-archive-to-fresh-read.md) | Existing coverage tests ready; no-permanent-irrelevant-receipt tests pending | D migration pending |

| `FR-CX-012` | `context doctor` invokes only readiness paths and separates reader health from source access | Source process, degraded-state renderer, and CLI routing tests | D stale — evidence claims a process-level test; none exists in Tests/ |

| `FR-CX-013` | `context analyze` requires and previews the exact `cal1_…` and `rl1_…` destinations with its scope, then requires the exact model confirmation | Required-argument and preview projection tests plus non-inference default process probe | D stale — evidence claims a process-level test; none exists in Tests/ |

| `FR-CX-014` | Empty guided-generation proposal array is accepted | Zero-proposal tests | D stale — no zero-proposal test exists in Tests/ |

| `FR-CX-015` | Legacy exact-revision completion remains for rollback; evidence-set digest and pre-mutation keyed-fingerprint replacement are specified by the [Fresh Context contract](../contracts/fresh-context-v1.md) | Existing concurrency tests ready; changed/deleted exact revalidation tests pending | D migration pending |

| `FR-CX-016` | Foundation Models deterministic mapper resolves all-day/timed dates from selected content, verifies both timed clocks, uses local-calendar half-open all-day ranges, and filters invalid generated siblings with safe rule warnings | Unique-date correction, ambiguous/missing date, missing clock, zero duration, DST, and valid-sibling retention tests | D worker unit tests ready; product path pending — no CLI entry point reaches sherpa-foundation-models; [L legacy date-only KakaoTalk Event verified](live-evidence.md) |

| `FR-CX-017` | Application-owned outbound model, persistent drafts in outbound.rs, orchestration workflow, CLI prepare/confirm/cancel/list, and native adapters | Validation, expiry/cancellation, exact-confirmation, worker-process, renderer, and full CLI single-use black-box tests | D stale — evidence claims a process-level test; none exists in Tests/ |

| `FR-CX-018` | Mail worker aggregates enabled Mail.app accounts and validates an exact sender/account; direct IMAP/SMTP remains an adapter milestone | Objective-C strict payload/policy release probes and nested worker fixture tests | D stale — evidence names a worker process boundary that no longer exists; re-verification required |

| `FR-CX-019` | `DispatchVerification` and every current sender return explicit `application_accepted` evidence | Adapter, worker, orchestration, persistence, renderer, and CLI black-box assertions | D stale — evidence claims a process-level test; none exists in Tests/ |

| `FR-CX-020` | Trigger/checkpoint ordering is specified by [ADR-0004](../adr/0004-native-fresh-read-context.md) and [RFC-0001](../rfc/0001-context-archive-to-fresh-read.md) | Duplicate, downtime, epoch-reset, overlap, and receipt-before-checkpoint tests pending | D pending |

| `FR-CX-021` | Fresh-read domain coverage and conservative application inference prevent below-proof and at-limit completeness claims | Count invariant, source-proof, equality-limit, JSON inventory, and live at-limit tests | D shadow ready; wider partial failures pending |

| `FR-CX-022` | Minimal durable state and retention boundary are specified by [ADR-0004](../adr/0004-native-fresh-read-context.md) | Ledger schema, privacy sentinel, TTL, and purge-separation tests pending | D pending |

| `FR-CX-023` | Sherpa-managed staged specialist routing is specified by the [fresh-read design](../design/native-fresh-read-context.md) | No-candidate fan-out, scoped-read, prompt-injection, and budget tests pending | D pending |

| `FR-CX-024` | Reconciliation outcomes and preconditions are specified by the [Fresh Context contract](../contracts/fresh-context-v1.md) | Completed resurrection, recurrence, detached occurrence, duplicate, and stale-mutation tests pending | D pending |

| `FR-CX-025` | Mail header-first measurement and IMAP decision gate are specified by [RFC-0001](../rfc/0001-context-archive-to-fresh-read.md) | Mail batch fixture and p50/p95 benchmark gate pending | D pending |

| `SR-CX-001` | CLI routes collection, Mail authorization, and outbound dispatch through the context adapter | Import ban in the repository gate, nested process contracts, and CLI black-box tests | D stale — evidence names test infrastructure that no longer exists; re-verification required |

| `SR-CX-002` | Fixed iMessage/Kakao read, exact-target validation, and text-send adapters are ready; bounded wake-up watcher path is not yet enabled | Existing command allowlist and sender tests ready; watcher no-model/no-mutation tests pending | D migration pending |

| `SR-CX-003` | Mail status is read-only; prompt requires the application authorization port and nested prompt gate | Two-worker authorization contract test | D stale — evidence names a worker process boundary that no longer exists; re-verification required |

| `SR-CX-004` | Content and LLM output remain data-only DTOs with no tool or shell port | Strict suggestion and unsupported-capability tests | D ready; L not required |

| `SR-CX-005` | Cleared allowlisted environments, bounded source/worker streams, one-shot process groups, shared failure classification, identical safe WorkerPolicy defaults, and status/result/error response invariants | Cross-language minimal-policy release probes; contradictory-response and collection-bound tests; oversized/malformed process tests; timeout, post-exit, cancellation-flag, and real CLI SIGINT descendant cleanup tests | D stale — evidence names a worker process boundary that no longer exists; re-verification required |

| `SR-CX-006` | Boundary logs contain only safe IDs, counts, states, and error kinds | Real Context worker debug-log tests cover iMessage, KakaoTalk, and nested Mail boundaries; each proves source PII traverses stdout data while reader stderr and worker stderr omit it | D stale — evidence names a worker process boundary that no longer exists; re-verification required |

| `SR-CX-007` | Dedicated owner-only Context path is ready; minimal ledger and encrypted TTL spill replace content storage under [ADR-0004](../adr/0004-native-fresh-read-context.md) | Existing filesystem gates ready; ephemeral spill expiry/privacy tests pending | D migration pending; [L legacy path verified](live-evidence.md) |

| `SR-CX-008` | Display-name map is exposed only by `context identity` | Explicit identity-map omission tests | D ready; L pending |

| `SR-CX-009` | Collection and model paths require read policy and have no outbound port; only explicit authorization and outbound routes accept verified writes | Context worker policy and unsupported-capability tests | D stale — evidence names a worker process boundary that no longer exists; re-verification required |

| `SR-CX-010` | Tool-free bounded Foundation Models path is ready; scoped specialist read grants are specified by the [Fresh Context contract](../contracts/fresh-context-v1.md) | Existing evidence allowlist tests ready; scoped-tool and untrusted-content tests pending | D worker unit tests ready; migration and product path pending — no CLI entry point reaches sherpa-foundation-models; [L legacy KakaoTalk verified](live-evidence.md) |

| `SR-CX-011` | Legacy protected storage resolves exact aliases; live target directory and final revalidation replacement are specified by [ADR-0004](../adr/0004-native-fresh-read-context.md) | Existing wrong-source/not-found tests ready; expiry/change/revalidation tests pending | D migration pending |

| `SR-CX-012` | Public CLI bodies are bounded stdin; application, worker, and Mail adapter validate strict action/header/recipient/policy contracts | CLI argument rejection, application bounds, worker unknown-field, and Mail invalid-policy release tests | D stale — evidence names a worker process boundary that no longer exists; re-verification required |

| `SR-CX-013` | Single-use claim, safe journal metadata, redacted boundary diagnostics, typed uncertain failure, and no automatic retry | Storage/orchestration once-only tests, real worker privacy tests, and CLI black-box dispatch-count assertion | D stale — evidence names a worker process boundary that no longer exists; re-verification required |

## Distribution and Agent Integration

| Requirement | Implementation evidence | Deterministic evidence | Status |
| --- | --- | --- | --- |
| `FR-DP-001` | Formula renderer in `scripts/package.sh` | Rendered Formula installs and passes `brew test` | D ready; L owner-operated |

| `FR-DP-002` | Single-binary staging in `scripts/package.sh` | Packager asserts the staged tree is exactly `./sherpa` and refuses anything else | D ready |

| `FR-DP-003` | Formula installs the binary directly; no `post_install` | Formula declares no runtime dependency | D ready |

| `FR-DP-004` | Version read back from the built binary; archive SHA-256 pinned in the Formula | Packager rejects a `--version` output that is not `sherpa X.Y.Z` | D ready |

| `FR-DP-005` | No agent-host installer exists; skills ship from this repository's marketplace | `plugins/sherpa/cli-contract.json` minimum version, enforced by `scripts/require-cli.sh` before a skill's first command | D ready; L owner-operated |

| `FR-DP-006` | Homebrew owns the installed binary; Sherpa owner state lives outside the keg | Upgrade and uninstall leave owner state untouched | D pending; L observe only |

| `SR-DP-001` | Ad-hoc-only build and permanent unsigned distribution policy | Formula declares no signing or notarization step | D pending; L permitted |

| `SR-DP-002` | Formula contains no agent-host mutation hook and no `post_install` at all | Rendered Formula structure | D ready |

| `SR-DP-003` | Packaging logs carry version, archive path, and checksum only | `[release:package:*]` log fields | D ready |

| `SR-DP-004` | Staged-tree assertion in `scripts/package.sh`; plugin absolute-path scan in `plugins/sherpa/scripts/check.sh` | Both refuse to pass on a violation | D ready |

## Gate commands

The deterministic proof is one command:

```bash
bash scripts/check-all.sh
```

The live proof is intentionally split by phase and must be run from
[the owner-operated runbook](live-validation.md). No row may be changed from
`L pending` based only on a synthetic test or a non-prompting status command.

## Related

- [Roadmap](../roadmap/README.md)
- [Planner requirements](../requirements/planner-authority.md)
- [Context requirements](../requirements/context-intelligence.md)
- [Distribution requirements](../requirements/distribution.md)
- [Test strategy](README.md)
