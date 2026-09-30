#!/usr/bin/env bash
# 릴리스 경로 전체를 실제로 돌려 본다 — 패키징, Formula 렌더, Homebrew 설치, brew test.
#
# 이 검사가 없던 동안 Formula 의 test 블록은 한 번도 통과한 적이 없었다. 없는 명령
# (`supply doctor`)을 검증하고, 워커에 Protocol V1 봉투를 보내고 있었다. 아무도 돌리지
# 않는 검증은 검증이 아니다.
#
# 설치된 sherpa 는 건드리지 않는다. 별도 이름(sherpa-smoke)과 임시 tap 을 쓰고 끝나면
# 둘 다 지운다.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly REPO_ROOT
readonly SMOKE_TAP="xiyo/sherpa-smoke-$$"
readonly SMOKE_FORMULA="sherpa-smoke-$$"
readonly LOG_SCOPE="check:release"

log() { printf '%s [%s:%s] %s\n' "$1" "$LOG_SCOPE" "$2" "$3" >&2; }
fail() { log error "$1" "$2"; exit 1; }

# The fixture never enters the shared bin directory. Homebrew documents
# install --skip-link and test --force for unlinked formulae.
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_FROM_API=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
export HOMEBREW_NO_INSTALL_UPGRADE=1

cleanup() {
  local code=$?
  if [ "${SMOKE_INSTALLED:-0}" = "1" ]; then
    brew uninstall --formula --force "$SMOKE_TAP/$SMOKE_FORMULA" >/dev/null 2>&1 \
      || { log error cleanup "reason=smoke_uninstall_failed"; code=1; }
  fi
  if [ "${SMOKE_TAP_CREATED:-0}" = "1" ]; then
    brew untap "$SMOKE_TAP" >/dev/null 2>&1 \
      || { log error cleanup "reason=smoke_untap_failed"; code=1; }
  fi
  [ -z "${SMOKE_DIST:-}" ] || rm -rf "$SMOKE_DIST"
  [ "$code" -eq 0 ] && log info success "smoke install and test passed" \
                    || log error failure "exit=$code"
  exit "$code"
}

SMOKE_INSTALLED=0
SMOKE_TAP_CREATED=0
command -v brew >/dev/null 2>&1 || fail failure "reason=brew_missing"

log info start "packaging and smoke-installing the release"

# 1. 릴리스를 실제로 만든다. 단 임시 위치에 만든다 — 검사가 릴리스 산출물을 덮어쓰면
#    tap 의 Formula 가 가리키는 해시와 어긋나 재설치가 깨진다.
SMOKE_DIST="$(mktemp -d "${TMPDIR:-/tmp}/sherpa-smoke-dist.XXXXXX")"
readonly SMOKE_DIST
trap cleanup EXIT
SHERPA_DIST="$SMOKE_DIST" bash "$REPO_ROOT/scripts/package.sh" >/dev/null \
  || fail failure "reason=packaging_failed"

rendered="$SMOKE_DIST/local-tap/Formula/sherpa.rb"
[ -f "$rendered" ] || fail failure "reason=formula_not_rendered"

# 스모크는 file:// 판을 설치한다. 배포본은 아직 올리지 않은 릴리스 자산을 가리키기 때문이다.
# 둘이 url 한 줄만 달라야 이 스모크가 배포본에 대한 검증이 된다.
published="$SMOKE_DIST/Formula/sherpa.rb"
[ -f "$published" ] || fail failure "reason=published_formula_not_rendered"
diff <(grep -v '^  url "' "$rendered") <(grep -v '^  url "' "$published") >/dev/null \
  || fail failure "reason=formulas_differ_beyond_url"
grep -Eq '^  url "https://github\.com/XIYO/sherpa/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/sherpa-[0-9]+\.[0-9]+\.[0-9]+-aarch64-apple-darwin\.tar\.gz"$' "$published" \
  || fail failure "reason=published_url_unexpected"

# A fresh tap and formula name isolates concurrent checks and existing installs.
[ ! -d "$(brew --repository "$SMOKE_TAP")" ] \
  || fail failure "reason=smoke_tap_exists"
brew tap-new --no-git "$SMOKE_TAP" >/dev/null 2>&1 \
  || fail failure "reason=smoke_tap_not_created"
SMOKE_TAP_CREATED=1
smoke_root="$(brew --repository "$SMOKE_TAP")"
mkdir -p "$smoke_root/Formula"
sed "s/^class Sherpa < Formula$/class SherpaSmoke$$ < Formula/" "$rendered" \
  > "$smoke_root/Formula/$SMOKE_FORMULA.rb"

# Mark ownership before install so a partial installation is cleaned too.
SMOKE_INSTALLED=1
brew install --formula --skip-link "$SMOKE_TAP/$SMOKE_FORMULA" > "$SMOKE_DIST/install.log" 2>&1 \
  || fail failure "reason=smoke_install_failed"
brew test --force "$SMOKE_TAP/$SMOKE_FORMULA" > "$SMOKE_DIST/test.log" 2>&1 \
  || fail failure "reason=smoke_test_failed"

# 4. 설치본이 실제로 이 릴리스인지, 그리고 딴것이 섞이지 않았는지 확인한다.
prefix="$(brew --prefix "$SMOKE_FORMULA")"
installed_version="$("$prefix/bin/sherpa" --version | awk '{print $2}')"
expected_version="$(grep -m1 '^  version "' "$rendered" | sed 's/.*"\(.*\)".*/\1/')"
[ "$installed_version" = "$expected_version" ] \
  || fail failure "reason=version_mismatch installed=$installed_version formula=$expected_version"

stray="$(find "$prefix" -type f -not -name sherpa -not -path '*/.brew/*' | head -3 | tr '\n' ' ')"
[ -z "$stray" ] || fail failure "reason=unexpected_files_installed files=$stray"

log info verified "version=$installed_version tap=$SMOKE_TAP"
