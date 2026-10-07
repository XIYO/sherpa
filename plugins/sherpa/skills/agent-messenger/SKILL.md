---
name: agent-messenger
description: Use the Agent Messenger CLI to read or send KakaoTalk, Discord, iMessage or Instagram messages as the local user, and to manage Discord custom emoji and stickers. Trigger for recent chats, DMs, channel activity, or approved replies. Not for calendar, reminders or mail.
---

# Agent Messenger

Use the upstream CLI directly. Do not add a Sherpa wrapper, worker, protocol,
database, or local proxy.

For KakaoTalk, this skill remains authoritative for fresh remote reads, images,
per-room checkpoints, and explicitly approved sends. If the user explicitly
needs historical full-text lookup across the Mac's locally synchronized rooms,
route that read-only lookup to the `kakaotalk-local-search` skill. Never merge
its local search rows into an Agent Messenger checkpoint.

```sh
AM='bunx --yes --package agent-messenger agent-messenger'
```

Use `$AM <platform> ...`. In this environment, do not invoke the platform
binary as the `bunx` executable (for example, `bunx ... agent-kakaotalk`):
`bunx` selects the package's primary executable.

Keep that definition unpinned so upstream fixes arrive on their own. The
Discord `emoji` and `sticker` commands, and the expression fields of `discord
server info`, need `agent-messenger` 2.38.0 or newer; if they are missing, the
resolved package is older than that.

## Authenticate

Inspect auth status before authenticating. Never print, store, or ask the user
to paste a password, token, cookie, device passcode, or message content into a
command transcript.

```sh
$AM kakaotalk auth status
$AM discord auth status
$AM instagram auth status
$AM imessage auth list
```

- KakaoTalk: run `$AM kakaotalk auth login` in the user's terminal. It creates
  a secondary **tablet** session and requires phone confirmation. It does not
  control the KakaoTalk UI.
- Discord: run `$AM discord auth extract`; it reads the local desktop or
  Chromium session and may require a Keychain prompt.
- Instagram: attempt `$AM instagram auth extract` for an existing browser
  session, then prove it with `$AM instagram chat list --limit 1 --pretty`.
  `auth status` alone only proves stored credentials exist. If the inbox call
  fails, let the user run `$AM instagram auth login` in their terminal and
  complete any Instagram security challenge; do not claim the account is
  connected until the inbox read succeeds.
- iMessage: require `imsg` on the Mac, then configure it once:

  ```sh
  $AM imessage auth set --bin "$(command -v imsg)" --region KR --label local --current
  ```

Credentials live in `~/.config/agent-messenger/`. Do not inspect or expose
them. Use the platform's `auth logout` only when the user asks to disconnect.

## Read first

Use bounded reads and JSON/pretty output. Read only the service, account,
server, channel, or chat needed for the request.

```sh
# KakaoTalk
$AM kakaotalk chat list --all --pretty
$AM kakaotalk message list <chat_id> -n 20 --pretty
$AM kakaotalk message list <chat_id> --from <last_log_id> -n 200 --pretty

# Discord: choose a server, then list channels and read only the requested one.
$AM discord server list --pretty
$AM discord server switch <server_id> --pretty
$AM discord server info <server_id> --pretty
$AM discord channel list --pretty
$AM discord channel history <channel_id> --limit 20 --pretty
$AM discord dm unread --pretty
$AM discord emoji list <server_id> --pretty
$AM discord sticker list <server_id> --pretty

# iMessage
$AM imessage chat list --limit 20 --pretty
$AM imessage message list <chat_id> --limit 20 --pretty

# Instagram
$AM instagram chat list --limit 20 --pretty
$AM instagram message list <chat_id> --limit 20 --pretty
```

### Recover a malformed KakaoTalk sync state

If a KakaoTalk read fails with the exact parser message
`Unexpected non-whitespace character after JSON`, treat the derived sync-state
cache as corrupt. Do not inspect or print its contents. Run the skill's
`scripts/repair_kakaotalk_sync_state.py` once, then retry the original read
once. The repair keeps every malformed file as an owner-only backup and never
opens or changes credentials. If the retry still fails, stop and report the
error; never loop the repair.

Do not claim a Discord server has no activity from `snapshot` alone. If it
returns `Missing Access`, list its channels and query an accessible channel's
history directly.

- `discord server info` is the only read that states the expression limits:
  boost tier with `static_emoji_slots_remaining` and `sticker_slots_remaining`.
  Read it before planning any upload. `emoji list` and `sticker list` count
  what already exists and never say how much room is left.
- `emoji list` and `sticker list` need no special permission, so they are safe
  reads. Uploading or deleting is not — see the write section below.

For incremental KakaoTalk reads, keep a separate `last_log_id` for every
account and chat. Advance it only after downstream analysis and disposition
storage succeeds. The command has no exact end-time option; capture a run
high-water and reject records beyond it in the caller.

KakaoTalk photo messages expose presigned URLs in `attachment.url`; multi-photo
messages expose them in `attachment.imageUrls`. Agent Messenger does not
download inbound files. For Sherpa context work, pass the unchanged JSON page
to the Context skill's `scripts/store_kakaotalk_images.py` before analysis.

## Send only with clear intent

Send only when the user specifies the recipient and exact message, or confirms
the proposed recipient and wording immediately before sending. Read back the
returned success object; do not claim delivery from a command that failed or
timed out.

```sh
$AM kakaotalk message send <chat_id> "exact text" --pretty
$AM discord message send <channel_id> "exact text" --pretty
$AM imessage message send <chat_id> "exact text" --pretty
$AM instagram message send <chat_id> "exact text" --pretty
```

Never send a test message to someone else. Use KakaoTalk `MemoChat` or another
explicitly named self-test destination. Do not attach or upload files unless
the user explicitly identifies the exact file and destination.

### Change a Discord server's custom emoji or stickers

These commands change a resource the whole guild shares, so they need the same
explicit intent as a send: the user names the server and the exact file to
upload or the exact expression to remove.

```sh
$AM discord emoji create <server_id> ./team-logo.png --name team_logo --pretty
$AM discord emoji delete <server_id> <emoji_id> --pretty
$AM discord sticker create <server_id> ./wave.png --tags 👋 --name wave --pretty
$AM discord sticker delete <server_id> <sticker_id> --pretty
```

- `sticker create` requires `--tags <emoji>`, one Unicode emoji the sticker
  relates to; it is the only required option on these commands. `--name`
  defaults to the filename without its extension.
- The CLI validates the name and the file locally, before it sends anything.
  Emoji names are 2–32 characters of `[A-Za-z0-9_]`, sticker names 2–30
  characters, and the format is decided by sniffing the bytes rather than the
  extension (emoji: PNG, GIF, JPEG, WebP; sticker: PNG, GIF, Lottie JSON). A
  rejection prints `{"error": …}` and exits 1 with no request made, so
  retrying the same file cannot change the outcome — rename or convert it.
- Check the remaining slots with `discord server info`, not with `emoji list`.
- `create` and `delete` need `MANAGE_GUILD_EXPRESSIONS` in that guild. The CLI
  does not probe the permission beforehand; it surfaces Discord's own error.
  Lottie stickers are accepted only in VERIFIED or PARTNERED guilds.
