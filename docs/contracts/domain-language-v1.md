---
id: CONTRACT-DOMAIN-LANGUAGE-V1
title: Sherpa Domain Language Contract
status: approved
owner: maintainer
---

# Sherpa Domain Language Contract

## Purpose

This contract defines the canonical words used at Sherpa's public and worker
boundaries. Code may use implementation terms where the platform or runtime
owns their meaning, but those terms must not silently rename a Sherpa concept.

## Canonical vocabulary

| Term | Meaning | Boundary rule |
| --- | --- | --- |
| Event | A scheduled occurrence or reserved time range. | Use `event` and `events` in commands, schemas, prompts, and projections. |
| Reminder | An actionable item managed through Apple Reminders. | Use `reminder` and `reminders`; do not present `Task` as its alias. |
| EventCollection | The provider-neutral internal collection of Events. | Project it publicly as Apple's `Calendar`; `EKCalendar` remains adapter-only. |
| ReminderCollection | The provider-neutral internal collection of Reminders. | Project it publicly as Apple's `Reminder List`. |
| Source | A provider account or container that owns collections. | A Source is not itself a mutation destination; provider-specific source type names stay in adapters. |
| Destination | The exact Calendar or Reminder list selected for a mutation. | Mutations never infer a destination from a Source alone. |
| Reference | A safe Sherpa identifier exposed outside a provider adapter. | Provider-native locators remain behind the typed reference boundary. |
| NativeLocator | A provider-owned identifier used for one bounded worker operation. | Never expose it as a public `Reference`; use `*_native_locator` on worker payloads. |
| Worker request | A versioned command envelope sent across a process boundary. | Validate the envelope before native work. |
| Worker result | The bounded result returned inside a worker response. | The result is untrusted until Sherpa validates it. |
| Mutation | An operation that may change provider or canonical state. | Journal and verify it according to the capability's evidence contract. |
| Read-back | A fresh provider read used to compare the observed state with the request. | Process success alone is not read-back evidence. |
| Cleanup | Explicit removal of synthetic verification state. | Cleanup failure remains visible with a safe reference. |

## Retired Reminder alias

`Task` and `Tasks` are retired names for the Reminder concept. Public CLI help,
agent instructions, model prompts, engineering domain documents, and new wire
contracts must use `Reminder` or `Reminders` instead.

The spelling remains valid when another authority owns its meaning:

- `scripts/check-all.sh` and `scripts/package.sh`;
- `subtask`, which is an Apple Reminders relationship;
- language runtime concurrency types and generic work-unit descriptions;
- Apple private API selector names that Sherpa must reproduce exactly;
- historical live evidence; and
- negative compatibility tests that prove obsolete `task` or `tasks` wire keys
  are rejected.

These exceptions do not authorize the spelling as a new Reminder alias.

## Enforcement

The deterministic `domain-language` gate scans declared public domain surfaces
and reports the exact file and line where the retired alias reappears. It runs
through `scripts/check-all.sh`.

The completed Swift migration is also protected. Outside the automation target,
the gate rejects the retired `ReminderTask` type name and its former
`*_task` Reminder port and validation identifiers. String literals retained by
negative compatibility tests remain valid evidence that obsolete wire keys are
rejected.

Public CLI help and user output deliberately retain the Apple terms `Calendar`
and `Reminder List`. Existing `ev1_`, `cal1_`, `rm1_`, and `rl1_` reference
prefixes and persisted SQLite reference-kind strings are compatibility data and
do not change with internal type names.

## Related

- [Public output contracts](public-output-v1.md)
- [System architecture](../architecture/README.md)
- [Planner authority requirements](../requirements/planner-authority.md)
- [Test strategy](../testing/README.md)
