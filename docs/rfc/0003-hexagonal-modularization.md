---
id: RFC-0003
title: Incremental Hexagonal Modularization
status: superseded
owner: maintainer
---

# Incremental Hexagonal Modularization

> **Superseded (2026-08-27).** 이 제안의 대상은 Rust 크레이트 경계였다. 런타임이 Swift 단일
> 실행 파일로 옮겨가면서 그 경계 자체가 사라졌다. Swift 타깃 분리는 `Package.swift` 가
> 직접 표현한다. 이 문서는 당시 모듈화 판단 기준에 대한 기록으로만 남는다.

## Purpose

Reorganize Sherpa around explicit inbound use cases, application-owned outbound
ports, isolated adapters, and small composition roots without changing product
behavior, public contracts, persistence history, or worker ownership.

The migration is designed for execution by a fast coding model with limited
planning depth. Architecture decisions live in this RFC. Each implementation
task is deliberately small, has an exact file boundary, and carries its own
deterministic proof. The executor is not expected to rediscover the design from
the repository or from prior chat context.

## Baseline

The pre-modularization checkpoint is commit `403e9f7`.

That checkpoint was intentionally created without reviewing or testing the
staged changes. A subsequent `cargo xtask check` preflight stopped at
`scrapling-browser-boundary`. The narrower xtask regression
`main_frame_capture_gate_rejects_provenance_action_and_image_regressions` also
fails because the checked-in positive fixture is currently classified as a
violation. No later deterministic test stage was reached.

This is an unclassified red baseline, not evidence that either the Python
implementation or the gate is correct. Phase 0 must name the failing invariant,
classify the Supply evidence according to the living design, and restore a full
green deterministic baseline before any architectural movement begins.

## Goals

1. Make the four product slices—Agent, Planner, Context, and Supply—individually
   navigable and verifiable.
2. Keep domain and application policy independent from CLI, SQLite, worker
   protocols, provider payloads, and language-native frameworks.
3. Give each inbound use case an explicit request, result, error, and set of
   outbound ports.
4. Limit adapter construction to composition roots.
5. Turn dependency direction, public projections, worker isolation, privacy,
   and port behavior into executable contracts.
6. Let one small change be implemented, verified, reviewed, and committed
   without loading the entire repository into one model turn.
7. Preserve the full deterministic release gate as the final authority.

## Non-goals

- This RFC does not redesign user-visible commands or versioned JSON output.
- It does not rewrite an applied SQLite migration or released worker protocol.
- It does not merge workers into the Rust process or give workers a database
  path.
- It does not decide the product direction proposed by RFC-0002.
- It does not adopt a new test runner, dependency-injection framework, command
  bus, or mocking library.
- It does not make live Apple, model, communication, or browser activity part of
  the deterministic gate.
- It does not require one Rust crate per use case.

## Architectural vocabulary

Sherpa uses these terms consistently during the migration:

| Term | Sherpa meaning |
| --- | --- |
| Domain | Provider-neutral entities, value objects, invariants, and typed domain errors. |
| Inbound port | A public application use case callable by CLI, a worker entry point, or a future host. It may be a trait or a concrete service API; alternate implementations are not invented merely to justify a trait. |
| Outbound port | An application-owned trait for persistence, native capability, analysis, extraction, clock, or another external effect. |
| Driving adapter | CLI parsing, worker request dispatch, or another entry point that maps external input to an inbound use case. |
| Driven adapter | SQLite, EventKit, Context workers, model gateways, browser extraction, agent hosts, and other outbound-port implementations. |
| Composition root | The only layer allowed to choose and construct concrete adapters. |
| Contract | A versioned public or cross-process shape whose compatibility is independently tested. |

## Target dependency shape

```text
CLI / worker entry point                         driving adapters
          |
          v
slice controller -> inbound use case            application
                         |
                         +--> domain
                         |
                         `--> outbound ports
                                  ^
                                  |
              SQLite / native / worker / web    driven adapters

protocol <--- worker process infrastructure ---> language-native workers
presentation <--- typed application results ---> public output
```

The existing crate-level inward dependency rule remains valid during the
migration:

```text
domain, protocol -> no Sherpa crate
application      -> domain
application workflow layer -> application + domain
adapters         -> application + domain (+ protocol/worker client when needed)
presentation     -> typed inner results
CLI              -> composition and driving adapters
```

`sherpa-orchestration` remains a separate application workflow layer, not an
outer adapter. It owns cross-use-case state machines such as approval, claim,
revalidation, verified mutation, and terminal outcome. It continues to depend
only on application and domain in normal builds. Moving a workflow into
`sherpa-application`, renaming the crate, or removing the layer requires a
separate architectural decision; this migration does not assume that package
churn is an improvement.

## Target module shape

The migration first changes logical modules inside the existing crates. Package
renames and directory regrouping provide little architectural value and create
large import-only diffs, so they are deferred unless a later RFC demonstrates a
need.

```text
sherpa-domain/
  planner/        context/        supply/        agent/

sherpa-application/
  planner/        context/        supply/        agent/
    inbound.rs      inbound request/result/error surface
    outbound.rs     application-owned port traits
    service.rs      use-case implementation

sherpa-orchestration/
  planner/        context/        verification/
    workflow.rs     cross-use-case application state machines

sherpa/
  cli/            syntax only, split by slice
  controller/     external input <-> inbound use-case mapping
  bootstrap/      concrete adapter construction, split by slice

driven adapter crates/
  one module per implemented outbound port or tightly cohesive provider family
```

The names describe ownership, not mandatory file count. A small slice may keep
`inbound`, `outbound`, and `service` in one file until size or coupling justifies
a split.

## Invariants preserved throughout

Every task must preserve all applicable existing invariants, including:

- Rust alone opens Sherpa-owned SQLite databases.
- Applied migrations and released protocols are immutable.
- Provider-native locators remain behind typed Sherpa references.
- External writes are journaled and verified to the provider's actual evidence
  strength.
- Communication acceptance is never presented as delivery or read-back.
- Workers are bounded, untrusted process adapters and never receive database
  paths.
- Public JSON is produced by explicit presentation projections.
- Sensitive content and native locators never enter diagnostics.
- Supply keeps its exact Rust/Python ownership chain and living-evidence update
  rules.
- `cargo xtask check` stays deterministic and non-prompting.

## Spark execution contract

Each implementation request is one packet and one commit. A packet contains all
of the following fields:

```text
Packet ID
Objective
Precondition commit
Allowed files
Forbidden changes
Invariant being protected
Test to add or characterization test to preserve
Focused verification command
Slice verification command
Stop conditions
Expected commit message
```

Packet rules:

1. One packet changes one seam in one slice. Moving one module and changing its
   behavior are separate packets.
2. A behavior packet begins with a failing test that expresses the required
   behavior. A pure movement packet records a green characterization test before
   and after the move; it must not manufacture an artificial red test.
3. The allowed-file list is closed. A newly required file, dependency, schema,
   migration, public field, or provider route is a stop condition rather than
   permission to expand scope.
4. A packet never leaves the tree red and never disables, ignores, weakens, or
   renames away a failing test.
5. Public contracts, applied migrations, worker capabilities, privacy rules, and
   release behavior may change only in a packet that names that boundary
   explicitly and updates its full evidence chain.
6. No packet relies on a later cleanup task to restore dependency direction.
7. The executor reports the exact commands run and the first failing boundary.
   It does not retry an unverified workaround.
8. Phase-boundary acceptance is reviewed separately from the packet that wrote
   the code.

## Migration sequence

### Phase 0 — Restore a trustworthy baseline

No architectural file movement is allowed in this phase.

1. Replace the aggregate boolean result of the failing Supply main-frame gate
   with named invariant results while preserving every current rule. Each result
   gets a positive fixture and at least one focused negative mutation.
2. Run the current checked-in Python sources through those named rules and
   identify the first actual mismatch.
3. Classify each reproduced mismatch before fixing it:
   current truth updates the living Supply design, an unresolved fact enters
   `Current incomplete work`, and a rejected path moves to live-evidence
   history.
4. Repair one named mismatch per packet. Update implementation, gate, tests,
   living design, and development skill together whenever a Supply fact changes.
5. Run `cargo xtask check` to completion. Record its successful commit and
   elapsed time as the modularization baseline.

Exit criterion: the complete deterministic gate passes from a clean worktree.

### Phase 1 — Build the modular verification substrate

1. Split `crates/xtask/src/gates.rs` behind a `gates` module without changing
   gate order or behavior. Move one existing gate per packet and retain its
   positive and negative tests beside the rule.
2. Introduce a typed `VerificationScope` registry in xtask. The initial scopes
   are `architecture`, `runtime`, `agent`, `planner`, `context`, `supply`,
   `distribution`, and `all`.
3. Add scoped forms of the existing entry points:
   `cargo xtask test --scope <name>`, `cargo xtask lint --scope <name>`, and
   `cargo xtask check --scope <name>`. Omitting `--scope` remains exactly
   equivalent to `--scope all`.
4. Add one scope per packet. Every scope has an xtask test that pins its exact
   command plan. Every product or runtime scope has boundary evidence, and every
   test-bearing scope proves that it executes nonzero tests.
5. Keep commands as typed argument arrays. Do not introduce shell orchestration,
   a Taskfile, or a second workflow registry.

Exit criterion: every product slice has a deterministic focused check and the
unchanged full check still passes.

### Phase 2 — Separate driving adapters from composition

Perform the pattern on Agent first, then Planner, Context, and Supply.

For each slice:

1. Pin its current clap syntax and public output with black-box tests.
2. Move only its clap types into `cli/<slice>.rs`.
3. Move only external-to-application mapping into `controller/<slice>.rs`.
4. Move concrete adapter construction into `bootstrap/<slice>.rs`.
5. Add an architecture rule proving that controller modules cannot import
   storage, platform, extractor, agent-host, protocol, or worker-client crates.
6. Make the controller call only a typed inbound use case and presentation
   function.

Exit criterion: `main.rs` handles process lifecycle, logging, parsing, and
top-level dispatch only; each slice has an independently tested controller and
bootstrap module.

### Phase 3 — Prove the pattern with Agent

Agent is the pilot because it is the smallest slice and already has an
application-owned port plus a fake command boundary.

1. Define the Agent inbound request, result, and error surface in one module.
2. Keep `AgentIntegrationPort` application-owned and split host process DTOs
   from application values.
3. Add reusable Agent port-contract tests for status reconciliation, partial
   host availability, rollback, and post-action read-back.
4. Run the same contract against the fake adapter and the real adapter with
   fixture executables only.
5. Complete the controller/bootstrap split and remove superseded re-exports only
   after all call sites migrate.

Exit criterion: the Agent slice demonstrates the complete target pattern and
becomes the template for later packets.

### Phase 4 — Modularize Planner authority

Order work by policy sensitivity:

1. Read-only Calendar and Reminder queries.
2. Mutation journal and safe-reference recovery.
3. Calendar and Reminder writes plus native read-back.
4. PlanningCandidate proposal, authorization, claim, revalidation, and final
   outcome.
5. Optional private Reminder enrichment and verification.

Organize `PlanningWorkflow` and public/private verification workflows under
slice-owned orchestration modules after their existing tests have been
expressed as reusable application and workflow contracts. Preserve partial
outcomes, single terminal journal transitions, and exact confirmation semantics
at every step.

Exit criterion: Planner controllers depend on Planner inbound use cases;
EventKit, private-helper, and SQLite construction occurs only in Planner
bootstrap; every mutation path has ordering and failure-injection tests.

### Phase 5 — Modularize Context

Use separate packets for these distinct capabilities:

1. Fresh read and source readiness.
2. Legacy archive compatibility.
3. Evidence protection and exact revalidation.
4. Semantic triage and model analysis.
5. Planning handoff.
6. Outbound draft, confirmation, target resolution, and dispatch.

Collection/analysis ports stay read-only. Outbound remains a separate write
port. The model adapter receives neither a sender nor a Planner mutation port.
Every packet retains hard byte/count/time bounds, exact-evidence freshness, and
privacy sentinels at process and CLI levels.

Exit criterion: each Context capability can be tested through an inbound use
case with fake ports, through its real fixture worker adapter, and through the
CLI without a live account or model invocation.

### Phase 6 — Resolve Supply direction before deep movement

Supply gate modularization and characterization may proceed earlier, but
provider parser expansion and domain reshaping wait for RFC-0002's product
decision.

If the current canonical path is retained, migrate in this order:

1. Search capture transport and integrity.
2. Rust search parser and durable selection references.
3. Detail capture transport and integrity.
4. Rust detail parser and transactional persistence.
5. Research, comparison, media read-back, and public presentation.

If the bounded LLM evidence-feed direction is accepted, write a separate design
and contracts before changing production code. This RFC supplies the same
hexagonal shell but does not pre-approve raw retention, parser removal, or a new
model boundary.

Exit criterion: Supply has one accepted product direction, one ownership chain,
slice-scoped deterministic tests, and all still-required owner-operated evidence.

### Phase 7 — Tighten the inner core

After slice boundaries are stable:

1. Split oversized domain and application files by cohesive concept, one file
   move per packet.
2. Replace `anyhow::Error` in domain modules with stable typed errors one module
   at a time.
3. Audit domain `serde` derives individually. Retain serialization only when it
   is an intentional inner contract; move public/wire/persistence encoding to
   adapter DTOs. Do not perform a bulk derive removal.
4. Split orchestration by bounded slice while retaining its exact inward normal
   dependencies and prohibiting concrete adapter construction.
5. Remove compatibility re-exports only after repository-wide use is zero and
   the relevant slice plus full check pass.

Exit criterion: the domain has no provider, persistence, process, CLI, or public
projection concern, and application modules depend only on domain plus explicitly
reviewed general-purpose libraries.

### Phase 8 — Accept and publish the architecture

1. Run every scoped check and `cargo xtask check` from a clean worktree.
2. Run deterministic packaging when build or runtime layout changed.
3. Run only the owner-operated live gates required by the boundaries actually
   touched.
4. Update the normative architecture and test strategy from the accepted
   implementation; do not copy transient packet detail into them.
5. Update the verification matrix only when a product requirement or its
   evidence changed.
6. Mark this RFC accepted after the normative documents and architecture gate
   describe the implemented state.

## Initial packet ledger

This ledger fixes order and scope. It is not a substitute for the complete
packet fields under `Spark execution contract`; instantiate those fields with a
closed allowed-file list immediately before each packet runs.

| Packet | Single objective | Mandatory evidence |
| --- | --- | --- |
| `HEX-000` (complete) | Make the current Python main-frame architecture gate return named invariant violations without changing any rule. | Existing positive/negative gate tests rewritten to pin every name; current source reports at least one exact name. |
| `HEX-001..HEX-00N` | Resolve exactly one named baseline mismatch per packet after Supply evidence classification. | Focused regression, synchronized living design/skill when a fact changes, and the Supply gate advances without weakening another rule. |
| `HEX-009` | Establish the clean green baseline milestone. | `cargo xtask check` completes; elapsed time and commit are recorded; no source change is mixed into this evidence-only milestone. |
| `HEX-010` | Add the `gates` module shell and retain the existing gate order. | Old and new runners produce the same ordered gate plan. |
| `HEX-011+` | Move one existing architecture gate and its tests per packet. | The moved gate has the same positive behavior and named negative fixtures; full lint passes at the phase boundary. |
| `HEX-020` | Add `VerificationScope` parsing with `all` as the unchanged default. | CLI/unit tests pin every accepted name, reject unknown names, and prove no-argument behavior is unchanged. |
| `HEX-021` | Register `architecture`. | Typed plan assertion plus execution of all registered architecture gates. |
| `HEX-022` | Register `runtime`. | Nonzero protocol, worker-client, process failure, timeout, and cancellation targets. |
| `HEX-023` | Register `agent`. | Nonzero application, fixture-host adapter, presentation, and CLI targets. |
| `HEX-024` | Register `planner`. | Nonzero domain/application/workflow, storage, worker, privacy, presentation, and CLI targets. |
| `HEX-025` | Register `context`. | Nonzero fresh-read/analysis/outbound application, storage, worker-process, privacy, presentation, and CLI targets. |
| `HEX-026` | Register `supply`. | Nonzero Python production-capture, Rust decoder/parser, application, SQLite, contract, presentation, and CLI targets. |
| `HEX-027` | Register `distribution` and re-prove `all`. | Artifact/release-worker targets plus exact equivalence between default check and `--scope all`. |
| `HEX-030` | Add Agent CLI and output characterization tests. | Current syntax, exit status, outer errors, and public projections pinned through the real binary. |
| `HEX-031` | Move Agent clap types only. | `HEX-030` remains green; no application or adapter file changes. |
| `HEX-032` | Introduce the Agent controller with a typed inbound request/result. | Controller tests use a fake inbound use case and import no driven adapter. |
| `HEX-033` | Introduce Agent bootstrap and route the CLI through it. | Fixture-host black-box flow plus architecture rule restricting concrete construction to bootstrap. |
| `HEX-034` | Extract reusable Agent outbound-port contracts. | Same observable contract passes for the fake and fixture-backed real adapter. |
| `HEX-039` | Review the Agent pilot and freeze its pattern. | Agent scope and full check pass; review records any pattern correction before Planner packets are generated. |
| `HEX-040+` | Generate and execute one Planner seam packet at a time in Phase 4 order. | Planner packet protocol and Planner scope, with immediate full checks for mutation/worker/contract changes. |
| `HEX-050+` | Generate and execute one Context capability packet at a time in Phase 5 order. | Context packet protocol and Context scope, with privacy process evidence for every boundary move. |
| `HEX-060` | Decide RFC-0002 before deep Supply restructuring. | Accepted/rejected product decision and matching design/contract plan; no speculative parser movement. |
| `HEX-070+` | Tighten domain/application internals one cohesive module at a time. | Characterization plus owning scope; dependency or serialization changes trigger the full check. |
| `HEX-090` | Accept the implemented architecture. | All scopes, clean full check, required package/live evidence, normative document updates, and RFC status transition. |

## Commit and review cadence

- One packet produces one conventional commit.
- A slice may advance only while its scoped check is green.
- Every five successful packets, and at every phase boundary, run the full
  deterministic check to detect cross-slice coupling early.
- A change to `Cargo.toml`, a protocol schema, a migration, a worker capability,
  public output, or a living Supply fact always triggers an immediate full
  deterministic check rather than waiting for the five-packet cadence.
- Do not squash away the baseline-recovery evidence until the migration is
  accepted.

## Completion criteria

The modularization is complete only when:

- all production entry points reach external systems through application-owned
  ports;
- only bootstrap modules construct concrete adapters;
- Agent, Planner, Context, Supply, runtime, architecture, and distribution each
  have an executable scoped check;
- port contracts cover success, rejection, partial effect, timeout/cancellation,
  malformed response, and privacy behavior where applicable;
- public schemas and applied migrations remain compatible or have explicit new
  versions;
- the exact dependency graph is enforced;
- `cargo xtask check` passes from a clean worktree; and
- required owner-operated evidence is complete for every changed live boundary.

## Related

- [System architecture](../architecture/README.md)
- [Hexagonal modularization test plan](../testing/hexagonal-modularization.md)
- [Sherpa test strategy](../testing/README.md)
- [Supply LLM evidence-feed proposal](0002-supply-llm-feed-reorientation.md)
- [Worker protocol](../contracts/worker-protocol.md)
- [Verification matrix](../testing/verification-matrix.md)
- [Codex speed and Spark guidance](https://learn.chatgpt.com/docs/agent-configuration/speed)
