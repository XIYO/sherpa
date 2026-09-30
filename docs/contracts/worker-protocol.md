---
id: CONTRACT-WORKER-V2
title: Sherpa Worker Protocol V2
status: approved
owner: maintainer
---

# Sherpa Worker Protocol V2

## Transport

The initial transport is one request and one response per process.

- stdin contains exactly one UTF-8 JSON request.
- stdout contains exactly one UTF-8 JSON response and no diagnostics.
- stderr contains diagnostics that obey the privacy policy.
- process exit success means a syntactically valid response was produced; the
  response status describes the capability outcome.
- On Unix the caller starts each one-shot worker in its own process group. The
  worker must not leave descendants behind; the caller cleans the group after
  normal leader exit, timeout, or cooperative process cancellation before
  joining protocol readers. The CLI converts its first SIGINT or SIGTERM into
  an atomic cancellation flag observed by the worker supervisor, cleans the
  active group, and exits with `128 + signal`. A second termination signal may
  stop the process immediately if cleanup itself is stuck. A descendant
  therefore cannot survive terminal interruption or keep stdout/stderr open
  past the request.
- Both caller and worker enforce request and response bounds while streaming,
  before an unbounded buffer can form. EventKit and private Reminder requests
  are limited to 64 KiB. Context and Mail allow 2 MiB so a separately bounded
  1 MiB mail body plus its envelope can cross both worker boundaries;
  Foundation Models also allows 2 MiB for its own bounded content envelope. Caller-side stdout, stderr, runtime, and artifact limits remain an
  independent second boundary.

Process supervision has one shared failure classification used by every typed
gateway: unavailable startup, timeout, protocol-boundary failure, or adapter
execution failure. Invalid/oversized stdout or stderr is a protocol-boundary
failure; a non-zero or signalled worker exit is an adapter execution failure.
Provider-specific response error codes remain a separate layer.

Response outcome semantics separate processing status, external effect, and
evidence. `succeeded` requires an object result and no error. `failed` means the
effect did not start. `partial` preserves an applied effect and a bounded result
when required evidence mismatched or was unavailable. `uncertain` preserves a
`may_have_applied` effect after invocation when the boundary cannot determine
the native outcome. Timeout and cancellation are stable error codes rather than
statuses. Warnings are bounded to 128 rows.

## Compatibility

Major versions are incompatible. Every V2 envelope is exact-key and rejects V1
before executing the requested capability. There is no runtime V1 fallback or
dual dispatch.

The policy is executable input, not documentation. Every request explicitly
supplies `effect`, `required_evidence`, and `artifact_directory`; no field has a
default. Effects are `read`, `authorization_prompt`, `mutation`, and `dispatch`.
Evidence is `none`, `authorization_readback`, `native_readback`,
`native_absence_readback`, or `application_acceptance`. Workers reject
irrelevant artifact directories and mismatched policy before touching the
provider. A non-null artifact directory is a non-empty,
NUL-free string bounded to 4,096 UTF-8 bytes and is accepted only by a
capability that explicitly stages artifacts.
The Context worker's collection and analysis-facing capabilities are read-only
with respect to source data. Exactly two Context routes accept verified write
policy:

- `context.mail.authorization.request` may prompt for macOS automation consent
  only after the explicit CLI authorization use case; the inner Mail worker
  independently requires its permission-prompt environment gate.
- `context.outbound.dispatch` accepts only a validated adapter-only outbound DTO
  after the workflow has atomically consumed an expiring confirmation. It
  routes to a fixed KakaoTalk or Messages command, or to the inner
  `mail.message.send` dispatch capability with application-acceptance evidence.

Outbound acceptance is typed separately from delivery. A successful current
adapter returns `application_accepted`; any failure after invoking a sender is
classified as uncertain and is not automatically retried.

Every response exactly echoes the request's application contract, request ID,
operation ID, and capability. Capability discovery alone returns a
`capabilities` array; ordinary responses carry no capability report.

The machine-readable wire source of truth is
`protocols/worker-v2.schema.json`.
Implementation and fixtures must validate against the same schema. The
deterministic gate validates every schema against the Draft
2020-12 meta-schema and validates real serialized request and response values,
with standard formats enabled; parsing the schema as JSON is not sufficient.

## Sensitive values

Payloads may contain private content needed for one operation, but envelope
metadata, diagnostics, and error messages cannot repeat it. Large or binary
content uses a request-scoped staging reference. Sherpa validates and promotes
the result; a worker never receives canonical database write access.

## Authority split

The Swift Planner Application owns Event and Reminder contract interpretation,
semantic validation, native invocation, fresh read-back, and semantic
comparison. The application core owns CLI syntax, approval, idempotency, candidate freshness,
worker supervision, safe references, journal state, SQLite, and public output.
Both sides independently validate the V2 process contract.

## Related

- [System architecture](../architecture/README.md)
- [Planner requirements](../requirements/planner-authority.md)
- [Context requirements](../requirements/context-intelligence.md)
