---
id: TEST-SHERPA-LIVE
title: Sherpa Owner-Operated Live Validation
status: approved
owner: maintainer
---

# Sherpa Owner-Operated Live Validation

## Safety boundary

Run this only after `bash scripts/check-all.sh` passes. These commands are intentionally absent
from the default gate because they may request Apple privacy permissions, read
bounded personal content, invoke the on-device model, create disposable Apple
records, or open a logged-in marketplace profile. Use a disposable writable
Calendar and Reminder list for mutation checks.

Developer ID enrollment is not required. An unsigned rebuild may be treated as
a different privacy identity by macOS and require authorization again.
`authorize` requires exactly one target and deliberately has no `all` target;
run each permission request separately after inspecting the current status.

## 1. Public EventKit

Inspect state, then explicitly request only the permission being tested:

```bash
target/release/sherpa status
target/release/sherpa authorize calendar
target/release/sherpa authorize reminders
target/release/sherpa calendars --format text
target/release/sherpa reminder-lists --format text
```

The preferred path is to choose one writable Event source and one writable
Reminder source. Sherpa creates its own uniquely titled disposable Calendar or
Reminder list in that source, runs the item lifecycle, and removes the
destination. First run each verification without `--confirm`; it prints the
exact planned actions and exits without mutation.

```bash
target/release/sherpa verify calendar-crud \
  --source <event-source-reference> --format text

target/release/sherpa verify reminder-crud \
  --source <reminder-source-reference> --format text
```

After checking the target, run the exact approvals:

```bash
target/release/sherpa verify calendar-crud \
  --source <event-source-reference> \
  --confirm VERIFY_CALENDAR_CRUD_ON_THIS_MAC --format json

target/release/sherpa verify reminder-crud \
  --source <reminder-source-reference> \
  --confirm VERIFY_REMINDER_CRUD_ON_THIS_MAC --format json
```

`--calendar <calendar-reference>` and `--list <list-reference>` remain
available for an owner-prepared disposable destination. They conflict with
`--source`; exactly one mode is required.

The Calendar check creates a relative alarm and bounded weekly recurrence,
reads them back, updates the item while explicitly clearing both, reads back
again, and deletes the item. The Reminder check does the same with a dated
Reminder and additionally performs complete and reopen. Source-owned successful
output uses the evidence code `eventkit.live_synthetic_crud.v4`; the existing
destination mode remains v3. Every item and destination mutation is journaled,
and each worker write is natively read back. A partial create preserves its safe
Sherpa reference so cleanup can still run. Recurring Calendar update and
deletion use the future-series span, and the verifier checks both scheduled
occurrence windows for residue. Reminder deletion is re-read by exact reference.
Cleanup is attempted even when an intermediate invariant fails, and source mode
also removes and re-lists the disposable Calendar or Reminder list. If cleanup
itself fails, the error prints the safe Sherpa reference; inspect
`sherpa operations` before manual deletion.

## 2. Private Reminder capability

Probe compatibility first. Enable private writes only for the explicitly
confirmed command:

```bash
target/release/sherpa capabilities --format json

SHERPA_PRIVATE_WRITES=1 target/release/sherpa verify reminder-tags \
  --list <list-reference> --format text

SHERPA_PRIVATE_WRITES=1 target/release/sherpa verify reminder-tags \
  --list <list-reference> \
  --confirm VERIFY_REMINDER_TAGS_ON_THIS_MAC --format json
```

Do not infer support for sections, hierarchy, flags, or attachments from a tag
result; private capabilities are enabled and verified independently for the
exact OS environment.

The tags verifier journals its public create before invoking the private
helper. If public create read-back fails after the native write, it recovers the
safe Sherpa reference, deletes that synthetic Reminder, confirms the reference
is no longer readable, and returns the original partial-create error. Normal
cleanup performs the same deletion read-back before capability evidence is
recorded. A cleanup error prints only the safe reference and requires journal
inspection before any manual retry.

The tag command above is the only automatic disposable synthetic verifier.
For the remaining capabilities, create or choose one disposable Reminder,
inspect each command first without `--confirm`, and then repeat only the desired
command with `--confirm` set to that exact `rm1_...` reference:

```bash
SHERPA_PRIVATE_WRITES=1 target/release/sherpa reminder flagged <rm1-reference> --value true
SHERPA_PRIVATE_WRITES=1 target/release/sherpa reminder urls <rm1-reference> --url https://example.invalid/sherpa-verification
SHERPA_PRIVATE_WRITES=1 target/release/sherpa reminder section <rm1-reference> --name '<existing disposable section>'
SHERPA_PRIVATE_WRITES=1 target/release/sherpa reminder subtasks <rm1-reference> --title 'Sherpa verification subtask'
SHERPA_PRIVATE_WRITES=1 target/release/sherpa reminder image <rm1-reference> --file <small-test-image>
```

Every confirmed command performs native read-back and records verification only
for its own capability. Its v2 result reports native mutation status separately
from `capability_evidence`; if the latter is `not_recorded`, do not claim that
the capability has been activated even though the returned mutation itself may
be `verified`. Use an existing disposable section: creating a new section is a
separate list mutation and `section.assign` deliberately refuses to do it. A
misspelled or absent section returns a typed not-found failure before a private
save request is constructed. Inspect the Reminder in the native app after each
command, and delete the disposable Reminder only after all selected checks
finish.

## 3. Context

`doctor` does not read content. `sync` does, so select one source and a narrow
half-open range deliberately:

```bash
target/release/sherpa context doctor --format json

target/release/sherpa context sync \
  --source imessage --from 2026-08-01 --to 2026-08-02 --format ai

target/release/sherpa context export \
  --source imessage --from 2026-08-01 --to 2026-08-02
```

Choose the complete references of the disposable writable Calendar and Reminder
list used in section 1. Run `context analyze` once without confirmation to
inspect the exact transcript scope, both destinations, and confirmation phrase:

```bash
target/release/sherpa context analyze \
  --source imessage --from 2026-08-01 --to 2026-08-02 \
  --calendar <cal1-reference> --list <rl1-reference> --format text

target/release/sherpa context analyze \
  --source imessage --from 2026-08-01 --to 2026-08-02 \
  --calendar <cal1-reference> --list <rl1-reference> \
  --confirm ANALYZE_CONTEXT_WITH_LOCAL_MODEL --format text
```

Only the confirmed retry invokes the on-device model. The destinations are held
by Sherpa outside the model request, so the model cannot replace them. Inspect
every resulting candidate and its bound destination before approving one:

```bash
target/release/sherpa candidates --state proposed --format text
target/release/sherpa candidates <pc1-reference> --format text
target/release/sherpa approve <pc1-reference> \
  --confirm <ap1-confirmation-code> --format json
```

The final `approve` command is a separate EventKit mutation. Run it only for an
inspected candidate targeting the disposable destination; analysis by itself
never writes Calendar or Reminders.

### Controlled outbound check

Use only a self/test conversation or mailbox. First sync the narrow range that
contains the target, then take the complete `K...` or `I...` alias from the
export. Preparing a draft reads UTF-8 stdin and does not send:

```bash
printf '%s' 'Sherpa controlled iMessage check' |
  target/release/sherpa context send imessage \
    --thread <I-thread-reference> --format text

printf '%s' 'Sherpa controlled KakaoTalk check' |
  target/release/sherpa context send kakaotalk \
    --thread <K-thread-reference> --format text

printf '%s' 'Sherpa controlled mail check' |
  target/release/sherpa context send mail \
    --from '<configured-sender@example.com>' \
    --to '<self@example.com>' --subject 'Sherpa controlled check' --format text
```

Inspect the complete target and content. Cancel an unwanted draft with
`sherpa context send cancel <od1-reference>`. To perform the controlled send,
copy the exact reference and one-time code printed by that draft:

```bash
target/release/sherpa context send confirm <od1-reference> \
  --confirm <sc1-confirmation-code> --format json
```

The code is consumed before native dispatch and cannot be reused. A successful
result currently means only `application_accepted`; confirm delivery in the
native app. Never retry a `dispatch_uncertain` result automatically,
because the original command may already have been accepted.

## Related

- [Owner-operated live evidence](live-evidence.md)
- [Test strategy](README.md)
- [Roadmap](../roadmap/README.md)
- [Planner requirements](../requirements/planner-authority.md)
- [Context requirements](../requirements/context-intelligence.md)
