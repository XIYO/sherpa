---
uuid: 01a0ed5f-8dd1-705a-9f48-d51eac1c0851
type: note
audience: "Maintainers checking what was actually observed on a device before trusting a Sherpa claim"
goal: "Find the dated observation behind a current fact, and what that observation did not cover"
tone: "Dated, factual English. Separates what ran from what was inferred or left unobserved"
manner: "Newest entry first; each entry names its device, build, commands, and exact results"
---

# Sherpa Owner-Operated Live Evidence

## 2026-10-05 — Plugin 0.7.8 startup behavior (Codex 0.160.0 and Claude Code 2.1.289)

On macOS, a fresh ephemeral Codex session loaded the installed plugin 0.7.8. A
temporary `sherpa` executable on PATH answered `sherpa 0.0.1`. The session used
the owner's configured hook trust bypass and no model tools. Its answer reported
the startup warning and the installed version 0.0.1. This directly proves that
Codex ran the plugin's SessionStart hook and delivered its context to the model.
The real Homebrew CLI remained 0.7.1 and was not changed by the test.
The probe invoked `codex exec --ephemeral --json --skip-git-repo-check
--dangerously-bypass-hook-trust -C <scratch>` with the fake CLI first on PATH.

On Windows, a logged-in headless Claude Code session loaded the enabled
`sherpa@plug-hole` plugin 0.7.8 alongside `svelte-arch` 7.27.2. The latter's
SessionStart hook reported a fixture version difference. Sherpa showed no
warning, as its CLI is macOS-only. The debug log named the installed Sherpa
version but did not name `session-start.sh`, so this observation does not by
itself prove Sherpa's silent hook executed. The Windows hook CI did run the
Sherpa script with ready, missing, mismatch, and unsupported fixtures and passed.
The host probe used `claude -p` with `--output-format json --max-turns 1
--debug hooks` from a disposable project.

## 2026-09-29 — Journaled send outcomes and the silent top-level failure (CLI 0.7.0 → 0.7.1)

Run here, on this Mac (macOS 26.5.1, Swift 6.3.3), against a debug build of
`d973d74`. No message, mail, Calendar, or Reminder record was read or written;
every send below is a fixture `imsg` run by the real command runner, and every
journal is an in-memory fake.

**The silent failure, reproduced.** `printf '{}' | sherpa planner request`
exited 1 with 0 bytes on stdout and 0 bytes on stderr. The envelope check threw
`WorkerProtocolError.invalidEnvelope`, and the top-level `catch` printed only a
`NativeCommandError`; every other error ended the process without output. On
0.7.1 the same call prints `{"error":"protocol.invalid_envelope","status":"failed"}`
and exits 1. A decode error in `mail send` input, which fails before any send,
prints `sherpa.internal_failure`. The gate now runs the `{}` call itself.

**The send outcomes, pinned before the fix.** The 0.7.0 `journaled` control
flow was ported unchanged into `SherpaMutationApplication`, and five tests were
run against it:

- rejected before the sender launched → `failed`: passed. This was already
  correct and is now pinned.
- sender launched, then its output exceeded the bound → expected `uncertain`,
  journaled `failed`. The runner threw `outputTooLarge` after the child ran,
  and only `uncertain` was mapped to `uncertain`.
- sender accepted, completion write refused → expected `completed` with a named
  journal failure. Instead the same `catch` wrote `failed`, which the fake
  accepted, and the command threw.
- sender failed after launch, failure write refused → the error did not say the
  journal missed it.
- journal start refused → the raw store error escaped instead of a named one.

A runner test (`effect: .mutation`, output over the limit) threw
`outputTooLarge`. After the fix all six pass, and so do the other 79 tests in
`eventkit-service`.

**Not observed.** A real iMessage or Mail send through 0.7.1, a real SQLite
write failure after a send, and an installed 0.7.1 binary. The journal failure
paths are proven only against the fake journal.

## 2026-09-21 — Codex update, pinning, and session load (codex-cli 0.155.1, macOS)

Run here, on this Mac, with three throwaway `CODEX_HOME` directories and local
probe marketplaces. It closes what the `sherpa@xiyo` catalog entry below left
open for Codex: update, `ref`/`sha` pinning, and session load. Everything in
this entry is codex-cli 0.155.1 on macOS; the Windows 11 device runs 0.154.0
and was not used.

**There is no `codex plugin update`.** `codex plugin --help` lists exactly four
subcommands: `add`, `list`, `marketplace`, `remove`. The two update paths are
`codex plugin marketplace upgrade [NAME]` and re-running
`codex plugin add <plugin>@<marketplace>`.

**`codex plugin add` never compares versions; it re-checks-out the source every
time.** Two independent proofs.

1. *Inode and a planted file.* A marker was written into the install cache
   (`PROBE-MARKER.txt`), then `codex plugin add` was re-run for the same
   plugin at the same version. The cache directory's inode changed from
   `1789998717` to `1789998735` and the marker was gone. The file count was 28
   before and after, so a count alone would have shown nothing.
2. *Same version string, two commits.* The probe marketplace pointed at two
   commits of this repository that both carry the plugin version
   `0.7.0+codex.20260827020000` — `0dc0efc4` (no hooks) and `1b6408c0`
   (SessionStart hook present). Flipping only `sha` between them and re-running
   `add` moved the cache between 22 and 28 files, and between "no `hooks/`
   directory" and `hooks/hooks.json` plus `hooks/session-start.sh`. The version
   string never changed. Under Claude Code's rule the second install would have
   been a no-op.

**Codex deletes the old version directory.** After an upgrade the marketplace
holds exactly one cache directory. Claude Code, by contrast, leaves the old one
in place when a `ref` pin is removed and the plugin is updated (the
`ref: v0.7.0` row of the catalog entry below).

**Codex honours `ref` and `sha`; it does not silently drop them.** Five local
probe marketplaces, one variant each.

| Probe source fields | Installed |
| --- | --- |
| `ref: v0.7.0` | 0.7.0 |
| `sha: ce628821c4b3b51fb87c3f3a1c31d3ffae64e7ac` (the 0.7.1 commit) | 0.7.1 |
| `ref: main` + the same `sha` | 0.7.1 — **`sha` wins** |
| `sha: deadbeef…` (does not exist) | **exit 1**, see below |
| `zzzbogus: …` (unknown field) | installs, no message — the unknown field is dropped |

The nonexistent `sha` is the decisive one. It does not fall back to the tip:

```text
Error: git checkout deadbeef… failed with status exit status: 128
fatal: upload-pack: not our ref
```

So the only thing Codex discards in silence is a field it does not know. That
is the same trap the `github` source sprang with `path` (the subdirectory probe
entry below), still living in the schema layer.

**Runbook value.** The human-readable output of `codex plugin marketplace
upgrade` answers `Upgraded marketplace … to the latest configured revision.`
even when nothing changed. Only `--json` tells the truth, with
`upgradedRoots: []`.

**Session load is half closed.** `codex debug prompt-input [PROMPT]` ("Render
the model-visible prompt input list as JSON") exits 0 without a login. Its
`<skills_instructions>` block carries all five `sherpa:*` skills —
`agent-messenger`, `context`, `kakaotalk-local-search`, `planner`, `sherpa` —
each with the install cache path as its skill root. What remains is whether the
model actually invokes one, and `codex exec` stops at 401 Unauthorized. That is
the same root as the open Claude Code item.

**Whether Codex registers this plugin's SessionStart hook is not known.**
`.codex-plugin/plugin.json` declares `skills` only and has no hooks key; the
cached `hooks/hooks.json` describes itself as a "Claude Code adapter" and its
command uses `${CLAUDE_PLUGIN_ROOT}`. The codex binary does contain the string
`hooks/hooks.json`, but `RUST_LOG=debug` produced no hook log line. Neither
"registers" nor "does not register" is supported.

**User configuration untouched.** All three `CODEX_HOME` directories were
temporary and were removed, as were the probe marketplaces. `~/.codex/plugins`
has zero files written — checked before and after.

## 2026-09-21 — Two marketplaces share one skill namespace; re-reading the hook line

No new install was performed for this. It is a documentation reading plus a
re-reading of evidence already in this file.

**Confirmed: Claude Code names a skill after the plugin alone.** The name is
`sherpa:planner`; the marketplace is not part of it. Three sources agree.
`code.claude.com/docs/en/discover-plugins` (read on this date) states "Plugin
skills are namespaced by the plugin name". `plugins-reference` states that "the
agent `agent-creator` for the plugin with name `plugin-dev` will appear as
`plugin-dev:agent-creator`". The name-construction site in the claude 2.1.278
bundle does the same. So installing both `sherpa@sherpa` and `sherpa@xiyo`
produces five same-named skills and one same-named hook with **no way to
address one rather than the other**.

**Re-read, not re-run: the coexistence entry below already recorded who won.**
The `sherpa@xiyo` catalog entry of this same date logs
`Skipping duplicate hook registration for plugin "sherpa" from sherpa@sherpa`.
That message names the registration being *displaced*, so in that measurement
`sherpa@xiyo` had already registered and `sherpa@sherpa` was the one skipped —
**`sherpa@xiyo` won.** The same entry's other observation points the same way: a
bare `claude plugin details sherpa` resolved to `sherpa@xiyo`. The original
entry is left exactly as it was written; what is new here is knowing what that
line meant.

**Inferred, not reproduced.** Reading the obfuscated bundle suggests the winner
is decided by key order in `settings.json`'s `enabledPlugins`, with skill-list
assembly being first-wins. Version plays no part, so an older copy can win. And
`~/.claude-secondary` stores `enabledPlugins` alphabetically while `~/.claude` stores
it in install order, which would mean the winner can flip whenever the settings
file is rewritten. None of this was reproduced, and it cannot be reproduced on
this Mac right now: all four Claude profiles hold `sherpa@sherpa` 0.7.2 and
nothing else, `sherpa@xiyo` is installed in none of them (only the marketplace
is registered, in all four; `~/.claude`'s `xiyo` has `autoUpdate: true`), and
the only cache directory is `0.7.2`.

**A related mtime question is answered.** `CURRENT.md` used to say that the
`installed_plugins.json` files were rewritten at 08:04–08:07Z by an unknown
actor. The sherpa entries do carry those timestamps, but the files themselves
were rewritten later the same day by another plugin update: that
entry's `lastUpdated` is 11:59:50.793Z in one file and
12:00:04.606Z in the other. Files were read only; nothing under `~/.claude*`
was written.

## 2026-09-21 — `agent-messenger` 2.38.0 carries the Discord emoji and sticker commands

Deterministic package evidence, not an owner-operated live run. It answers the
question the `CURRENT.md` "next candidates" list left open: whether upstream
`agent-messenger/agent-messenger#337` (Discord custom emoji and stickers) had
actually shipped to npm. It had, in `agent-messenger@2.38.0`. This is why
plugin 0.7.4 writes those commands into `skills/agent-messenger/SKILL.md`.

No automated gate protects those command names. `verify_commands.py` only
matches calls that begin with `sherpa `, and step 6 of
`plugins/sherpa/scripts/check.sh` explicitly excludes `agent-messenger` from
the guard-reference rule because the skill drives an upstream CLI. The
existence check for these lines is this entry and nothing else, so the four
checks are written here in a form that can be repeated.

1. **Timing.** The pull request's `mergedAt` is 2026-09-21T08:04:51Z; npm
   published 2.38.0 at 2026-09-21T08:13:17.825Z, eight minutes later.
2. **Lineage.** `npm view agent-messenger@2.38.0 gitHead` is
   `505738a15d47a9e1d76f16302288bc347d427d84`. GitHub's compare of the merge
   commit `46268c9e142179566b49c2c4af50787ed9854926` against that `gitHead`
   reports ahead 1, behind 0 — the published tree descends from the merge
   rather than predating it.
3. **Tarball.** The 2.38.0 package contains
   `src/platforms/discord/commands/emoji.ts`, `sticker.ts`,
   `expression-format.ts`, and `expression-names.ts`, and
   `src/platforms/discord/cli.ts` registers them with `addCommand(emojiCommand)`
   and `addCommand(stickerCommand)`.
4. **Execution.**
   `bunx --yes --package agent-messenger@2.38.0 agent-messenger discord emoji --help`
   and the `sticker` equivalent exit 0 and print the signatures the skill now
   documents.

Checks 1 to 3 and the pinned help runs were performed in another session.
Repeated here against the unpinned form the skill actually uses:
`npm view agent-messenger version` answers `2.38.0`, and
`bunx --yes --package agent-messenger agent-messenger discord <server|emoji|sticker> --help`
plus `discord sticker create --help` each exit 0. Those runs are what fixed two
details of the wording: `server info` takes the server id as an argument
(`info [options] <server-id>`), and `--tags <emoji>` is the only required
option among the six commands.

Still unverified. `emoji list` and `sticker list` have not been run against a
real Discord guild, and nothing has been uploaded or deleted. By this
repository's standard there is no owner-operated live evidence for these
commands at all. The local pre-request name and byte-sniffing validation, the
`server info` slot fields, the `MANAGE_GUILD_EXPRESSIONS` requirement, and the
VERIFIED/PARTNERED restriction on Lottie stickers are read from the upstream
help text and sources — no observed response carries them.

## 2026-09-21 — Installed plugin 0.7.3 on a real Windows device

Reported by the Windows session, the session that operates a Windows 11
device. Nothing in this entry was run here.

- **Update path.** `claude plugin update sherpa@xiyo --scope user` answered
  "updated from 0.7.2 to 0.7.3 for scope user".
- **Hook.** `bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start.sh"`, the same
  invocation `hooks.json` declares, run against the installed 0.7.3 cache: exit
  0, no stdout, no stderr. With no output there is no `additionalContext`.
- **Guard.** `bash "$CLAUDE_PLUGIN_ROOT/scripts/require-cli.sh"` exited 1. The
  platform value is that device's real `uname -s`, with no fake in place, and
  `brew` appears in neither stream (checked with grep).

  ```text
  stdout  {"status":"unsupported","reason":"macos_only","platform":"MINGW64_NT-10.0-26200","remedy":"none on this device: the Sherpa CLI runs only on macOS, so use these skills on a Mac"}
  stderr  warn [plugin:sherpa:require-cli:failure] platform=MINGW64_NT-10.0-26200; the Sherpa CLI runs only on macOS
  ```

Limit stated by that session: it could not open a new logged-in Claude Code
session. What is confirmed ends at the hook's empty output under the declared
invocation. That a real session on that device shows nothing, and how the model
words the `unsupported` answer when it calls a skill there, were not observed.
This replaces the "every session reads the install sentence" state of the 0.7.2
entry below for the hook's output, not for a session screen.

## 2026-09-21 — Actions billing block; hosted jobs removed; first green `main` since 0.7.2

Observed here with `gh`. From the merge of PR #8 on, GitHub did not start the
hosted jobs: "The job was not started because recent account payments have
failed or your spending limit needs to be increased."

| Run | Commit | Jobs |
| --- | --- | --- |
| 35575597752 (`main` push) | plugin 0.7.2 | `Repository gate` failure, `Windows hook gate` failure; neither started, a re-run ended the same way |
| 35589839153 (`main` push) | plugin 0.7.3 | `Repository gate` (`macos-latest`) failure, `Windows hook gate` (`windows-latest`) failure, neither started; `Windows hook gate (self-hosted)` success on the self-hosted Windows runner |
| 35605438357 (PR #11) | hosted jobs removed | `Windows hook gate` success on the self-hosted Windows runner |
| 35605553318 (`main` push) | PR #11 squash | `Windows hook gate` success on the self-hosted Windows runner; run conclusion success |

Neither red `main` run was a code failure. The 0.7.2 merge commit has the same
tree as the last commit of PR #8, which passed both hosted checks before the
block began. Whether the CI iterations of the 0.7.2 work pushed the account over
a limit is not known.

Owner decision, relayed by the Windows session quoting the owner: no
GitHub Actions payment; connect everything to self-hosted runners. PR #11
removed the two hosted jobs from `verify.yml`. A job that is always red hides a
real failure, and the jobs can be restored from git history if billing is
resolved. The remaining runner is a self-hosted Windows runner (labels
`self-hosted`, `Windows`, `X64`), online at the time of these runs. PR #10
(plugin 0.7.3) was merged by the Windows session on the owner's instruction, as
that session reported.

Consequence: the macOS gate (`scripts/check-all.sh`) no longer runs in CI. No
macOS self-hosted runner was attached: the owner gave no such instruction for
this repository, `check-release.sh` unlinks and relinks the real `sherpa`
Homebrew formula on the machine it runs on, and a laptop runner sleeps with its
lid closed, leaving jobs queued. `AGENTS.md` now requires a local full-gate
exit 0, recorded in the pull request body, before a merge. On this Mac the gate
exited 0 after the last change of PR #11 and again after the last change of
PR #9.

Installed copies on this Mac, read from files only and not modified:
`~/.claude` and `~/.claude-secondary` both list `sherpa@sherpa` 0.7.2, each with a
single `0.7.2` cache directory; both `installed_plugins.json` files were updated
on 2026-09-21 between 08:04Z and 08:07Z. In `~/.claude-secondary`, all 10
`installPath` values and all 5 `installLocation` values now lie under
`~/.claude-secondary/`, unlike the state recorded in the `~/.claude-secondary` entry
below (11 and 15, all under `~/.claude/`). This session did not make that change
and does not know who did; `claude plugin marketplace update` was not re-run in
that profile.

## 2026-09-21 — Plugin 0.7.3 on a real Windows device; the check picked a WSL `bash.exe`

Windows session report (a Windows 11 device), not run here. That session
ran `verify_session_start.py` from branch `feat/plugin-0.7.3-non-macos-silence`
at `9d77b03`.

As committed, every case failed with `hook exited 126` and output `''`. The
cause was the check, not the hook. `find_bash()` returned a WSL launcher:

```text
DEBUG rc=126  stderr=b'/bin/bash: /bin/bash: cannot execute binary file\n'
BASH = %USERPROFILE%\AppData\Local\Microsoft\WindowsApps\bash.exe
```

That device has two `bash.exe` on PATH: `C:\WINDOWS\system32\bash.exe`, which
the `SystemRoot` exclusion skipped, and `…\Microsoft\WindowsApps\bash.exe`, a
Store app-execution alias that the exclusion did not cover. Git Bash
(`C:\Program Files\Git\bin\bash.exe`) is not on PATH at all. The `git`-relative
fallback knew the right answer but ran only after the PATH scan had already
returned the wrong one.

With BASH forced to Git Bash the check exited 0 with no failures, so the 0.7.3
logic passes on real Windows. The `cygpath -u` re-prepend that keeps the fake
`uname` ahead of Git for Windows' `usr/bin/uname` works there, and so do fake
scripts without an exec bit. This closes the "fake `uname` may be shadowed" item
that PR #10 left unverified. With the real `uname`, the hook printed nothing and
exited 0.

Corrected here: `find_bash()` no longer lists bad directories. It collects the
PATH candidates and the `git`-relative paths, runs `bash -c 'echo $OSTYPE'` on
each with a timeout when on Windows, and takes the first that answers `msys` or
`cygwin`; if none does, it fails with every candidate and its rejection reason.
The selection function is exercised with fake candidates (exit 126, `linux-gnu`,
no answer, missing file, `msys`) inside the same check, so the macOS gate covers
it. Against the previous pick-the-first-file logic that self-check failed on
this Mac with `bash selection: picked '…/exits-126', expected the one whose
OSTYPE is msys`. A self-hosted job on that device was added to `verify.yml`
next to the hosted `windows-latest` job.

Run on the device by that self-hosted job (workflow run 35579700068, job
`Windows hook gate (self-hosted, <device>)`, 37 s, success; pwsh 7.6.6, git
2.55.0.windows.3, checkout `i/lf w/crlf`). `Get-Command bash` listed only the two
WSL launchers. The check logged:

```text
[check:sherpa:bash] chosen=C:\Program Files\Git\bin\bash.exe rejected=2
[check:sherpa:bash] rejected C:\WINDOWS\system32\bash.exe: OSTYPE is 'linux-gnu', not one of ('msys', 'cygwin')
[check:sherpa:bash] rejected %USERPROFILE%\AppData\Local\Microsoft\WindowsApps\bash.exe: OSTYPE is 'linux-gnu', not one of ('msys', 'cygwin')
[check:sherpa:hook] verified with %USERPROFILE%\AppData\Local\Microsoft\WindowsApps\python3.exe
```

Both WSL launchers ran and answered, so an "is it executable" probe alone would
have accepted them; the OSTYPE is what separates them from Git Bash. Git Bash was
reached through the `git`-relative path. The two hosted jobs of the same run did
not start: "The job was not started because recent account payments have failed
or your spending limit needs to be increased."

After that run the runner was renamed and relabelled: it now carries only the
automatic labels `self-hosted`, `Windows`, `X64`; the custom device label is
gone. The job now asks for `[self-hosted, Windows]` and its display name no
longer names a device. The record above replaces the device, runner, and user
names that run used with generic placeholders.

## 2026-09-21 — Plugin 0.7.2 on a real Windows device

Reported by the Windows session, the session that operates a Windows 11
device. Nothing in this entry was run here. It closes the two Windows questions
left open after the 0.7.2 merge.

- **Update path.** `claude plugin marketplace update xiyo` succeeded. The listing
  then read `sherpa@xiyo / Version: 0.7.1 / Scope: user`.
  `claude plugin update sherpa@xiyo --scope user` answered "updated from 0.7.1 to
  0.7.2 for scope user". The cache holds both 0.7.1 and 0.7.2 and the listing
  reads 0.7.2. No uninstall was needed.
- **Hook, four states.** Every run exited 0 and no payload carried a CR byte.

  | State | How it was reached | `additionalContext` |
  | --- | --- | --- |
  | `missing` | the device's real state, no fake | "Sherpa CLI가 설치되어 있지 않습니다. … 설치: brew install xiyo/package-hole/sherpa" |
  | `ready` | fake `sherpa` 0.7.0 | no output |
  | too old | fake `sherpa` 0.6.9 | "…계약과 어긋납니다(설치됨 0.6.9). 조치: brew install xiyo/package-hole/sherpa" |
  | too new | fake `sherpa` 9.0.0 | "…(설치됨 9.0.0). 조치: update this plugin (its skills expect an older CLI)" |

- **Python on that device.** `python3` is
  `%USERPROFILE%\AppData\Local\Microsoft\WindowsApps\python3.exe`, an App
  Execution Alias that leads to Python Manager. It is a real interpreter, not the
  Store stub, and it ran with exit 0. `python` is
  `…\Programs\Python\Python314\python`. The hook therefore used `python3` on
  this device, and **the `python3` → `python` fallback still has no real-device
  run**; it remains exercised only by the simulated `renamed` case. CRLF was the
  single cause of the 0.7.2 defect.
- **Every session on that device now reads the install sentence.**
  `~/.claude/settings.json` there enables `sherpa@xiyo: true` globally, the CLI
  is macOS-only, so the state is always `missing` and each session is told to run
  `brew install …`, a command that device cannot run. Whether the hook should
  speak on a non-macOS device is an owner decision.
- **plug-hole hit the same Actions billing block.** The jobs for its main push
  were not started; its local gate and pre-push hook passed.

## 2026-09-21 — SessionStart hook read every state as a failure on Windows (plugin 0.7.2)

Reported by another session operating a Windows 11 / pwsh 7 device, then
reconfirmed here from the code and on a GitHub `windows-latest` runner. The
guard `require-cli.sh` was correct (`{"status":"missing",...}`, exit 1). The hook
extracted the guard's fields with `python3 -c '... print(...)'` and read them
with bash `read`. Python's stdout is in text mode on Windows, so `print()` writes
`\r\n`; bash `read` strips only `\n`. `ready\r`, `missing\r`, and `mismatch\r`
match no `case` pattern, so every state fell to the catch-all branch and every
session read "Sherpa CLI 확인에 실패했습니다(…\r)", including one whose CLI
satisfied the contract. `emit()` appended `\r` to the payload for the same
reason. The reporting session confirmed that `sys.stdout.reconfigure(newline="\n")`
in both Python calls restores the `ready` branch and silence.

Two reasons it went unnoticed, both corrected. `check-windows.ps1` checked only
the manifests on the premise that nothing runs on Windows; that holds for the
CLI but not for the hook, which `hooks.json` registers unconditionally, and
nothing called the script anyway. And `verify_session_start.py` asked only
whether the install command was contained in the context, which the catch-all
branch also satisfies because it interpolates the remedy.

Reproduced before the fix on this Mac (Python 3.14.7) with the new regression
case, which gives the hook a `python3` whose `sitecustomize.py` reconfigures
stdout to `\r\n`. `plain` passed; `crlf` failed in all four states, for example
`crlf/ready: hook spoke while the CLI satisfies the contract: …(\\r)…}}\r\n` and
`crlf/missing: fell through to the catch-all branch: 'Sherpa CLI 확인에
실패했습니다(brew install xiyo/package-hole/sherpa\r). …'`. The `renamed` case
(a `python3` that exists but does not run, plus a working `python`) failed with
empty output: the old hook said nothing at all when `python3` did not run.

Reproduced on real Windows. A probe branch carrying the new check and the
unfixed hook ran on `windows-latest` (workflow run 35574980007, since cancelled;
the branch is deleted): the unsimulated `plain` case failed in all four states
with the same sentences and the same `\r`. The fix branch passed on the same
runner image (run 35574887239).

Facts recorded by that runner (image win25-vs2026 20260907.229, pwsh 7.6.5, git
2.55.0.windows.5):

| Question | Observed |
| --- | --- |
| Is there a `python3`? | Yes. `C:\hostedtoolcache\windows\Python\3.12.10\x64\python3.exe`, then `…\WindowsApps\python3.exe`. `python.exe` exists in the same two places. The check ran with the hostedtoolcache `python3.exe`. |
| Which `bash`? | `C:\Program Files\Git\bin\bash.exe`, then `C:\Windows\system32\bash.exe`, then `C:\Program Files\Git\usr\bin\bash.exe`. The check skips the System32 entry. |
| Line endings of the checkout | `core.autocrlf=true` from the system gitconfig; `session-start.sh`, `require-cli.sh`, `hooks.json`, and `cli-contract.json` are all `i/lf w/crlf`. Git Bash ran the hook and the guard to completion from those CRLF files and the check passed, so CRLF script files are not a cause of this defect. |
| Extensionless fake `sherpa` on PATH | Git Bash resolves and runs a `#!/bin/sh` script without an extension; the four states were reachable. |

Audited here at the same time: the hook is the only place in the plugin where
bash reads another tool's output and branches on it. `require-cli.sh` does not
call Python; it reads the contract file with `sed` and builds JSON with bash
`printf`. The three Python scripts under the skills are read by the agent, not
by bash, and `check.sh` is a macOS/Linux gate only.

Not verified: a real Windows device that has no `python3`. The `python3` →
`python` fallback is exercised only by the simulated `renamed` case. `pwsh` is
not installed on this Mac, so `check-windows.ps1` was executed only on the
runner. A real Claude Code session on Windows picking up 0.7.2 through
`plugin update` is left to the Windows session after the merge.

Reported by the Windows session in the same exchange (Windows 11 Pro 26200,
codex-cli 0.154.0, pwsh 7), not run here:

- `codex plugin marketplace upgrade` exited 0, then `codex plugin add sherpa@xiyo`
  exited 0. The cache
  `%USERPROFILE%\.codex\plugins\cache\xiyo\sherpa\0.7.1+codex.20260921101159`
  holds 28 files, the same file list as the Claude Code cache for 0.7.1. The
  listing reads `sherpa@xiyo → https://github.com/XIYO/sherpa.git`, path
  `plugins/sherpa`. **Windows Codex resolves `git-subdir`.** The plugin was then
  removed with `codex plugin remove sherpa@xiyo`, because it is macOS-only and
  of no use on that device.
- Before `upgrade`, sherpa was absent from the listing. That is not a Codex or
  documentation defect: the command had not been run on that device. Both
  plug-hole READMEs already put `codex plugin marketplace upgrade xiyo` first in
  their `## 업데이트` section and explain why the background refresh fails
  silently for a private repository.
- `git ls-remote https://github.com/XIYO/sherpa.git` exited 0. The device has
  access, so this does not show how an account without access fails.

## 2026-09-21 — Claude Code did not load `AGENTS.md` here; `CLAUDE.md` import

The repository's only agent instruction file was `AGENTS.md`, and a Claude Code
session opened in this checkout did not have it in context. The official memory
documentation (code.claude.com/docs/en/memory, read on this date) says Claude
Code v2.1.277 or later reads `AGENTS.md` directly, but only when no
`CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` exists in the working
directory or any directory above it, and not at all in sessions that cannot
fetch feature flags (third-party providers, telemetry disabled, the first
session after an install or upgrade, `disableAllHooks`). For those cases it
recommends a `CLAUDE.md` next to `AGENTS.md` containing the `@AGENTS.md` import,
and the import rather than a symbolic link when anyone clones on Windows.

Measured with claude 2.1.278, `claude -p` run from the repository root with
`CLAUDE_CONFIG_DIR` pointed at a new scratch directory that held only a
`settings.json` registering an `InstructionsLoaded` command hook that appended
its payload to a scratch file. There was no login, so the run ends with exit 1
at the API call; the hook fires before that. No user configuration directory was
written.

| State | `InstructionsLoaded` payloads |
| --- | --- |
| Before (`AGENTS.md` only) | `~/.claude/CLAUDE.md`, `memory_type: Project`, `load_reason: session_start` |
| After (`CLAUDE.md` = `@AGENTS.md`) | the same, plus `<repo>/CLAUDE.md` (`Project`, `session_start`) and `<repo>/AGENTS.md` (`Project`, `load_reason: include`, `parent_file_path: <repo>/CLAUDE.md`) |

With `CLAUDE_CONFIG_DIR` set to anything other than `~/.claude`, the file
`~/.claude/CLAUDE.md` is loaded as a project instruction file, because it is a
`.claude/CLAUDE.md` in a directory above the checkout. By the documented rule
that alone stops direct `AGENTS.md` reading for every such profile on this Mac.
The documentation states that `InstructionsLoaded` does not fire for an
`AGENTS.md` read directly, so the "before" row cannot by itself prove that
`AGENTS.md` was skipped; the cold feature-flag cache of a login-free first
session is a second documented reason it would be. The "after" row is direct
evidence that the import loads it. What the model receives in a logged-in
session was not observed.

`scripts/checks/verify_docs.py` now fails when `CLAUDE.md` is missing, is a
symbolic link, or is anything other than the single line `@AGENTS.md`; each case
was run against a scratch copy and exited 1, and the correct form exited 0.

## 2026-09-21 — `sherpa@xiyo` catalog entry: install, coexistence, update, session load

`XIYO/plug-hole` PR #5 (merge commit; macOS and Windows CI both passed, and the
post-merge main CI run succeeded) added `sherpa` to both of its manifests,
`.claude-plugin/marketplace.json` for Claude and
`.agents/plugins/marketplace.json` for Codex, with the source object
`{"source":"git-subdir","url":"https://github.com/XIYO/sherpa.git","path":"plugins/sherpa"}`.
The plug-hole checker used to admit only in-repository products (entry equals
published equals a `plugins/` directory, source `./plugins/<name>`). It now
admits an external product only when `catalog-policy.json` declares it under
`external` (`{"sherpa":{"url":...,"path":...}}`): the name must be published and
cannot be primary, `url` must be a full `https://….git`, `path` must be
relative, the source object in both catalogs must equal the declaration down to
its keys, `ref` and `sha` pins are rejected, and the `github` source is
rejected. Four checker tests cover this. `XIYO/plug-hole` and `XIYO/sherpa` are
both PRIVATE.

Every Claude command below ran with claude 2.1.278 and `CLAUDE_CONFIG_DIR`
pointed at a new empty scratch directory. `~/.claude`, `~/.claude-secondary`, the
two further Claude profile directories, `~/.codex`, and the global git
configuration were identical before and after every check in this entry.

- **Install.** `claude plugin install sherpa@xiyo` exited 0. The cache
  `cache/xiyo/sherpa/0.7.1/` holds only the contents of `plugins/sherpa/`, 28
  files, no `.git`. `claude plugin details` reports `sherpa 0.7.1`, Skills (5),
  Hooks (1) SessionStart.
- **Coexistence.** With `sherpa@sherpa` and `sherpa@xiyo` installed into the
  same configuration, both list as 0.7.1 enabled and no conflict message
  appears. The debug log reads `Total plugin skills loaded: 10 (0 duplicate…
  skipped)`, yet the session init event names only the five `sherpa:*` skills.
  The hook registers once:
  `Skipping duplicate hook registration for plugin "sherpa" from sherpa@sherpa`.
  A bare `claude plugin details sherpa` resolves to `sherpa@xiyo`. Which of the
  two same-named skills actually runs was not verified.
- **Update and pinning.** `claude plugin update sherpa@xiyo` answered "already
  at the latest version (0.7.1)". A temporary probe marketplace showed that
  `ref: v0.7.0` and a `sha` pin both pass validate and install. After the pin
  was removed and the plugin updated, the `ref` install moved 0.7.0 → 0.7.1 and
  left the old cache directory in place; the `sha` install answered "already at
  the latest" and its recorded commit did not change. **Update compares the
  version number only and never looks at the commit**, so the rule that the
  version number is the only cache-invalidation signal holds for `git-subdir`
  as well.
- **Session load.** Without a login,
  `claude -p … --output-format stream-json --verbose --debug-file` emitted an
  init event that carries the cache path and the five `sherpa:*` skills, and the
  SessionStart hook exited 0. The run ended with "Not logged in", so a model
  actually invoking one of these skills was not verified.
- **Remote, after the merge.** In another new empty configuration,
  `claude plugin marketplace add XIYO/plug-hole` exited 0 with the shorthand as
  given; the resulting remote is HTTPS, and whether SSH was attempted first was
  not observed. `claude plugin install sherpa@xiyo` then exited 0 with 0.7.1,
  Skills (5), Hooks (1).
- **Codex.** codex-cli 0.155.1 with an empty `CODEX_HOME`:
  `codex plugin add sherpa@codex-probe` exited 0, version
  `0.7.1+codex.20260921101159`, and the cache holds the `plugins/sherpa` tree
  with five skills. Only the install was checked. Codex update, pinning, and
  session load were not verified.

Nothing was run on Windows. plug-hole's `CURRENT.md` (ruling 18) and the PR
body carry a handoff to the Windows session, which is the same
`XIYO/plug-hole` repository operated on the Windows device rather than a
separate repository. It asks how `sherpa` appears after a marketplace update,
how the SessionStart hook (bash and python3) and `require-cli.sh` end on
install, and whether Windows Codex resolves `git-subdir`. plug-hole's Windows
gate iterates only its `plugins/` directory, so it runs nothing for sherpa, and
nothing anywhere calls sherpa's `check-windows.ps1`.

Inferred, not run: plug-hole is held back from going public until it is
finished. Once it is public, an account without access to `XIYO/sherpa` should
fail to install this entry. No account without access was used to try it.

## 2026-09-21 — `~/.claude-secondary` sherpa update and a registry that points at `~/.claude`

`CLAUDE_CONFIG_DIR=~/.claude-secondary claude plugin update sherpa@sherpa` exited 0
and moved the install 0.7.0 → 0.7.1. Its install guidance is now
`brew install xiyo/package-hole/sherpa`, and `claude plugin list` reports no
error. The 0.7.0 cache directory remains beside the new one.

The update exposed a structural problem in that profile. All 11 `installPath`
values in `~/.claude-secondary/plugins/installed_plugins.json` and all 15
`installLocation` values in `known_marketplaces.json` pointed into
`~/.claude/plugins/...`. The sherpa that profile had been reading was therefore
the 0.7.0 cache under `~/.claude`. `claude plugin marketplace update sherpa`
exits 1 before git runs, with
`corrupted installLocation … expected a path inside ~/.claude-secondary/plugins/marketplaces … remove and re-add`.
All 15 entries are in the same state, so every marketplace update fails in that
profile. The profile's own sherpa marketplace clone is still at 2026-08-27.

Inferred, not proven: the plugin update succeeded because the CLI followed the
stale `installLocation` and read the current clone under `~/.claude`. The basis
is that the newly recorded `gitCommitSha` equals that clone's HEAD.

The registry was not re-registered. That reaches beyond sherpa and can drop
installed plugins, so it is left as an owner decision.

## 2026-09-21 — Marketplace subdirectory source probe

ADR-0007 left open which marketplace field makes an entry resolve a plugin that
lives in another repository's subdirectory (`XIYO/sherpa`, `plugins/sherpa/`).
`claude plugin validate --strict` could not decide it, so the question was
settled by real installs with claude 2.1.278. Every `claude plugin` command ran
with `CLAUDE_CONFIG_DIR` pointed at a new empty scratch directory. SHA-256
digests of `installed_plugins.json`, `known_marketplaces.json`, and
`settings.json`, plus the cache and marketplace directory listings, under
`~/.claude`, `~/.claude-secondary`, and the two further Claude profile directories
were identical before and after. No global git configuration was changed and
no credential value was printed.

A local directory marketplace `sherpa-probe` declared four entries against the
same repository:

| Variant | `source` object |
| --- | --- |
| A | `{"source":"git-subdir","url":"XIYO/sherpa","path":"plugins/sherpa"}` |
| A2 | `{"source":"git-subdir","url":"https://github.com/XIYO/sherpa.git","path":"plugins/sherpa"}` |
| B | `{"source":"github","repo":"XIYO/sherpa","path":"plugins/sherpa"}` |
| C | `{"source":"github","repo":"XIYO/sherpa","subdirectory":"plugins/sherpa"}` |

`claude plugin validate --strict` exited 0 for the combined manifest and for
each variant validated alone. Validation again distinguished nothing.

The first `claude plugin install <name>@sherpa-probe` of A, B, and C exited 1
with `git@github.com: Permission denied (publickey)`. The `owner/repo`
shorthand is cloned over SSH, for both `github` and `git-subdir`, and this Mac
has no GitHub SSH identity; its GitHub access is HTTPS through the
`gh auth git-credential` helper. A2 installed with exit 0 and no workaround,
so the full HTTPS URL uses the system credential helper and reaches the private
repository. To observe A, B, and C past the clone, the installs were repeated
with a process-scoped rewrite only
(`GIT_CONFIG_COUNT=1`, `GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf`,
`GIT_CONFIG_VALUE_0=git@github.com:`). All three then exited 0 with
`Successfully installed plugin`.

Install success did not mean the subdirectory was resolved. The cache showed:

| Variant | Cache directory | Cache root | `claude plugin details` |
| --- | --- | --- | --- |
| A, A2 | `<name>/0.7.1` | `.claude-plugin/plugin.json`, `skills/` (5), `hooks/`, `scripts/`, `cli-contract.json`; 28 files, no `.git` | `sherpa 0.7.1`, Skills (5), Hooks (1) SessionStart |
| B, C | `<name>/571c8352d7e7` | whole repository root (`apple/`, `docs/`, `plugins/`, `runtime/`, `CURRENT.md`, ...); `.claude-plugin/` holds only `marketplace.json`; 138 files | entry name only, Skills (0), Hooks (0), always-on ~0 tok |

`git-subdir` with `path` is the only form that resolves the subdirectory: the
cache root is the plugin root and the version comes from `plugin.json`. The
`github` source silently ignores both `path` and `subdirectory`, copies the
repository root, finds no plugin manifest there, falls back to the 12-character
commit prefix as the version, and registers an enabled plugin with zero
components. It reports no error at validate, install, or list time, which is
the failure this probe existed to catch.

All four probe plugins were uninstalled and the marketplace was removed;
`claude plugin list` and `claude plugin marketplace list` in the scratch
configuration ended empty. `XIYO/plug-hole` was not modified. Not covered:
`ref`/`sha` pinning on `git-subdir`, `claude plugin update` behaviour for a
`git-subdir` entry, and a session actually loading the skills from such an
install.

## 2026-08-10 — iCloud Calendar residue discovery gap

An owner screenshot and iCloud.com inspection showed many server-side Calendars
whose titles begin with `Sherpa disposable Calendar verification` or
`Sherpa EventKit disposable`. The same Mac's Calendar UI and
`event.source.list` exposed only seven Calendars and none of the disposable
titles. This disproves the earlier claim that an immediate local EventKit
absence read-back proves remote cleanup.

Source discovery now calls EventKit's public `refreshSourcesIfNecessary()`
before reading Calendar or Reminder collections. Deterministic spies prove
that refresh precedes both reads, and the Swift package's 68 tests pass. An
owner-operated release query still returned seven Calendars and zero Sherpa
residue after that refresh. Therefore EventKit remains a device-local view and
cannot be the sole authority for iCloud cleanup verification. Direct iCloud
Calendar reconciliation remains incomplete and requires an authenticated
server boundary; no server-side deletion was attempted.

## 2026-08-05 — Rust-owned disposable destination v4

The owner-approved release CLI created its own disposable Calendar and
Reminder list from explicit safe source references, exercised the public item
workflows inside those destinations, and removed both the items and their
destinations. Both commands returned
`eventkit.live_synthetic_crud.v4` with `supported` state.

The Calendar path journaled five verified mutations: Calendar create, Event
create, future-series update, future-series delete, and Calendar delete. Its
exact item read-backs, both bounded occurrence-residue windows, destination
delete read-back, and an independent source-list residue count all passed.

The first Reminder attempt deliberately preserved a real failure rather than
being retried as if it were transient. Reminder-list create and cleanup were
verified, while Reminder create became `partial` with `protocol_failure` before
Rust could record an affected safe item reference. The cause was an exact
cross-language contract mismatch: Swift returned the actual worker
envelopes as `reminders` and `reminder`, while the Rust decoder required
`tasks` and `task` under `deny_unknown_fields`. Rust now maps only the actual
Swift envelope names, and a regression test accepts list, get, and verified
mutation responses while rejecting the obsolete names.

After rebuilding the release CLI, the Reminder v4 path journaled seven
verified mutations: list create, Reminder create, update, complete, reopen,
delete, and list delete. Exact item deletion read-back, destination deletion
read-back, and an independent source-list residue count all passed. The two
post-run destination residue counts were zero. All twelve final v4 journal
rows contained only safe `cal1_`, `ev1_`, `rl1_`, or `rm1_` references; no
native locator, destination title, or item content is recorded here.

Parallel source discovery also reproduced a canonical-store first-open race:
simultaneous CLI processes could read a stale schema version and replay an
already-completed migration, while concurrent fresh-database WAL transitions
could return `BUSY` immediately. Schema discovery and migration now share one
immediate transaction, WAL retries are finite and limited to `BUSY`/`LOCKED`,
and file creation accepts only the independently revalidated `AlreadyExists`
race. Twelve barrier-synchronized storage opens passed deterministically, and
32 release CLI processes then opened one fresh `SHERPA_HOME` with zero
failures.

## 2026-08-05 — Swift EventKit disposable acceptance expansion

The owner-authorized release worker and Swift live verifier returned:

```json
{"status":"verified","suite":"eventkit-disposable-calendar-and-reminder"}
```

The run created two exact disposable Calendars and two exact disposable
Reminder lists, exercised the completed public EventKit Calendar and Reminder
acceptance set, deleted both destinations by their opaque native references,
and independently confirmed their absence from source listings. It did not
select or mutate owner data by title.

The expanded Calendar run reproduced a second future-split defect: a same-time
recurrence-rule update left both the old and replacement occurrence on the
split day. The worker repair now applies to a future split with or without a
time move, but removes an old occurrence only after exact old/new identifiers
and exact starts prove two distinct branches. The corrected release run proved
old history, changed target/later occurrences, future deletion, and no
split-day duplicate. The same run covered single-occurrence title/time/all-day
changes with both neighbors, bounded deterministic reads, one/multi-day
all-day moves, and timed/all-day/daily-recurrence behavior across Los Angeles
spring DST in an explicitly zoned worker process.

The Reminder date expansion exposed that EventKit treats a component set
without hour, minute, and second as all-day. Sherpa's minute-precision payload
had passed hour and minute while leaving second absent, so a fresh due-time
Reminder lost its time. The worker now supplies second `0` when the caller
omits it. The release run then passed separate due-date-only, due-date-time,
start-only, and start-plus-due create/read stages, timed update, explicit
due/start clear, completion/reopen exact filtered membership, and recurring
completion with exact cleanup of the completed and next incomplete
occurrences.

The deterministic Swift gate passed 56 tests and the release suite remained
green after every Event and Reminder data operation gained a full-access
preflight. The owner confirmed that authorization-unavailable validation is
complete for Calendar and Reminders; the verifier does not reset or revoke TCC.
A safe count-only source audit found two read-only Calendars. Calendar
read-only rejection has a deterministic guard and an optional exact-reference
live mode, but the owner decided that a mutation-rejection live run was not an
acceptance requirement; no candidate reference or title was printed or
auto-selected. Read-only destinations are not part of the Reminder acceptance
scope, so the verifier no longer requires a Reminder-list fixture.

At the 2026-08-05 acceptance run, organizer and attendee values were read-only
Event snapshot metadata. No attendee mutation, invitation creation or sending,
or RSVP capability was implemented or claimed. The later product proposal is
tracked separately in
[RFC-0004](../rfc/0004-calendar-invitation-boundary.md).

## 2026-08-01 — Public EventKit v3

The owner explicitly approved Calendar and Reminders access and the two exact
CRUD confirmation phrases. The identity-free local binaries reported full
access for Calendar, Reminders, and the isolated private Reminder helper.

The first live attempt exposed Foundation's `UTC` to `GMT` canonicalization and
a verifier cleanup gap. Both native partial records were recovered. The shared
domain now recognizes only the reviewed UTC-link family, partial create errors
retain their safe Sherpa reference, and recurring Calendar cleanup uses the
future-series span with two occurrence-window residue checks.

The corrected verifier returned `eventkit.live_synthetic_crud.v3`:

| Capability | Create | Update | Additional mutations | Cleanup | Result |
| --- | --- | --- | --- | --- | --- |
| `calendar.crud` | `mut-0aff20nwd8w3f` | `mut-8fh3xdx957nkp` | — | `mut-08cgq7ha6g66q` | supported |
| `reminder.crud` | `mut-4hy9gbxbynfc7` | `mut-chxaptqytfk7v` | complete `mut-0dxprb34s7bwt`; reopen `mut-eb9nj5y8w8yjb` | `mut-cnxp30nwq6fgd` | supported |

An independent post-run query found zero titles with either synthetic verifier
prefix in both selected destinations. The journal contains the full safe
mutation history; this document intentionally omits destination names, native
identifiers, and item content.

After hardening create recovery so the assigned Sherpa reference is persisted
on the still-`started` journal row before read-back, the full release gate and
both owner-approved round trips were run again:

| Capability | Create | Update | Additional mutations | Cleanup | Result |
| --- | --- | --- | --- | --- | --- |
| `calendar.crud` | `mut-6tsd4456zr74y` | `mut-e5rew2g426071` | — | `mut-7yj9xye8pznjk` | supported |
| `reminder.crud` | `mut-6kq9pje0jsqtn` | `mut-7v5hrjdp4vreb` | complete `mut-e29581ghqjv5m`; reopen `mut-dy4pdfavvg1yv` | `mut-1hdy85hy4f0dv` | supported |

All eight new journal rows were independently read back as `verified`. Both
create rows already contained their safe Sherpa target references, and every
later row for that record retained the same reference. A separate bounded
post-run query again found zero Calendar and zero Reminder titles with the
synthetic verifier prefixes.

Private Reminder selectors were available, but all six advanced capabilities
remained disabled at that checkpoint pending their independent owner-approved
write/read-back checks.

## 2026-08-01 — Read-only readiness observations

The rebuilt release binary reported the isolated private Reminder helper at
the current macOS/helper revision with full Reminders access. Selector probes
completed, but tags, sections, hierarchy, flagged state, URL attachments, and
image attachments correctly remained `disabled` with
`private.requires_live_verification`. The disposable tags preview printed its
exact destination and `VERIFY_REMINDER_TAGS_ON_THIS_MAC`, then exited without a
write because no private confirmation had been supplied.

`context doctor` reported the iMessage and KakaoTalk readers ready with source
access still unknown, Mail degraded because its target application was not
running, and the on-device Foundation Models adapter ready. No communication
content was collected. The Supply doctor at that historical checkpoint reported
three markets before any matching live adapters existed; that claim has since
been disproved and is not current evidence. Doctor v2 now advertises only the
Naver capture vertical slice. No marketplace page or persisted browser profile
was opened by the historical readiness check.

These are readiness observations only. They do not replace the owner-operated
private mutations, bounded personal-source collection/model invocation, or
per-market research required by the verification matrix.

Without contacting a communication source, an empty `context status` opened
the real local Context archive. A path-redacted filesystem inspection found a
regular owner-owned database with mode `0600` beneath a non-symlink,
owner-owned directory with mode `0700`. No SQLite journal, WAL, or SHM sidecar
was present after the read-only empty status query. The public status contract
returned an empty array and exposed no content or filesystem path.

The private helper was subsequently advanced to `reminder-private-v2` after
removing an unsafe side effect: `section.assign` now resolves only an existing
section and returns `private.section_not_found` before constructing a save when
the name is absent. The release gate bans the private section-creation selector.
The rebuilt helper compiled and passed the full regression gate, its live probe
reported the v2 environment, and all six capabilities remained disabled as
required. A fresh v2 tags preview again exited without mutation and printed the
same exact owner confirmation phrase.

## 2026-08-01 — Private Reminder tags

The owner then supplied the exact `VERIFY_REMINDER_TAGS_ON_THIS_MAC`
confirmation for the selected disposable Reminder list. The isolated
`reminder-private-v2` helper completed a synthetic create, private tag replace,
private tag read-back, public EventKit read-back, and cleanup round trip on
`Version 26.5.1 (Build 25F80)`.

| Capability | Public create | Private mutation | Public cleanup | Evidence | Result |
| --- | --- | --- | --- | --- | --- |
| `reminder.tags` | `mut-2zbz7ttaz1der` | `mut-bs9qhcsm2sej1` | `mut-9ra2xg66f5z5m` | `private.live_synthetic_round_trip.v1` | supported |

All three journal rows were independently read back as `verified` and retained
the same safe Sherpa target reference. An independent bounded query found zero
remaining synthetic verification reminders. The capability registry now marks
only `reminder.tags` as `supported` for this exact OS/helper environment;
sections, hierarchy, flagged state, URL attachments, and image attachments
remain `disabled` with `private.requires_live_verification`. Destination names,
native identifiers, and item content are intentionally omitted.

## 2026-08-01 — All private Reminder capabilities on v8

The owner granted standing authorization for Sherpa's local live validation,
sensitive-source reads, and synthetic create/read-back/cleanup operations. This
removed repeated conversational approval prompts without weakening the CLI's
explicit write environment and exact-reference confirmation gates.

Testing the remaining private surfaces exposed four real compatibility defects
that deterministic selector-presence tests could not prove:

- the forwarded `flagged` getter returns an integer scalar and crashed when read
  as an Objective-C object;
- private subtask proxies did not provide a reliable title and their completion
  getter was another scalar boundary, so content read-back moved to EventKit;
- image `fileSize`, `width`, and `height` are unsigned scalars and crashed when
  read as objects;
- operation-scoped staging names allowed duplicate image attachments after a
  crash retry, so staging became SHA-512 content-addressed.

The isolated helper contained both native crashes: the Rust CLI and public
EventKit remained available, and the affected journals retained `partial`
status (`mut-eg3sjgdx08fd2`, `mut-1smt15k89x3a1`, and
`mut-8tk7qrpb7yka2`). An empty section list was also corrected from
`Unavailable` to `Absent` only after the full list-section query succeeded with
zero rows. Every incompatible helper change advanced the implementation
revision, preventing stale evidence reuse. The final helper is
`reminder-private-v8` on `Version 26.5.1 (Build 25F80)`.

The final v8 evidence is:

| Capability | Verified mutation evidence |
| --- | --- |
| `reminder.tags` | create `mut-7m7tkmweg262v`; replace `mut-8zgk0q7bfv81a`; cleanup `mut-6120546sfqz7r` |
| `reminder.sections` | create `mut-8ghvq5jzz1xj1`; assign `mut-c13ecxksgszt5`; cleanup `mut-d29cra0ked555` |
| `reminder.flagged` | `mut-2xrzfswk3edsw` |
| `reminder.attachments.url` | `mut-6veqywczgd5h8` |
| `reminder.hierarchy` | `mut-ady5pxkec1nsv` |
| `reminder.attachments.image` | `mut-fxq21vzbw6apb` |

The shared synthetic parent was created by `mut-ehfe7fskr5pnc` and removed by
`mut-avkk52a7jbty3`. All twelve final rows above were independently read back
as `verified`. Replaying the same content-addressed image on the synthetic
parent left the image count unchanged. Parent and subtask references both
returned not found after cleanup, and bounded title queries found zero parent,
subtask, section-verifier, and tags-verifier residues.

The final capability registry reports all six private capabilities as
`supported` for the exact v8 environment. No support is inferred for a future
macOS build or helper revision. Section names, destination names, native
identifiers, and user item content are intentionally omitted.

The complete deterministic `cargo xtask check` passed after the v8 rebuild. A final
post-gate capability query still reported all six as supported, and fresh
bounded residue queries again returned zero for every synthetic title.

## 2026-08-01 — KakaoTalk Context to verified Calendar Event

A bounded one-day KakaoTalk collection archived three messages from two threads.
The source worker remained read-only, the Context archive retained the exact
revisions, and analysis coverage ended with zero pending revisions. No message
was sent and no attachment binary was opened.

Live on-device analysis exposed several boundary defects before a trustworthy
candidate was accepted:

- Rust emits fractional RFC 3339 reference times, so the Swift parser was made
  tolerant of both whole and fractional seconds;
- message timestamps were incorrectly attractive as planning clocks, so timed
  Events now require both clocks in selected message content;
- date-only occurrences and timed Events were split into separate generated
  shapes, with DST-safe local-calendar conversion for all-day ranges;
- copying opaque references or source quotes was unreliable, so the model view
  now uses compact one-based invocation-local handles and restores the exact
  immutable pair only after bounded validation;
- a model-normalized date is no longer authoritative: the mapper resolves a
  unique explicit date from selected content and rejects absent or ambiguous
  temporal evidence;
- one malformed generated proposal no longer discards valid siblings; it is
  omitted with a content-free `analysis.omitted.<rule>` warning.

One inspected date-only occurrence was approved and created through the normal
PlanningCandidate gate. The first mutation (`mut-6m5kgqavgm0cy`) was recorded as
partial because this EventKit store read the inclusive local end back as
`23:59:59`. The adapter now canonicalizes only that exact all-day representation
to the next local midnight. A no-content-change follow-up
(`mut-37stga6p2308v`) completed verified native read-back, and a bounded Event
detail query confirmed the intended half-open one-day range.

After the ordinal-handle and deterministic-date changes, a fresh analysis of
the same immutable revisions returned one correctly grounded all-day Event
candidate for that existing occurrence. Unsupported all-day and timed siblings
were omitted with `all_day_start_evidence` and `event_start_evidence`. The
candidate was deliberately not approved, so no duplicate was created. Earlier
false-positive candidates expired without mutation.

iMessage and Mail remain pending their separate macOS TCC grants; this evidence
does not infer readiness for those sources.

## 2026-08-01 — Archive-free KakaoTalk fresh read

The unsigned release CLI and Context worker ran the new `context read` path
against a bounded KakaoTalk range without opening `ContextStore`. A compact
request emitted three run-scoped records from two run-scoped threads. It exposed
only `E...`, `T...`, and `P...` aliases; no native message, thread, or author
identifier and no message body appeared in compact output.

The request reached a configured native limit. The v1 coverage contract reported
`partial_limit`, `matched=3/lower_bound`, and `remaining=?/unknown`; it did not
claim completeness. A second one-record inventory request returned an empty
public item array with the same conservative limit state.

The Context SQLite modification time and byte size were captured immediately
before and after the second native read and were identical. No Calendar,
Reminder, message, or mail mutation was attempted. This proves the first
archive-free live read boundary only; checkpoint, overlap, specialist routing,
and Planner reconciliation remain separate migration gates.

## Related

- [Owner-operated live validation](live-validation.md)
- [Requirement verification matrix](verification-matrix.md)
- [Test strategy](README.md)
- [Native fresh-read ADR](../adr/0004-native-fresh-read-context.md)
- [Archive migration RFC](../rfc/0001-context-archive-to-fresh-read.md)
