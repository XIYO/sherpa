---
uuid: 01a0f252-d266-7310-aa81-ee3531585026
type: guide
audience: "Mac users installing the Sherpa agent plugin and its CLI for Claude Code or Codex"
goal: "Install the CLI and one plugin entry point, run a first request, and know what data stays local"
tone: "Plain user-facing English. States requirements before steps"
manner: "Outcome first, then install, prerequisites, first use, verification, data boundary, limits"
---

# Sherpa

[한국어](README.ko.md)

Sherpa turns planning intent into bounded, evidence-checked work on your own
Mac. It reads Calendar, Reminders, Mail, iMessage, and KakaoTalk through the
native `sherpa` CLI, proposes changes, and mutates only after you confirm the
exact content. Nothing leaves the machine except what you explicitly send.

## Install

The plugin bundles skills and a SessionStart hook. Install the CLI first.

```bash
brew install xiyo/tap/sherpa
sherpa --version
```

```bash
claude plugin marketplace add https://github.com/XIYO/plug-hole.git
claude plugin install sherpa@plug-hole
```

```bash
codex plugin marketplace add https://github.com/XIYO/plug-hole.git
codex plugin add sherpa@plug-hole
```

`plug-hole` fetches the plugin from `plugins/sherpa/` in this repository. The
CLI remains a separate Homebrew install.

A new session loads the skills. Skills load from a snapshot taken at session
start, so an open session keeps the version it already loaded.

## Prerequisites

- macOS 14 or newer, Apple silicon
- Calendar and Reminders permission, granted on first read
- Full Disk Access for the host application, for Mail and iMessage
- The official `kakaocli` binary, for local KakaoTalk reads

## First use

Ask in plain language. The `sherpa` skill routes the request.

```text
오늘 일정과 할 일을 정리해줘.
새 메시지에서 일정 후보를 찾아줘.
```

Five skills carry the work:

| Skill | What it owns |
|---|---|
| `sherpa` | Entry point. Routes intent and runs the evidence loop. |
| `planner` | Calendar and Reminders through validated proposals and readback. |
| `context` | Bounded Mail, iMessage, and KakaoTalk reads; commitments and candidates. |
| `kakaotalk-local-search` | Local KakaoTalk text — keyword search, one-room history, dated archive. |
| `agent-messenger` | Server-backed KakaoTalk, Discord, iMessage, Instagram via the upstream CLI. |

## Verify

```bash
sherpa --version
claude plugin list
```

For Codex, use `codex plugin list --marketplace plug-hole`.
The list must show Sherpa as installed and enabled. A new session runs the
bundled CLI guard on macOS. It stays silent when the CLI is ready; it names
`mismatch` with both versions or `missing` when the CLI is absent. Each skill
runs the same guard before its first CLI command.

On anything other than macOS the guard answers `unsupported`
(`"reason":"macos_only"`) without looking for a CLI or suggesting an install.

## Version contract

The plugin and the CLI live in this repository, but they reach your machine by
different routes — the skills through `plugin install`, the CLI through
Homebrew. Nothing keeps those two installs in step, so their versions can drift
apart. `cli-contract.json`
holds the one constraint that matters: the minimum CLI version these skills
need, within the same MAJOR. Every skill that calls the CLI runs
`scripts/require-cli.sh` before its first command, so an outdated CLI stops the
workflow with a clear message instead of failing partway through.

## Data boundary

Reads are bounded by an explicit limit and a checkpoint, and every result
reports its own coverage. Local KakaoTalk reads cover synchronized text only —
never attachments, and never proof that the server holds nothing more. Their
checkpoint stays separate from the Agent Messenger checkpoint and is committed
only after analysis.

Outbound messages and mail are drafted first and sent only after you approve
the exact destination and content. Calendar and Reminders mutate only past the
same confirmation boundary. Sherpa returns opaque references, never provider
identifiers.

## Limitations

- macOS only. Claude Code still runs the SessionStart hook on Windows and
  Linux; there it stays silent, and a skill that is invoked stops at the guard's
  `unsupported` answer. The Windows repository check verifies the manifests and
  that hook, and skips the rest.
- `sherpa` is not a complete archive of any service.
- The CLI is not bundled. Upgrading the plugin does not upgrade the CLI.

## Development

The plugin lives at `plugins/sherpa/`; the CLI is the Swift package under
`apple/eventkit-service`. Both ship from this repository.

```bash
bash scripts/check-all.sh
```
