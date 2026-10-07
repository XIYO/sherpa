---
name: sherpa
description: Route a personal-assistant request to the right Sherpa workflow and run its evidence-based command loop. Use for combined calendar, reminder and message-derived planning, a general planning review (플래닝해줘), or when unsure which Sherpa skill applies.
---

# Sherpa

Use Sherpa as the deterministic executor. Interpret the user's intent, invoke only supported Sherpa commands, inspect the machine-readable result, and either issue the next bounded command or explain the result.

## Command contract

Before the first Sherpa command in a session, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/require-cli.sh"` once. Continue only when it prints `"status":"ready"`; otherwise stop and report its JSON. `missing` and `mismatch` carry the command or remedy that fixes the CLI; `unsupported` means this device is not macOS, where the Sherpa CLI cannot run, so say that the plugin is macOS-only and do not suggest an install command. The plugin and the CLI ship separately, so `cli-contract.json` holds the minimum CLI version this skill needs. Use the commands written in the Sherpa skills directly. Do not run routine top-level or nested `--help` probes, and do not rediscover commands at the start of a session.

If a command is missing or returns `invalidRequest`, run the guard again and report what it says. Use `--help` only to diagnose that mismatch, never as part of a normal workflow.

Build an argv array. Never interpolate user text into a shell command, add shell operators, or invent flags. Treat returned JSON as execution evidence.

## Route the request

- Use the `planner` skill for Calendar, Reminders, proposals, approvals, and planning records.
- Use the `context` skill for bounded communication reads, analysis, candidates, and explicitly confirmed outbound communication.
- Use the `kakaotalk-local-search` skill for local-first KakaoTalk text reads: keyword search, one-room seven-day history, or all synchronized rooms from an explicit date with a local checkpoint. Return to `context` for planning analysis.

For a general request such as “플래닝해줘”, “최신 계획을 정리해줘”, or “일정과 할 일을 최신화해줘”, run the complete planning review without asking the user to name every source:

1. Follow the Context workflow for fresh Mail, iMessage, and the user-selected KakaoTalk source after each source checkpoint.
2. Include every supported KakaoTalk image for Agent Messenger reads. For a user-selected local database read, state that attachment contents are unavailable and use its local-text checkpoint.
3. Reconcile the findings with current Calendar and Reminders through the Planner workflow.
4. Report grounded suggestions. Mutate Calendar or Reminders only after the normal confirmation boundary.

## Agent loop

After every command, verify the schema, requested scope, result status, coverage, and stable error code. Continue only when another Sherpa command is necessary to answer the same request. Ask the user when a required meaning is ambiguous or when Sherpa returns a confirmation boundary. Stop on CAPTCHA, authorization denial, unavailable providers, malformed output, or a contract mismatch; report the exact stable error code without proposing bypasses.

Never call Sherpa's Python or Swift workers directly. Never solve CAPTCHAs, bypass access controls, extract sessions, or perform shopping mutations such as cart, coupon, order, payment, or seller messaging.
