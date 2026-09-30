#!/usr/bin/env bash
# 세션이 시작될 때 Sherpa CLI 가 이 플러그인의 계약을 만족하는지 한 번 확인한다.
#
# 스킬의 require-cli.sh 가드는 스킬을 부를 때 돈다. 그래서 사용자는 일을 시키고
# 나서야 CLI 가 없거나 낡았다는 것을 알게 된다. 같은 가드를 세션 첫머리에 돌려
# 그 시점을 앞당긴다. 판정 자체는 가드 하나에만 있고 여기서 다시 계산하지 않는다.
#
# 제약 둘. 정상이면 아무 말도 하지 않는다 — 매 세션 같은 문장을 읽히지 않는다.
# 그리고 무슨 일이 있어도 세션을 실패시키지 않는다. 그래서 항상 0 으로 끝난다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly GUARD="${SCRIPT_DIR}/../scripts/require-cli.sh"

# python 을 이름 하나로 단정하지 않는다. CLI 는 macOS 전용이지만 이 훅은 hooks.json 에
# 무조건 등록되어 Windows 의 Claude Code 도 Git Bash 로 돌린다. 어느 기기에나 python3
# 이라는 이름이 있고 실행된다는 보장이 없으므로, python3, python 순으로 실제로 돌려 본
# 것만 쓴다. reconfigure 는 3.7 부터 있다.
PYTHON=""
for candidate in python3 python; do
  if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)' >/dev/null 2>&1; then
    PYTHON="$candidate"
    break
  fi
done
readonly PYTHON

if [ -z "$PYTHON" ]; then
  # 가드의 JSON 을 읽을 수도, 문장을 JSON 으로 감쌀 수도 없다. 이스케이프가 필요 없는
  # 고정 문장 하나만 직접 낸다.
  echo "warn [plugin:sherpa:session-start:python] neither python3 nor python runs; CLI state is unread" >&2
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
    "Sherpa 훅이 python3 도 python 도 실행하지 못해 CLI 상태를 읽지 못했습니다. Sherpa 스킬을 쓰기 전에 sherpa --version 을 직접 확인하세요."
  exit 0
fi

# bash 가 읽는 python 출력은 줄 끝을 "\n" 으로 고정한다. Windows 의 python 은 stdout 이
# text mode 라 print() 가 "\r\n" 을 쓰고, bash read 는 "\n" 만 떼어 "\r" 을 남긴다.
# 그러면 "ready\r" 이 case 의 어느 패턴에도 맞지 않아 모든 상태가 마지막 분기로 떨어진다.
emit() {
  # SessionStart 훅의 출력 계약. additionalContext 만 대화에 들어간다.
  "$PYTHON" -c '
import json, sys
sys.stdout.reconfigure(newline="\n")
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": sys.argv[1],
}}))' "$1"
}

if [ ! -x "$GUARD" ] && [ ! -f "$GUARD" ]; then
  # 가드가 없으면 플러그인 설치가 깨진 것이다. 세션을 막지는 않는다.
  emit "Sherpa 플러그인의 CLI 가드(require-cli.sh)를 찾을 수 없습니다. 플러그인을 다시 설치해야 합니다."
  exit 0
fi

status_json="$(bash "$GUARD" 2>/dev/null)" || true

if [ -z "$status_json" ]; then
  emit "Sherpa CLI 상태를 확인하지 못했습니다. Sherpa 스킬을 쓰기 전에 \`sherpa --version\`을 직접 확인하세요."
  exit 0
fi

# 필드는 줄 단위로 읽는다. remedy 가 "brew install xiyo/tap/sherpa" 처럼
# 공백을 품고 있어서, 공백으로 쪼개면 첫 낱말만 남는다.
{
  read -r status
  read -r remedy
  read -r installed
} <<EOF
$(printf '%s' "$status_json" | "$PYTHON" -c '
import json, sys
sys.stdout.reconfigure(newline="\n")
payload = json.load(sys.stdin)
print(payload.get("status", "failed"))
print(payload.get("install") or payload.get("remedy") or payload.get("error", ""))
print(payload.get("installed") or payload.get("minimum", ""))')
EOF

case "$status" in
  ready)
    # 계약을 만족한다. 침묵이 정답이다.
    ;;
  unsupported)
    # macOS 가 아니다. 가드가 스킬을 부를 때 "macOS 전용"이라고 답하므로 여기서는 말하지 않는다 —
    # 세션마다 말하면 그 기기에서 고칠 수 없는 사실을 매번 읽히게 된다.
    ;;
  missing)
    emit "Sherpa CLI가 설치되어 있지 않습니다. Sherpa 스킬(planner, context, kakaotalk-local-search, sherpa)은 CLI 없이 동작하지 않습니다. 설치: ${remedy}"
    ;;
  mismatch)
    emit "Sherpa CLI 버전이 이 플러그인의 계약과 어긋납니다(설치됨 ${installed}). 조치: ${remedy}"
    ;;
  *)
    emit "Sherpa CLI 확인에 실패했습니다(${remedy}). Sherpa 스킬을 쓰기 전에 \`sherpa --version\`을 직접 확인하세요."
    ;;
esac

exit 0
