#!/usr/bin/env bash
# 저장소 게이트. push 전과 CI 에서 같은 것을 돌린다.
#
# 이 저장소는 두 가지를 배포한다 — brew 로 나가는 네이티브 CLI 와,
# plugin marketplace 로 나가는 에이전트 스킬. 게이트는 둘 다 본다.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly REPO_ROOT
readonly LOG_SCOPE="check:repository"

log() { printf '%s [%s] %s\n' "$1" "$2" "$3" >&2; }
fail() { log error "$LOG_SCOPE:failure" "$1"; exit 1; }

log info "$LOG_SCOPE:start" "root=${REPO_ROOT##*/}"

# 1. Swift 패키지 전부. eventkit-service 만 돌리던 시절, worker-protocol 과
#    foundation-models-service 의 테스트 34 개가 아무도 돌리지 않는 채로 남아 있었다.
#    돌리지 않는 테스트는 없는 테스트다.
#    foundation-models-service 는 CLI 가 부르지 않는다 — 의도적으로 배선하지 않은 채
#    보존한다(승인된 계약 둘의 유일한 구현. docs/roadmap/README.md Phase 2).
#    이 패키지가 platforms: [.macOS(.v26)] 이라 게이트 전체가 macOS 26 이상을 요구한다.
readonly SWIFT_PACKAGES="worker-protocol foundation-models-service eventkit-service"
for package in $SWIFT_PACKAGES; do
  log info "check:swift:start" "package=$package"
  swift build --package-path "$REPO_ROOT/apple/$package" >/dev/null \
    || fail "reason=swift_build_failed package=$package"
  swift test --package-path "$REPO_ROOT/apple/$package" >/dev/null \
    || fail "reason=swift_test_failed package=$package"
done

# --version 출력 형식은 계약이다. 스킬의 가드와 Formula 의 test 가 이 모양을 파싱한다.
binary="$REPO_ROOT/apple/eventkit-service/.build/debug/sherpa"
raw="$("$binary" --version)"
printf '%s' "$raw" | grep -Eq '^sherpa [0-9]+\.[0-9]+\.[0-9]+$' \
  || fail "reason=version_format_broken output=$raw"
cli_version="$(printf '%s' "$raw" | awk '{print $2}')"

# 실패는 이름 있는 오류 코드로 끝나야 한다. 최상위 catch 가 알 수 없는 실패를 stdout·stderr
# 0 바이트로 끝내던 것을 이 호출로 재현했다. {} 는 봉투 검사에서 거부되므로 EventKit 과
# 기록부에 닿기 전에 끝난다.
if probe="$(printf '{}' | "$binary" planner request 2>/dev/null)"; then
  fail "reason=invalid_request_accepted"
fi
python3 -c 'import json, sys; assert json.loads(sys.argv[1]) == {"status": "failed", "error": "protocol.invalid_envelope"}' "$probe" \
  || fail "reason=failure_unnamed output=$probe"
log info "check:swift:success" "packages=3 cli_version=$cli_version"

# 2. 에이전트 플러그인. 방금 빌드한 바이너리를 넘겨 스킬이 부르는 명령이 실제로
#    존재하는지까지 확인시킨다.
SHERPA_BINARY="$binary" bash "$REPO_ROOT/plugins/sherpa/scripts/check.sh" \
  || fail "reason=plugin_check_failed"

# 3. 두 마켓플레이스 매니페스트가 같은 플러그인을, 같은 순서로 담아야 한다.
python3 - "$REPO_ROOT" <<'PY' || fail "reason=marketplace_mismatch"
import json, sys, pathlib
root = pathlib.Path(sys.argv[1])
claude = json.loads((root / ".claude-plugin/marketplace.json").read_text())
codex = json.loads((root / ".agents/plugins/marketplace.json").read_text())
names = lambda d: [p["name"] for p in d["plugins"]]
if names(claude) != names(codex):
    raise SystemExit(f"order or membership differs: {names(claude)} vs {names(codex)}")
if claude["name"] != codex["name"]:
    raise SystemExit(f'marketplace name differs: {claude["name"]} vs {codex["name"]}')
for entry in claude["plugins"]:
    source = root / entry["source"]
    if not (source / ".claude-plugin/plugin.json").is_file():
        raise SystemExit(f'source has no manifest: {entry["source"]}')
PY
log info "check:marketplace:success" "manifests=2"

# 4. 스킬이 요구하는 최소 CLI 버전이 이 체크아웃의 CLI 로 만족되는가.
#    같은 저장소에서 나가는 둘이 서로 모순인 채 릴리스되는 것을 막는다.
minimum="$(python3 -c "import json;print(json.load(open('$REPO_ROOT/plugins/sherpa/cli-contract.json'))['minimumVersion'])")"
python3 - "$cli_version" "$minimum" <<'PY' || fail "reason=cli_older_than_contract"
import sys
installed, minimum = (tuple(int(x) for x in v.split(".")) for v in sys.argv[1:3])
if installed < minimum:
    raise SystemExit(f"cli {'.'.join(map(str, installed))} < contract {'.'.join(map(str, minimum))}")
PY
log info "check:contract:success" "cli=$cli_version minimum=$minimum"

# 5. 문서 구조. 제목 앞에 본문이 오면 렌더러가 제목 없는 문서로 읽는다.
python3 "$REPO_ROOT/scripts/checks/verify_docs.py" "$REPO_ROOT" || fail "reason=doc_structure_invalid"
log info "check:docs:success" "structure and links"

# 6. 릴리스 경로. brew 가 없으면(리눅스 CI 등) 건너뛰되 건너뛴 사실을 남긴다.
#    SHERPA_SKIP_RELEASE=1 로 명시적으로 끌 수 있다 — 반복 실행에서 느리기 때문이다.
if [ "${SHERPA_SKIP_RELEASE:-0}" = "1" ]; then
  log warn "check:release:skipped" "reason=explicitly_disabled — release path is UNVERIFIED"
elif command -v brew >/dev/null 2>&1; then
  bash "$REPO_ROOT/scripts/check-release.sh" || fail "reason=release_check_failed"
else
  log warn "check:release:skipped" "reason=no_brew — release path is UNVERIFIED"
fi

log info "$LOG_SCOPE:success" "cli=$cli_version plugin=1"
