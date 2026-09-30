---
id: TEST-HEXAGONAL-MODULARIZATION
title: Hexagonal Modularization Test Plan
status: superseded
owner: maintainer
---

# Hexagonal Modularization Test Plan

> **Superseded (2026-08-27).** `cargo xtask` 범위 기반 테스트 계획이었다. xtask 도 크레이트도
> 없다. 현재 게이트는 `scripts/check-all.sh` 하나다.

## Purpose

Define the executable evidence required to move Sherpa toward the architecture
proposed by RFC-0003. This plan supplements the approved repository-wide test
strategy. It does not weaken or replace `cargo xtask check`.

The plan favors small deterministic suites because each refactoring packet must
be safely executable without asking one coding model to reason about the entire
repository. Focused suites are a feedback mechanism; the full deterministic
gate remains the integration and release authority.

## Current baseline status

Checkpoint `403e9f7` is red. `cargo xtask check` stops in
`scrapling-browser-boundary`, and its checked-in positive main-frame capture
fixture fails the corresponding xtask unit test. The implementation and the
gate have not yet been classified against the living Supply design.

No modularization packet may begin until Phase 0 of RFC-0003 restores a complete
green deterministic baseline.

## Verification scopes

The target xtask interface is:

```text
cargo xtask test  --scope <scope>
cargo xtask lint  --scope <scope>
cargo xtask check --scope <scope>
```

Omitting `--scope` is exactly equivalent to `--scope all`. Scope composition is
owned by a typed Rust registry under `crates/xtask`; there is no YAML, shell, or
Taskfile test registry.

| Scope | Responsibility |
| --- | --- |
| `architecture` | Documentation, traceability, exact crate dependencies, forbidden imports, schema meta-validation, source ownership, and marketplace layout. |
| `runtime` | Worker Protocol, process supervision, bounded I/O, cancellation, failure classification, and shared worker artifacts. |
| `agent` | Agent inbound use cases, host adapter contracts, rollback, presentation, and CLI behavior with fixture hosts. |
| `planner` | Calendar, Reminder, PlanningCandidate, mutation journal, public/private workers, presentation, privacy, and CLI behavior. |
| `context` | Fresh read, compatibility archive, evidence, analysis, handoff, outbound, Context/Mail workers, privacy, and CLI behavior. |
| `supply` | Browser transport, Rust parsing, application services, SQLite, presentation, CLI, privacy, and cross-language fixtures. |
| `distribution` | Deterministic build, release worker probes, archive, Formula, and agent marketplace packaging. |
| `all` | Existing full lint and test behavior in the existing order. |

Every scope definition pins exact Cargo packages and test targets, Swift
packages, Python test files, architecture gates, fixture processes, and artifact
probes. A scope may intentionally include a shared package; speed never takes
priority over a dependency that can invalidate the slice.

## Zero-test defense

A focused command that silently selects zero tests is a false green and is
forbidden.

- Critical contracts use named Cargo integration-test targets rather than only
  substring filters.
- Swift and Python commands name exact suites or files.
- The xtask scope plan records the expected executable test targets.
- xtask unit tests assert that every test-bearing scope contains a discoverable
  target. Every product scope contains inbound/application evidence and at
  least one boundary test; runtime and distribution pin their own applicable
  layers.
- A scope execution reports every planned target and fails when a target is
  missing or no longer discoverable.
- Test renames update the typed registry and its regression in the same change.

## Evidence layers

Each slice owns tests at the applicable layers below.

### 1. Domain invariants

Use real values and deterministic functions with no mocks, filesystem, process,
clock, network, or provider framework.

Cover:

- valid construction and canonicalization;
- every rejected boundary value;
- equality, ordering, and content identity;
- absence versus zero/default semantics;
- overflow and cardinality bounds;
- timezone and half-open range behavior; and
- typed error classification.

### 2. Inbound use-case contracts

Call the public application use case through in-memory fakes for its outbound
ports. Each use case covers:

- success;
- invalid request rejected before an outbound call;
- authorization or confirmation rejection;
- not found and ambiguous reference;
- adapter unavailable, timeout, protocol failure, and verification failure;
- partial external effect with recoverable operation/reference evidence;
- exact outbound call count and order; and
- no unrelated port invocation.

Fakes record typed calls. They do not reproduce SQLite, subprocess, browser, or
provider behavior.

### 3. Reusable outbound-port contracts

For every port with multiple implementations or safety-critical behavior, define
one reusable contract suite. Run it against the in-memory test adapter and each
real deterministic adapter.

| Slice | Port families requiring contracts |
| --- | --- |
| Agent | Integration status, install/update/remove reconciliation, verification, and rollback. |
| Planner | Capability registry, Calendar, Reminder, private Reminder, mutation journal/history, PlanningCandidate, and execution guard. |
| Context | Source registry, Mail source/authorization, archive compatibility, control ledger, evidence, analysis usage, exact revalidation, outbound drafts, target resolution, and sender. |
| Supply | Readiness, search, detail, durable search selection, detail/media store, research archive, and catalog queries. |
| Runtime | Worker request/response validation and worker process failure classification. |

A reusable contract states observable behavior only. It never requires two
adapters to share internal storage layout or provider calls.

### 4. Adapter tests

Use the real adapter and the narrowest deterministic substitute at the external
edge.

- SQLite tests use real in-memory or private temporary databases, real
  migrations, transactions, constraints, and rollback.
- Migration tests start from every already-applied schema version affected by a
  new migration, not just from an empty database.
- Worker gateway tests use fixture executables for success, malformed output,
  oversize output, timeout, cancellation, nonzero exit, descendants retaining
  pipes, and uncertain dispatch.
- Provider parsers use immutable synthetic or privacy-reviewed fixtures and
  exercise malformed, ambiguous, incomplete, conflicting, and bounded input.
- macOS workers compile their real payload mapping and protocol code without
  prompting or touching owner data.
- Python tests replace only the browser/page boundary; production request
  parsing, capture construction, omission accounting, response serialization,
  and Rust decoding remain in the path.

### 5. Contract tests

For every public or cross-language schema:

1. validate the schema against Draft 2020-12;
2. serialize the production request/result builder;
3. validate that exact serialization with format checks enabled;
4. reject unknown fields, wrong versions, wrong policy, excess arrays, and
   unsafe sizes;
5. prove private/native fields do not appear in the public envelope; and
6. keep released schema fixtures immutable.

Syntax-only JSON checks are not contract evidence.

### 6. Driving-adapter and composition tests

Use the real CLI binary or worker entry point with deterministic outbound
adapters.

Cover:

- clap command and flag compatibility;
- request mapping into the exact inbound use case;
- renderer selection and versioned outer envelope;
- exit status and reviewed outer error text;
- no direct storage/provider method call from a controller;
- optional adapter failure isolation;
- stdout/stderr separation; and
- privacy sentinels that traverse results but never diagnostics.

### 7. Architecture tests

Architecture tests fail on structural regressions even when behavior tests pass.

They enforce:

- the exact normal-dependency graph;
- domain and application forbidden-import rules;
- controller modules importing no driven adapter crate;
- concrete adapter construction occurring only under `bootstrap` or worker
  composition roots;
- private frameworks confined to their worker;
- Python Supply semantics confined to Rust;
- public projection functions remaining explicit;
- each application slice exposing an inbound surface and owning its outbound
  ports; and
- every verification scope retaining its registered tests.

Large boolean source scans are decomposed into named rules. A failure reports
one invariant and file, and every rule has a positive fixture plus a focused
negative mutation. Multiple independent rules may be reported together, but
one opaque aggregate message is not sufficient.

## Packet test protocol

Every implementation packet uses one of two protocols.

### Behavior packet

1. Run the packet's precondition check and record green.
2. Add one test that fails for the intended reason.
3. Run that exact test and record red.
4. Implement the smallest change within the allowed files.
5. Run the exact test and record green.
6. Run the owning scope check.
7. Inspect the diff for unrelated behavior or fixture updates.
8. Commit only when all steps pass.

### Movement packet

1. Add or identify the characterization tests that pin current observable
   behavior and run them green.
2. Move one cohesive symbol/module without changing behavior.
3. Run the same characterization tests green.
4. Run architecture rules for both old and new locations.
5. Run the owning scope check.
6. Prove the old implementation path has zero remaining production uses.
7. Commit the move separately from later cleanup or behavior change.

## Spark packet acceptance record

The executor returns this compact record with every packet:

```text
packet: HEX-...
base: <commit>
changed: <allowed files actually changed>
red: <test and expected failure, or "movement packet">
focused: <command and result>
scope: <command and result>
full: <command and result, or cadence reason for omission>
stops: <none or exact unexpected boundary>
commit: <hash>
```

Missing evidence means the packet is incomplete even if the code appears
correct.

## Full-gate cadence

Run `cargo xtask check`:

- before the first modularization packet;
- after restoring the Phase 0 baseline;
- after every five successful packets;
- at every phase boundary;
- immediately after any dependency, schema, migration, worker capability,
  public projection, privacy rule, architecture rule, or Supply living-fact
  change; and
- before merging, packaging, or declaring the RFC complete.

The first full-gate failure stops the cadence counter. Diagnose the first real
boundary and do not stack more refactoring on top of it.

## Fixture policy

- Fixtures contain synthetic data unless a reviewed, minimized, privacy-safe
  provider shape is explicitly required.
- A fixture records the semantic boundary it proves, not a full private capture.
- Updating a golden or provider fixture requires a test that fails before the
  update and a written explanation of the changed fact.
- Native identifiers, message bodies, mail content, cookies, headers, account
  state, and raw attachments never enter repository fixtures.
- Time, random identifiers, and environment discovery are injected or bounded so
  deterministic tests do not depend on the execution date or owner machine.

## Live and release evidence

Focused scopes never perform live mutations, browser collection, model
generation, host registration, or owner-data reads.

At a phase boundary, run only the existing owner-operated gates required by the
changed boundary. A pure module move with identical process/contract output does
not manufacture a live-test requirement. A changed provider route, worker
behavior, mutation verification rule, packaging layout, or persisted fact does.

Supply release completion continues to require its living design, deterministic
gates, bounded diverse live evidence, version synchronization, package/local-tap
publication, Homebrew upgrade, and installed-binary verification.

## Completion evidence

This test plan is implemented when:

- all eight scopes exist and reject unknown values;
- default xtask behavior remains the full check;
- every product scope runs nonzero domain/application and boundary evidence;
- every safety-critical outbound port has a reusable observable contract;
- architecture failures identify a named invariant;
- each Spark packet can finish with one focused and one slice command; and
- the clean-worktree full deterministic gate passes.

## Related

- [Incremental hexagonal modularization RFC](../rfc/0003-hexagonal-modularization.md)
- [Sherpa test strategy](README.md)
- [System architecture](../architecture/README.md)
- [Worker protocol](../contracts/worker-protocol.md)
- [Verification matrix](verification-matrix.md)
