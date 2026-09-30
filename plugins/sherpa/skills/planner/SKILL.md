---
name: planner
description: Use Sherpa to inspect and manage Apple Calendar and Reminders through validated proposals, confirmations, and readback, with natural Korean Event titles and notes. Trigger for schedules, appointments, time blocks, deadlines, reminders, checklists, planning candidates, or requests to create, update, complete, reopen, or delete them. For a general planning review, collect fresh Mail, iMessage, and the user-selected KakaoTalk source first; local KakaoTalk reads cover text only.
---

# Sherpa Planner

Translate planning intent into the installed Sherpa CLI contract, then reason over its versioned output.

## Workflow

1. If the request is a general planning review, follow the Context skill first. Read fresh Mail, iMessage, and the user-selected KakaoTalk source after their checkpoints. Agent Messenger reads include supported images; local database reads report attachment contents unavailable and use the local-text checkpoint.
2. Before the first Sherpa command in a session, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/require-cli.sh"` once. Continue only when it prints `"status":"ready"`; otherwise stop and report its JSON. `missing` and `mismatch` carry the command or remedy that fixes the CLI; `unsupported` means this device is not macOS, where the Sherpa CLI cannot run, so say that the plugin is macOS-only and do not suggest an install command. The plugin and the CLI ship separately, so `cli-contract.json` holds the minimum CLI version this skill needs. Do not run `--help` during a normal workflow. Send strict Worker Protocol V2 JSON to `sherpa planner request` on standard input.
3. Read Event sources and their Calendar destinations through `event.source.list` and `reminder.source.list` planner requests before choosing an exact collection.
4. Read current state before updates or deletion. Use only opaque references returned by Sherpa; never pass native identifiers.
5. For language-derived actions, use the proposal and candidate flow. Present the preview and confirmation boundary to the user, then run approval only after explicit confirmation.
6. For direct user instructions, send the matching typed Event or Reminder capability to `sherpa planner request` and verify its native readback.
7. Before every Event create, title or notes update, or communication-derived planning candidate, read `references/korean-event-writing.md` completely and apply it. Pass the draft title and notes as JSON on standard input to `scripts/lint_korean_event_text.py`; rewrite every error and review every warning before mutation. Do not bypass a warning merely because the Event date is in the past.
8. Run `sherpa operations list --limit 100` when a mutation is partial or its final state is unclear.

## Korean writing gate

Treat the Calendar date as the time expression and the title as the name of what
happens that day. Use neutral Korean action or schedule phrases. Never generate
a completion report or future-tense sentence as an Event title. Preserve an
official source title exactly only when evidence proves it is a proper name;
set `official_title: true` for the linter and keep that evidence in the active
read session.

The reference owns the detailed title patterns, tense conversions, Korean
naturalness rules, note layout, examples, and final checklist. Do not duplicate
or improvise a competing style rule here.

Always pass timestamps with explicit offsets and preserve the user's time zone. Distinguish events from reminders: fixed attendance or time blocks are events; actionable work and deadlines are reminders. Do not guess a destination, date, recurrence, or destructive scope. Do not treat a process exit as proof of a mutation; require Sherpa's verified result.
