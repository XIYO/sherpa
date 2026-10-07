---
name: context
description: Use Sherpa to read bounded KakaoTalk, iMessage or Mail context from checkpoints, find commitments and planning candidates, check coverage, and send only confirmed replies. Trigger for reviewing recent messages or mail or extracting plans from them.
---

# Sherpa Context

Sherpa owns source checkpoints, bounded reads, disposition summaries, and outbound confirmation. Use Agent Messenger for server-backed KakaoTalk reads, media, and explicitly approved sends. When the user chooses the Mac database as the read source, use the `kakaotalk-local-search` archive and its separate local-text checkpoint. Neither local source is a completeness or send authority.

## Workflow

1. Before the first Sherpa command in a session, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/require-cli.sh"` once. Continue only when it prints `"status":"ready"`; otherwise stop and report its JSON. `missing` and `mismatch` carry the command or remedy that fixes the CLI; `unsupported` means this device is not macOS, where the Sherpa CLI cannot run, so say that the plugin is macOS-only and do not suggest an install command. The plugin and the CLI ship separately, so `cli-contract.json` holds the minimum CLI version this skill needs.
2. Diagnose the requested source before reading when access is uncertain.
   For historical KakaoTalk keyword lookup, diagnose and search through the
   `kakaotalk-local-search` skill instead of enumerating every Agent Messenger
   room.
3. For server-backed KakaoTalk, list every room with Agent Messenger and maintain one checkpoint per account and room: `account_id`, `chat_id`, `last_log_id`, and `last_message_at`. If the requested room has no checkpoint, read only the prior seven days. Report the exact read-floor date and say that earlier conversation was not read. For a user-selected local read, follow the `kakaotalk-local-search` archive workflow and advance only its local-text checkpoint after analysis.
4. Read KakaoTalk incrementally with `message list <chat_id> --from <last_log_id> --count <limit>`. Bound every page and reject records at or before the stored log ID after decoding.
5. For Agent Messenger pages, pipe the exact JSON page through `scripts/store_kakaotalk_images.py --account-id <account_id> --chat-id <chat_id>` and analyze every returned image before advancing its checkpoint. For local archive pages, mark image and attachment contents unavailable; the local checkpoint covers text only.
6. Store the scenario summary and image analysis before advancing any checkpoint. A failed download, image analysis, or context analysis leaves the prior checkpoint unchanged.
7. Keep conversation memory as a scenario summary, not a task-state mirror. Calendar owns schedules and Reminders owns tasks. Suppress resolved items and known noise; surface changed evidence again.
8. Inspect completeness and coverage before claiming that no message or commitment exists. A successful local KakaoTalk search proves only that the synchronized Mac database was queried; it does not prove that every server message or attachment was available.
9. Draft first. Send only after the user explicitly approves the exact destination and content.

Use JSON for control decisions. Never expose native source identifiers, retained evidence paths, cookies, account data, raw logs, or credentials. If evidence is incomplete, stale, changed, or expired, reread it instead of reconstructing it.

KakaoTalk images are retained under `~/Library/Application Support/Sherpa/context-media/kakaotalk/` in opaque account, room, and message folders. The script validates HTTPS, blocks private-network targets, caps each image at 25 MiB, verifies image bytes, uses owner-only permissions, and stores no source URL. Do not delete retained media unless the user asks to remove the related context or defines a retention limit.
