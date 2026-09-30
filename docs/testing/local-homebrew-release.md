---
uuid: 01a0f254-3833-7686-b189-fc627ecfcd6d
type: guide
audience: "The maintainer releasing a Sherpa CLI version or installing a development build on one Mac"
goal: "Publish a version to the public tap, or install a local build, without a version or checksum split"
tone: "Imperative English. Each step says what must hold before the next one"
manner: "Commands in order; the reasons live in ADR-0005 and the requirements in distribution.md"
---

# Homebrew Release and Upgrade Runbook

## Purpose

Use this flow to release Sherpa through the public Homebrew tap and to upgrade
an installed copy. Homebrew owns installation and upgrade; the maintainer only
publishes the release archive and the generated Formula.

Users install with:

```bash
brew install xiyo/tap/sherpa
```

## Model

Keep these objects distinct:

1. `bash scripts/package.sh` creates a versioned, checksum-pinned release
   archive, `target/dist/sherpa-<version>-aarch64-apple-darwin.tar.gz`.
2. It renders two Formulas from one template. They differ only in the `url`
   line:
   - `target/dist/Formula/sherpa.rb` names the archive as the release asset of
     the public `XIYO/sherpa` repository for tag `v<version>`. It is the file
     the public tap `XIYO/homebrew-tap` carries as `Formula/sherpa.rb`.
   - `target/dist/local-tap/Formula/sherpa.rb` names the archive through a
     `file://` URL, so it installs before anything is published. The release
     smoke and a local development tap use it.
3. `brew install` or `brew upgrade` installs the version advertised by the
   Formula in the tap.

Homebrew does not inspect source changes to discover a newer version. A new
release must bump the canonical version and publish the regenerated Formula
before `brew upgrade` can detect it.

The canonical version is the string `main.swift` prints for `--version`; the
help banner and both `Info.plist` files carry the same value.
`scripts/package.sh` reads it back from the built binary and refuses to package
anything whose output does not match `sherpa X.Y.Z`, because the plugin's
version guard parses exactly that shape.

### The gate never touches the release artifacts

`scripts/check-release.sh` packages into a temporary directory (`SHERPA_DIST`),
not into `target/dist`. The Swift build is not reproducible — the same source
yields a different archive checksum on every run — so a check that repackaged in
place would leave a Formula pinning a checksum no archive has, and the next
`brew reinstall` would fail on a hash mismatch. Running the gate any number of
times leaves the published archive and the tap in agreement.

Only `scripts/package.sh` writes `target/dist`, and only when you run it
yourself. For the same reason, publish the Formula from the same run that
uploaded the archive; a Formula from any other run pins a different checksum.

## Release

1. Increment the canonical version in `main.swift` and both `Info.plist` files.
   The repository gate checks it against the plugin's `cli-contract.json`.
2. Run the whole gate on macOS and confirm it exits 0:

   ```bash
   bash scripts/check-all.sh
   ```

3. Tag the release commit `v<version>`, push the tag, and create the GitHub
   release for that tag on `XIYO/sherpa`. `scripts/package.sh --publish` stops
   with `release_tag_missing` when the release does not exist.
4. Package, upload, and read back:

   ```bash
   bash scripts/package.sh --publish
   ```

   It uploads the archive as the release asset, downloads that asset again,
   and stops with `asset_checksum_mismatch` unless its SHA-256 equals the one
   pinned in both Formulas.
5. Publish the Formula into a clone of `XIYO/homebrew-tap`:

   ```bash
   tap_clone=<path to a clone of XIYO/homebrew-tap>
   git -C "$tap_clone" pull --ff-only
   git -C "$tap_clone" status --short
   cp target/dist/Formula/sherpa.rb "$tap_clone/Formula/sherpa.rb"
   cmp target/dist/Formula/sherpa.rb "$tap_clone/Formula/sherpa.rb"
   git -C "$tap_clone" diff -- Formula/sherpa.rb
   git -C "$tap_clone" add Formula/sherpa.rb
   git -C "$tap_clone" commit -m "sherpa <version>"
   git -C "$tap_clone" push
   ```

   The status command must print nothing; stop and inspect any pre-existing
   change instead of overwriting it. The diff must change only `url`,
   `version`, and `sha256`, unless the Formula template itself changed.
6. Let Homebrew perform the upgrade:

   ```bash
   brew update
   brew upgrade xiyo/tap/sherpa
   ```

Do not hand-edit `version`, `url`, or `sha256` in the tap. The packager derives
them together; copying the complete generated file prevents a
version/archive/checksum split.

## Verification

Verify the installed keg, Formula test, dynamic linkage, and CLI version:

```bash
brew info --formula xiyo/tap/sherpa
brew test xiyo/tap/sherpa
brew linkage --test xiyo/tap/sherpa
sherpa --version
```

The reported CLI and installed Formula versions must equal the release version.
The Formula URL must name the release asset for that same version, and its
SHA-256 must match the asset.

The release smoke installs a uniquely named temporary Formula with `brew install --skip-link`
and tests it with `brew test --force`. It never replaces the installed Sherpa links.
Automatic cleanup and dependent upgrades are disabled; cleanup failures fail the gate.
The smoke uses a clean installation and does not exercise an existing owner database. After the real upgrade, run one small, ordinary, bounded
installed-binary request against the existing owner state. A migration change
is complete only when a regression begins at the already-applied prior
`user_version` and the installed binary upgrades a representative existing
database; fresh initialization alone is insufficient evidence.

Homebrew upgrades the CLI only. The agent skills reach a machine through each
host's plugin command and are not touched by a Formula. If a release raises the
CLI version the skills need, raise `minimumVersion` in the plugin's
`cli-contract.json` in the same change, as its `note` describes.

## Development installs

To install an unreleased build on one Mac, publish the local Formula into a
local tap. The tap has no remote and is not a distribution route.

Create the tap once:

```bash
brew tap-new xiyo/sherpa-dev
```

Package the checkout, copy the local Formula as a whole, trust it, and install:

```bash
bash scripts/package.sh
tap_root="$(brew --repository xiyo/sherpa-dev)"
mkdir -p "$tap_root/Formula"
cp target/dist/local-tap/Formula/sherpa.rb "$tap_root/Formula/sherpa.rb"
brew trust --formula xiyo/sherpa-dev/sherpa
brew install xiyo/sherpa-dev/sherpa
```

Only one tap's `sherpa` can be installed at a time. Switch between the
development build and the release with `brew uninstall sherpa` followed by the
other tap's `brew install`. A Mac that still installs from an older local tap
switches the same way and can then remove that tap with `brew untap`.

`brew update` changes nothing for a local tap; `brew upgrade` reads its working
tree directly. The `file://` archive must stay in `target/dist` for as long as
the development install may be reinstalled.

## Same-version rebuilds

`brew upgrade` compares Formula versions. If source code changed but the
version did not, the correct release action is to increment the version and
regenerate the package. Use a same-version rebuild only for a local diagnostic
install from the development tap:

```bash
brew reinstall xiyo/sherpa-dev/sherpa
```

Never publish two distinct release payloads under one version.

## Failure interpretation

- `brew upgrade` reports the installed version as current: the canonical
  version was not incremented, or the regenerated Formula was not pushed to
  `XIYO/homebrew-tap`, or `brew update` has not fetched it yet.
- The Formula still names an older archive: rerun `bash scripts/package.sh
  --publish` after the version bump and copy the generated file again; do not
  patch fields by hand.
- Download fails with a checksum mismatch: the Formula came from a different
  packaging run than the uploaded asset. Rerun `--publish` and copy that run's
  `target/dist/Formula/sherpa.rb`.
- `release_tag_missing`: create the GitHub release for `v<version>` first.

## Related

- [Unsigned Homebrew distribution decision](../adr/0005-unsigned-homebrew-distribution.md)
- [Distribution requirements](../requirements/distribution.md)
- [Test strategy](README.md)
- [System architecture](../architecture/README.md)
- [Project overview](../../README.md)
