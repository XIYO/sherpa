---
uuid: 01a0f253-1e8d-7354-bb91-5bfbde9f6a59
type: spec
audience: "Maintainers changing how the Sherpa CLI is packaged, published, or installed"
goal: "Check a packaging or install change against the numbered functional and safety requirements"
tone: "Normative English. One requirement per identifier, stated as must or never"
manner: "Requirements only; the release steps live in the runbook and the rationale in ADR-0005"
---

# Homebrew Distribution and Agent Integration Requirements

## Outcome

A macOS user who already has Homebrew must be able to install a complete,
relocatable Sherpa executable without Xcode, an Apple developer
account, or a paid signing identity. Agent integration is a separate explicit
Sherpa operation after the CLI is installed.

## Functional requirements

- `FR-DP-001`: `brew install xiyo/tap/sherpa` is the canonical product install.
  The Formula declares no runtime dependency and installs no toolchain. The tap
  is the public `XIYO/homebrew-tap` repository, and the Formula's
  checksum-pinned URL names the release asset of the public `XIYO/sherpa`
  repository for that version. For development on one machine, the same
  generated Formula may be rendered against a checksum-pinned `file://` archive
  and published into a local tap; that tap is a development convenience, not a
  distribution route.
- `FR-DP-002`: The release archive contains the Sherpa CLI, every required
  executable and nothing else. It contains no agent skills and no worker
  runtime. Every executable and installer
  resource resolves relative to the installed runtime and never depends on a
  source checkout or developer-machine path.
- `FR-DP-003`: The Formula installs the executable directly and needs no
  `post_install` step,
  after Homebrew has relocated the archive's native files. Runtime packages
  are installed offline from release-contained wheels selected by a
  hash-bearing export of `uv.lock`; a copied virtual environment is never a
  distribution artifact.
- `FR-DP-004`: The archive carries exactly one file, the executable, and the
  packager refuses to build one that carries anything else. The generated
  Formula pins the archive SHA-256, and the version it declares is read back
  from the built binary rather than written by hand.
- `FR-DP-005`: The CLI does not register, update, or remove agent plugins on
  any host. This repository publishes its own plugin marketplace at
  `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`, and
  skills are installed with each host's own plugin command. The archive and the
  marketplace are separate delivery routes, so the plugin declares the minimum
  CLI version its skills require and each skill verifies it before its first
  command rather than requiring an exact CLI/plugin version pair.
- `FR-DP-006`: Homebrew owns installed program files and worker environments.
  Upgrade and uninstall do not silently purge Sherpa's owner data, browser
  profile, Apple data, or host plugin registrations.

## Safety requirements

- `SR-DP-001`: Sherpa permanently requires no Developer ID, Team ID, paid Apple
  developer membership, notarization, or hardened-runtime distribution flow.
  Identity-free ad-hoc Mach-O signatures may satisfy the operating system, and
  an upgrade may require the owner to grant macOS privacy permissions again.
- `SR-DP-002`: Formula installation never changes Codex or Claude Code user
  configuration in `post_install`. Agent integration requires a separate,
  visible Sherpa command after the CLI installation succeeds.
- `SR-DP-003`: Packaging and installer boundaries log safe action, state,
  duration, byte-count, and failure-class fields only. They never log command
  arguments, paths, host output, cookies, tokens, user content, or environment
  values.
- `SR-DP-004`: A deterministic packaging test must install from the generated
  archive into a clean temporary prefix, verify it holds the executable and
  nothing else, and invoke it with
  network access disabled, invoke every worker capability, and reject absolute
  source paths or copied virtual-environment launchers.

## Non-goals

- Installing Homebrew itself.
- Installing or managing Codex or Claude Code.
- Automatically registering an agent plugin during `brew install`.
- Paid Apple distribution identity, notarization, App Store distribution, or a
  marketing claim that Sherpa is an Apple-verified developer product.
- Purging owner data as a side effect of `brew uninstall`.

## Acceptance

The deterministic gate must build one release archive, validate its manifest,
render and audit a Formula, perform a clean-prefix offline runtime install, and
exercise the packaged CLI and worker capability paths. The archive must contain
no agent marketplace; the skill side is gated separately by the plugin check.

## Related

- [System architecture](../architecture/README.md)
- [Roadmap](../roadmap/README.md)
- [Unsigned Homebrew decision](../adr/0005-unsigned-homebrew-distribution.md)
- [Test strategy](../testing/README.md)
- [Homebrew release runbook](../testing/local-homebrew-release.md)
- [Requirement verification matrix](../testing/verification-matrix.md)
