#!/usr/bin/env bash
# 스킬이 Sherpa CLI 명령을 호출하기 전에 한 번 실행한다.
#
# 플러그인과 CLI 는 한 저장소에 있지만 설치 경로가 다르다 — 스킬은 plugin install 로,
# CLI 는 brew 로 들어온다. 사용자 머신에서 두 버전이 어긋날 수 있다.
# 버전을 서로 같게 강제할 수 없으므로 한 방향 제약만 검사한다 —
# 설치된 CLI 가 cli-contract.json 의 minimumVersion 이상이고 MAJOR 가 같은가.
#
# stdout 은 스킬이 읽는 JSON 한 줄이다. 진단 로그는 stderr 로만 보낸다.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly CONTRACT="${SCRIPT_DIR}/../cli-contract.json"
readonly LOG_SCOPE="plugin:sherpa:require-cli"

log() {
  local level="$1" message="$2"
  case "${LOG_LEVEL:-warn}" in
    debug) : ;;
    info) [ "$level" = debug ] && return 0 ;;
    error) [ "$level" != error ] && return 0 ;;
    *) { [ "$level" = debug ] || [ "$level" = info ]; } && return 0 ;;
  esac
  printf '%s [%s:%s] %s\n' "$level" "$LOG_SCOPE" "${3:-check}" "$message" >&2
}

# CLI 는 macOS 전용이다(EventKit·Mail.app·iMessage). 다른 플랫폼에서는 버전을 볼 것도 없이
# 여기서 끝낸다 — "없음"으로 답하면 그 기기에서 실행할 수 없는 brew 명령을 권하게 된다.
# 플랫폼을 읽지 못한 것은 unsupported 가 아니라 failed 다. 훅이 unsupported 에는 침묵하므로,
# 모르는 것을 그쪽으로 보내면 macOS 에서의 고장이 조용해진다.
platform="$(uname -s 2>/dev/null)" || platform=""
platform="$(printf '%s' "$platform" | tr -cd 'A-Za-z0-9._-')"
if [ -z "$platform" ]; then
  log error "uname -s failed; cannot tell whether this is macOS" start
  printf '{"status":"failed","error":"platform_probe_failed"}\n'
  exit 1
fi
if [ "$platform" != "Darwin" ]; then
  log warn "platform=${platform}; the Sherpa CLI runs only on macOS" failure
  printf '{"status":"unsupported","reason":"macos_only","platform":"%s","remedy":"%s"}\n' \
    "$platform" "none on this device: the Sherpa CLI runs only on macOS, so use these skills on a Mac"
  exit 1
fi

# jq 없이 읽는다. 값이 단순 문자열이라 이 정도로 충분하고, 형식이 깨지면 아래에서 빈 값으로 걸린다.
json_string() {
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$CONTRACT" | head -1
}

if [ ! -f "$CONTRACT" ]; then
  log error "cli-contract.json not found at ${CONTRACT}" start
  printf '{"status":"failed","error":"contract_missing"}\n'
  exit 1
fi

readonly COMMAND="$(json_string command)"
readonly MINIMUM="$(json_string minimumVersion)"
readonly INSTALL="$(json_string install)"

if [ -z "$COMMAND" ] || [ -z "$MINIMUM" ]; then
  log error "contract is missing command or minimumVersion" start
  printf '{"status":"failed","error":"contract_invalid"}\n'
  exit 1
fi

log debug "checking ${COMMAND} against minimum ${MINIMUM}" start

if ! command -v "$COMMAND" >/dev/null 2>&1; then
  log warn "${COMMAND} is not on PATH; install with: ${INSTALL}" failure
  printf '{"status":"missing","command":"%s","minimum":"%s","install":"%s"}\n' \
    "$COMMAND" "$MINIMUM" "$INSTALL"
  exit 1
fi

raw_version="$("$COMMAND" --version 2>&1 | head -1)" || {
  log error "${COMMAND} --version failed" failure
  printf '{"status":"failed","error":"version_probe_failed"}\n'
  exit 1
}

installed="$(printf '%s' "$raw_version" | sed -n 's/^sherpa \([0-9]\{1,\}\.[0-9]\{1,\}\.[0-9]\{1,\}\)$/\1/p')"
if [ -z "$installed" ]; then
  log error "unexpected --version output: ${raw_version}" failure
  printf '{"status":"failed","error":"version_unparsable","output":"%s"}\n' "$raw_version"
  exit 1
fi

split() { printf '%s' "$1" | tr '.' ' '; }
read -r i_major i_minor i_patch <<<"$(split "$installed")"
read -r m_major m_minor m_patch <<<"$(split "$MINIMUM")"

# CLI 가 낡았는지 너무 새것인지에 따라 고쳐야 할 쪽이 다르다. 한쪽 안내만 내보내면
# 사용자를 반대 방향으로 보낸다 — 1.0.0 을 쓰는 사람에게 brew install 을 시키는 식으로.
mismatch() {
  local direction="$1" remedy
  if [ "$direction" = "cli_too_old" ]; then
    remedy="$INSTALL"
  else
    remedy="update this plugin (its skills expect an older CLI)"
  fi
  log warn "installed=${installed} does not satisfy minimum=${MINIMUM} (${direction}); remedy: ${remedy}" failure
  printf '{"status":"mismatch","reason":"%s","installed":"%s","minimum":"%s","remedy":"%s"}\n' \
    "$direction" "$installed" "$MINIMUM" "$remedy"
  exit 1
}

if [ "$i_major" -ne "$m_major" ]; then
  [ "$i_major" -lt "$m_major" ] && mismatch cli_too_old || mismatch cli_too_new
fi
[ "$i_minor" -lt "$m_minor" ] && mismatch cli_too_old
[ "$i_minor" -eq "$m_minor" ] && [ "$i_patch" -lt "$m_patch" ] && mismatch cli_too_old

log info "installed=${installed} minimum=${MINIMUM}" success
printf '{"status":"ready","installed":"%s","minimum":"%s"}\n' "$installed" "$MINIMUM"
