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
claude plugin marketplace add https://github.com/XIYO/sherpa.git
claude plugin install sherpa@sherpa
```

```bash
codex plugin marketplace add https://github.com/XIYO/sherpa.git
codex plugin add sherpa@sherpa
```

The shared `XIYO/plug-hole` catalog carries the same plugin as `sherpa@plug-hole`:

```bash
claude plugin marketplace add https://github.com/XIYO/plug-hole.git
claude plugin install sherpa@plug-hole
```

**Install one entry point, not both.** The catalog entry is a `git-subdir`
source that points at `plugins/sherpa/` in this repository, so both routes
deliver the same files — the install clones `https://github.com/XIYO/sherpa.git`
either way. Claude Code names a skill after the
plugin alone, never the marketplace, so two copies of `sherpa` expose the same
five skill names and the same SessionStart hook. Only one of each survives, the
session does not say which, and nothing guarantees it is the newer one. If both
are already installed, remove one: `claude plugin uninstall sherpa@plug-hole`.

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
ls -d ~/.claude/plugins/cache/sherpa/sherpa/*/
bash "$(ls -d ~/.claude/plugins/cache/sherpa/sherpa/*/ | sort -V | tail -1)/scripts/require-cli.sh"
```

There is no command that prints a plugin's path: `claude plugin --help`
(2.1.278) lists no `path` subcommand, and neither does `codex plugin --help`
(codex-cli 0.155.1). The install cache is the path. The first line shows which
versions are cached; substitute your own Claude configuration directory if it
is not `~/.claude`. The second line runs the newest of them — a bare
`bash …/*/scripts/require-cli.sh` would run only the first match and pass the
others to it as arguments once more than one version is cached.

`{"status":"ready", ...}` means the installed CLI satisfies the contract.
`mismatch` reports the installed and required versions; `missing` means no CLI
is on `PATH`. On anything other than macOS the guard answers `unsupported`
(`"reason":"macos_only"`) without looking for a CLI, and suggests no install
command.

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
