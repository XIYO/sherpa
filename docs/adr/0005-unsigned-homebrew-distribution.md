---
uuid: 01a0f253-5272-733e-9641-f6db1066bf6b
type: adr
audience: "Maintainers revisiting how the Sherpa CLI reaches a Mac and why it is unsigned"
goal: "Know why Homebrew without Developer ID is the installer and what a release must keep"
tone: "Decision record English, with dated Korean notes where the context has since changed"
manner: "Keep the decision; state changed facts in the dated note and point to the runbook for steps"
---

# ADR-0005: Unsigned Homebrew Distribution with Explicit Agent Installation

> **결정은 유효하나 맥락이 낡았다 (2026-08-27).** 서명·공증 없이 Homebrew 로 배포한다는
> 결정은 그대로다. 다만 본문이 말하는 구성은 바뀌었다 — Rust 와 Python 워커는 사라졌고
> 릴리스는 Swift 실행 파일 하나다. `cargo xtask package` 는 `scripts/package.sh` 가
> 대신한다. 현재 절차는 [릴리스 런북](../testing/local-homebrew-release.md)에 있다.
>
> **배포 경로를 고쳤다 (2026-09-30).** 저장소를 공개하면서 설치 정본은 공개 tap
> `XIYO/homebrew-tap` 의 `xiyo/tap/sherpa` 이고, Formula 의 url 은 공개 `XIYO/sherpa` 의
> 릴리스 자산이다. 같은 기기의 로컬 tap 과 `file://` 아카이브는 개발용으로만 남는다.
> Decision 의 카탈로그 문단은 이 사실로 바꿔 적었다.

## Context

Sherpa is a standalone CLI with Rust, Swift, Objective-C, and Python workers.
Copying a development virtual environment produces absolute interpreter paths,
while requiring every user to install Rust turns a product installation into a
source build. Codex and Claude Code plugin registration also changes per-user
host configuration and is not part of installing program files.

The intended audience chooses to run Sherpa and does not require an Apple
verified-developer title. A paid Developer ID and notarization add recurring
cost and release ceremony without improving Sherpa's local deterministic
contracts.

## Decision

Homebrew is the only system-level prerequisite and the canonical installer.
The `xiyo/tap/sherpa` Formula installs a versioned, checksum-pinned release
archive and declares Homebrew `uv` and `python@3.14` dependencies. Users never
need Rust, Cargo, or Xcode for a normal installation.

The Formula catalog and release payload are separate distribution objects. The
catalog is the public `XIYO/homebrew-tap` repository (`xiyo/tap`), and the
Formula's checksum-pinned URL names the release asset of the public
`XIYO/sherpa` repository. For development on one machine, a local tap may carry
the same generated Formula pointing at a checksum-pinned `file://` archive; it
is a development convenience, not a distribution route. Publishing the
generated Formula into a tap updates Homebrew's catalog, while `brew install` or
`brew upgrade` remains the only program-installation action.

The archive is relocatable. Native executables live in one private runtime
directory. The Python project, lock, hash-bearing requirements export, and
platform wheelhouse are shipped as data; the Formula creates a new environment
at the final installation path with network access disabled. Environment
creation runs idempotently in `post_install`, after Homebrew's native linkage
relocation, so third-party Python extension modules are not rewritten by
Homebrew. No `.venv` is copied from the build machine.

Developer ID, Team ID, hardened-runtime signing, notarization, Apple developer
membership, and App Store distribution are permanently outside the product
plan. The build keeps only identity-free ad-hoc signatures required by macOS.
The resulting possibility of renewed privacy prompts after an upgrade is an
accepted product constraint.

Formula installation does not mutate an agent host's user configuration. After
installation, `sherpa agent status` is read-only; `sherpa agent install`,
`update`, and `remove` perform explicit, verified Codex or Claude Code plugin
operations. The release carries an exact-version local marketplace, which
Sherpa promotes to an owner-controlled stable path before invoking the host's
native plugin CLI. Host integration remains replaceable and is isolated in an
adapter crate.

## Consequences

- Release automation owns a complete archive, manifest, Formula renderer, and
  clean-prefix smoke test.
- A local owner release regenerates and synchronizes the complete Formula; it
  never hand-edits version, URL, or checksum fields in the installed tap.
- Homebrew can patch `uv` and Python independently while Sherpa pins its Python
  application dependency graph and wheel hashes.
- A release is target-specific because compiled Python wheels and native
  binaries are target-specific.
- A shipped agent plugin has the same version as its Sherpa CLI. The installer
  reports compatibility explicitly and refuses a same-name marketplace owned
  by a different source instead of silently replacing it.
- macOS privacy permissions may need owner reauthorization after upgrade.

## Rejected alternatives

- **Copy the development `.venv`:** embeds build-machine interpreter paths and
  is not relocatable.
- **Install with Cargo:** exposes a compiler toolchain and omits native and
  Python runtime assets.
- **Download Python packages on first use:** moves installation failure into a
  user operation and weakens release reproducibility.
- **Mutate agent configuration from Formula `post_install`:** unlike the
  isolated Python runtime creation, host registration does not know the
  intended host and cannot provide reliable rollback.
- **Developer ID and notarization:** impose a permanent paid release dependency
  that the product owner explicitly rejects.

## Related

- [Distribution requirements](../requirements/distribution.md)
- [System architecture](../architecture/README.md)
- [Roadmap](../roadmap/README.md)
- [Worker isolation decision](0001-control-plane-and-workers.md)
- [Test strategy](../testing/README.md)
- [Homebrew release runbook](../testing/local-homebrew-release.md)
- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [Homebrew Tap Trust](https://docs.brew.sh/Tap-Trust)
- [uv command reference](https://docs.astral.sh/uv/reference/cli/)
