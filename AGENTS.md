---
uuid: 01a0ed87-17c8-729c-8473-05d2e83ddf73
type: instructions
audience: "이 저장소에서 작업하는 에이전트. 변경·검증·병합 전에 규칙을 확인할 때"
goal: "어디서 상태를 읽고, 사실이 바뀌면 무엇을 함께 고치며, 어떻게 검증하고 병합하는지 따르게 한다"
tone: "명령형 영어. 규칙마다 이유를 한 문장으로 단다"
manner: "규칙만 적고 근거는 ADR·live-evidence·스크립트 주석으로 내린다"
---

# Sherpa repository instructions

- Publish the agent plugin only through `XIYO/plug-hole` as `sherpa@plug-hole`.
  Keep its source and releases here without a repository marketplace.
- This file is the single body of the repository instructions. `CLAUDE.md` holds
  only the `@AGENTS.md` import so that Claude Code sessions load the same text;
  add rules here, never there. It is an import rather than a symbolic link
  because Git checks a committed link out as a plain one-line file in any clone
  where `core.symlinks` is false, and that value is fixed per clone on Windows.
- Read `docs/architecture/README.md` and the matching document under
  `docs/contracts/` before changing a worker boundary, canonical reference,
  domain model, or SQLite storage.
- Unfinished work that must pass to another session lives in one root
  `RESUME.md`: its goal, the owner's decisions, what is true now, what is not
  yet proven, and the next step. Read it only when resuming that work, rewrite
  its state instead of appending, and delete it when the work is done, because
  a stale handoff reads as current truth. Do not create `.handoff/` or files
  per topic. Historical probes and old code are not authority.
- When deterministic or owner-operated evidence changes a fact, update the
  matching architecture or contract document, the implementation, the lint
  rule, the relevant tests, and `RESUME.md` if it carries that work, in the
  same completed change. Replace disproved guidance and record an unresolved
  fact, marked unverified, in `RESUME.md`; do not rely on chat memory.
- Classify every reproduced discovery before continuing dependent work: current
  behavior replaces the matching fact in the architecture, contract, or README
  text, an open uncertainty enters `RESUME.md`, and a
  corrected or rejected path moves to the dated `docs/testing/live-evidence.md`
  history. Do not leave a reproduced observation only in chat, a terminal
  transcript, or a code comment, and do not duplicate stale current truth in
  the chronological log.
- The CLI and the plugin carry independent versions. The CLI version lives in
  `main.swift` (`--version` and the help banner) and both `Info.plist` files;
  its tag is `v<version>`, which `scripts/package.sh --publish` requires. The
  plugin version lives in both plugin manifests and `plugins/sherpa/CHANGELOG.md`
  and gets no tag. Bump it whenever `plugins/sherpa/` changes, because Claude
  Code compares only that version. `minimumVersion` in `cli-contract.json`
  follows the rule in its own `note`.
- CI runs only the Windows hook check (`plugins/sherpa/scripts/check-windows.ps1`
  on a GitHub-hosted `windows-latest` runner). The macOS gate — the three Swift packages'
  build and tests, the manifest, contract, and document checks, and the release
  smoke install — does not run in CI. Before merging any pull request, run
  `bash scripts/check-all.sh` on macOS after the last change, confirm the whole
  run exits 0, and write that result in the pull request body. Merge by hand
  only after the Windows job has actually passed; never use
  `gh pr merge --auto`, and never merge while the pull request shows no checks.
  No ruleset requires the check, so `--auto` would merge at once.
- When pull requests are stacked, retarget the upper one's base to `main`
  before merging the lower one with `--delete-branch`. GitHub closes a pull
  request whose base branch is deleted, and a closed pull request cannot change
  its base.
- Pair every reproduced defect with a deterministic regression or an explicit
  owner-operated live-evidence requirement. If the proof is still unavailable,
  keep that missing proof visible as incomplete work rather than calling the
  path complete.
