---
uuid: 01a0ed5e-d548-7186-8258-6b67286a11f2
type: guide
audience: "Developers and agents who build, run, or release the Sherpa CLI from this repository"
goal: "Build and gate the CLI, call its commands, read their outcomes, and install the agent skills"
tone: "Plain technical English. States verified behavior and names what is unobserved"
manner: "Commands first, then the contract each one keeps; long evidence stays in docs/"
---

# Sherpa

Sherpa is a native macOS CLI written in Swift. It talks directly to EventKit,
Mail.app, iMessage, KakaoTalk, and the optional private ReminderKit adapter.
There is no Rust runtime, Cargo workspace, or Rust worker boundary.

## Build and test

One gate covers everything — all three Swift packages, the `--version` format
the plugin's guard parses, and the agent plugin:

```bash
bash scripts/check-all.sh
```

The gate requires a macOS 26 or newer host. `apple/foundation-models-service`
declares `platforms: [.macOS(.v26)]` and imports `FoundationModels`; the other
two packages declare `.macOS(.v14)`. That one package therefore sets the floor
for the whole gate. What an older host actually does — a build failure, or
something subtler — has not been observed, because no such machine was
available; the floor is read off the declared platform, not off a failed run.
`SHERPA_SKIP_RELEASE=1` skips only the Homebrew release smoke, not that package.

Enable the pre-push check once per clone:

```sh
git config core.hooksPath .githooks
```

The hook runs the full gate, including the release smoke, against each pushed commit
in a clean worktree under `.claude/worktrees/`.

To build the release binary alone:

```bash
swift build --package-path apple/eventkit-service -c release --product sherpa
```

`bash scripts/package.sh` produces the release archive and renders the Homebrew
Formula from the version the built binary reports. Users install the released
CLI with `brew install xiyo/tap/sherpa`; the [release
runbook](docs/testing/local-homebrew-release.md) publishes a version there and
installs a development build locally.

Search the Mac's locally synchronized KakaoTalk text through Sherpa's bounded,
read-only projection. The query is read from standard input so it does not
become a Sherpa command argument:

```bash
printf '%s' '배송' | sherpa kakaotalk search --limit 20
```

This requires the official `kakaocli` binary and Full Disk Access for the host
application. Results always report partial coverage and omit KakaoTalk-native
identifiers.

The release executable is:

```text
apple/eventkit-service/.build/release/sherpa
```

## Native commands

Planner and native framework requests use bounded Worker Protocol V2 JSON on
standard input:

```bash
sherpa planner request
sherpa mail request
sherpa reminder-kit request
```

iMessage reads call its installed native CLI. Sends read the message body from
standard input and require an exact destination confirmation:

```bash
sherpa imessage chats --limit 20
sherpa imessage history --chat-id 42 --start 2026-08-01 --end 2026-08-07 --limit 200
printf '%s' 'message' | sherpa imessage send --chat-id 42 --confirm 42
```

KakaoTalk reads can use Agent Messenger or the Mac's synchronized local database.
The local adapter supports keyword search, one exact room's fixed seven-day
window, and an explicit all-room date range. A complete local archive returns a
pending local-text checkpoint; commit it only after analysis. It remains
separate from Agent Messenger and does not include attachment contents.

```bash
printf '%s' 'exact room display name' | sherpa kakaotalk history --limit 1000
sherpa kakaotalk archive --since 2026-07-01 --time-zone Asia/Seoul --limit 50000
printf '%s' '<checkpoint token>' | sherpa kakaotalk checkpoint --confirm COMMIT_LOCAL_CHECKPOINT
```

Mail can use the strict JSON worker request or the small direct command. The
direct command reads a validated `MailMessage` JSON value from standard input:

```bash
sherpa mail authorization-status
sherpa mail list \
  --from 2026-08-01T00:00:00+09:00 \
  --to 2026-08-02T00:00:00+09:00 \
  --limit 100 --max-body-bytes 16384
sherpa mail read \
  --message-id '<source_message_id>' --max-body-bytes 1048576
printf '%s' '{"sender":"me@example.com","to":["you@example.com"],"cc":[],"bcc":[],"subject":"subject","body":"body"}' \
  | sherpa mail send --confirm SEND_MAIL
```

`mail list` reads the Mail.app inbox in the half-open interval `from <= received
< to`. It returns bounded message bodies, recipients, and attachment metadata;
it never downloads or returns attachment contents. `mail read` resolves exactly
one identifier returned by `mail list` and does not perform fuzzy matching.

Mutation outcomes are recorded in the Swift-owned SQLite journal without
message bodies or native locators:

```bash
sherpa operations list --limit 100
```

A send is journaled `failed` only when it never reached the sender. Once the
sender has been handed the message, any failure is `uncertain`: check the
conversation before sending again. Every failure prints one JSON line with a
named `error` code and exits 1; a journaled send also carries its
`operation_id`. A send that completed but could not be journaled exits 0 with
`"status":"completed"` and `"journal_error":"journal.finish_failed"`, and its
journal row stays `started`. A `planner request` whose journal write fails
still prints its response and logs `[cli:sherpa:journal-failure]` on standard
error.

## Agent skills

The agent skills live in `plugins/sherpa/` and are listed by the `plug-hole`
marketplace. They are not bundled into the CLI archive — installing the CLI
does not install them, and vice versa:

```bash
claude plugin marketplace add https://github.com/XIYO/plug-hole.git
claude plugin install sherpa@plug-hole
```

```bash
codex plugin marketplace add https://github.com/XIYO/plug-hole.git
codex plugin add sherpa@plug-hole
```

Both halves come from this repository, but they reach a machine by different
routes, so their versions can drift. `plugins/sherpa/cli-contract.json` records
the minimum CLI version the skills need, and every skill that calls the CLI runs
`scripts/require-cli.sh` before its first command — an outdated CLI stops the
workflow with a clear message instead of failing partway through.

Private ReminderKit is an optional, unsupported Apple implementation detail.
It is linked behind the `reminder-kit request` adapter and remains disabled for
writes unless its explicit environment and request gates are both satisfied.
