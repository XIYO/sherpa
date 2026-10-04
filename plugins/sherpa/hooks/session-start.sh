#!/usr/bin/env bash
# 세션 시작 때 CLI 계약을 검사한다. 판정은 require-cli.sh 한 곳이 맡는다.
# 가드는 정해진 순서의 한 줄 JSON을 내므로 여기서는 상태와 안전한 표시 값만 읽는다.
# 정상과 지원하지 않는 OS에서는 침묵하고 어떤 경우에도 세션을 실패시키지 않는다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly GUARD="${SCRIPT_DIR}/../scripts/require-cli.sh"

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$1"
}

if [ ! -f "$GUARD" ]; then
  emit "Sherpa 플러그인의 CLI 가드(require-cli.sh)를 찾을 수 없습니다. 플러그인을 다시 설치해야 합니다."
  exit 0
fi

status_json="$(bash "$GUARD" 2>/dev/null)" || true
case "$status_json" in
  '{"status":"ready"'*|'{"status":"unsupported"'*)
    ;;
  '{"status":"missing"'*)
    install="${status_json#*\"install\":\"}"
    install="${install%%\"*}"
    if [[ "$install" =~ ^[A-Za-z0-9_./\ -]+$ ]]; then
      emit "Sherpa CLI가 설치되어 있지 않습니다. 설치: ${install}"
    else
      emit "Sherpa CLI가 설치되어 있지 않습니다. Sherpa 스킬의 설치 안내를 확인하세요."
    fi
    ;;
  '{"status":"mismatch"'*)
    installed="${status_json#*\"installed\":\"}"
    installed="${installed%%\"*}"
    if [[ ! "$installed" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then installed="알 수 없음"; fi
    case "$status_json" in
      *'"reason":"cli_too_new"'*)
        emit "Sherpa CLI 버전이 이 플러그인의 계약과 어긋납니다(설치됨 ${installed}). 조치: update this plugin"
        ;;
      *)
        install="${status_json#*\"remedy\":\"}"
        install="${install%%\"*}"
        if [[ "$install" =~ ^[A-Za-z0-9_./\ -]+$ ]]; then
          emit "Sherpa CLI 버전이 이 플러그인의 계약과 어긋납니다(설치됨 ${installed}). 조치: ${install}"
        else
          emit "Sherpa CLI 버전이 이 플러그인의 계약과 어긋납니다(설치됨 ${installed}). Sherpa 스킬의 갱신 안내를 확인하세요."
        fi
        ;;
    esac
    ;;
  *)
    emit "Sherpa CLI 확인에 실패했습니다. Sherpa 스킬을 쓰기 전에 sherpa --version 을 직접 확인하세요."
    ;;
esac

exit 0
