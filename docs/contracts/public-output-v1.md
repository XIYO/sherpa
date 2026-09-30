---
id: CONTRACT-PUBLIC-OUTPUT-V1
title: Sherpa Public Output Contracts
status: approved
owner: maintainer
---

# Sherpa Public Output Contracts

## Boundary

Every public JSON response names an explicit `sherpa.*.vN` schema. Its payload
is built by the presentation layer's explicit JSON projection, not by
serializing a domain, application, storage, or orchestration value wholesale.

This rule keeps internal model evolution separate from the CLI contract:

- every exposed field is selected and named deliberately;
- source and provider-native locators cannot appear by accidental derivation;
- `FieldState` remains explicit as `value`, `absent`, `unsupported`,
  `unavailable`, or `redacted`;
- timestamps and enum names are formatted by the projection contract;
- adding an internal field does not silently add a public field;
- changing an existing shape requires a deliberate version bump and golden-test
  change.

The exhaustive mappings live in the presentation crate's
`json_projection.rs`,
`context_projection.rs`,
and
`system_projection.rs`.
AI, text, and TSV have independent versioned renderers because their compactness
and human readability requirements differ from JSON.

Authorization output follows the same boundary. Both `sherpa status` and
`sherpa authorize` accept `--format ai|text|tsv|json`; JSON remains the default
and preserves `sherpa.authorization.v1`, while AI and TSV declare their row
schemas before emitting target/state pairs. `authorize` always requires one
explicit target; renderer selection cannot broaden the requested permission.

## Compatibility

Existing v1 field names and meanings may be clarified but not silently reused
for a different meaning. Additive changes still require an explicit projection
edit and compatibility review. A breaking shape or semantic change receives a
new schema version.

`sherpa.reminder-private-mutation.v2` supersedes its v1 shape. V2 separates the
verified native mutation from capability-evidence persistence, so a registry
failure is represented as `mutation.status=verified` together with
`capability_evidence.state=not_recorded`; it is never hidden as full success or
misreported as a failed native write.

`sherpa.context-analysis-handoff.v1` likewise separates the already-persisted
PlanningCandidate batch from exact Context analysis-usage persistence. If the
second store fails, candidate references and approval codes remain visible and
`analysis_usage.state=not_recorded` prevents an operator from mistaking the
cross-store handoff for complete success.

Planner event and Reminder detail families use v2:

- `sherpa.events.v2`, `sherpa.event.v2`, and `sherpa.event-mutation.v2`;
- `sherpa.reminders.v2`, `sherpa.reminder.v2`, and
  `sherpa.reminder-mutation.v2`;
- AI headers `@events/2`, `@event/2`, `@event-mutation/2`, `@reminders/2`,
  `@reminder/2`, and `@reminder-mutation/2`.

V2 adds the complete EventKit recurrence selectors to detail projections and
puts alarms and recurrence into every detail renderer. AI rows use short nested
keys declared once by their `#nested` schema row, avoiding repeated long JSON
field names. Text and TSV retain descriptive names. Compact list projections do
not add schedule detail.

Reminder source discovery also breaks to V2 immediately. JSON uses
`sherpa.reminder-sources.v2` and the collection key `lists`; AI and TSV use
`@reminder-sources/2` with `LIST_REFERENCE`, `LIST`, and `LIST_TYPE` columns.
`sherpa.capabilities.v2` exposes each executable capability's effect, required
evidence, and destination requirement. Invitations, attendee editing, and RSVP
remain non-executable: a typed `PlannedCapabilityHint` may describe them as
planned in help and capability output, but no parser command or worker
capability may be registered.

## Verification

The repository gate compiles exhaustive mappings, runs exact JSON contract tests,
rejects generic serde serialization in every projection module, and rejects
generic value serialization in the CLI composition root.

## Related

- [System architecture](../architecture/README.md)
- [Test strategy](../testing/README.md)
