#!/usr/bin/env bash
# 플러그인 검사 진입점(macOS/Linux). scripts/check-all.sh 가 호출한다.
#
# sherpa 플러그인은 스킬과 두 매니페스트, CLI 계약만으로 이루어진다. 빌드 산출물이
# 없으므로 검사는 "배포되는 파일이 서로 모순되지 않는가"에 집중한다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly SCRIPT_DIR PLUGIN_ROOT
readonly EXPECTED_SKILLS="agent-messenger context kakaotalk-local-search planner sherpa"
readonly ENTRY_SKILL="sherpa"

fail() {
  echo "[check:sherpa:failure] $1" >&2
  exit 1
}

echo "[check:sherpa:start] root=${PLUGIN_ROOT##*/}" >&2

command -v python3 >/dev/null 2>&1 || fail "reason=python3_missing"

# 1. 매니페스트 두 벌이 존재하고, name 이 같고, base version 이 같아야 한다.
claude_manifest="$PLUGIN_ROOT/.claude-plugin/plugin.json"
codex_manifest="$PLUGIN_ROOT/.codex-plugin/plugin.json"
[ -f "$claude_manifest" ] || fail "reason=claude_manifest_missing"
[ -f "$codex_manifest" ] || fail "reason=codex_manifest_missing"

python3 - "$claude_manifest" "$codex_manifest" <<'PY' || fail "reason=manifest_mismatch"
import json, re, sys
claude, codex = (json.load(open(p)) for p in sys.argv[1:3])
if claude["name"] != codex["name"] != "sherpa":
    raise SystemExit("name mismatch")
base = lambda v: v.split("+", 1)[0]
if base(claude["version"]) != base(codex["version"]):
    raise SystemExit(f'base version mismatch: {claude["version"]} vs {codex["version"]}')
if not re.fullmatch(r"\d+\.\d+\.\d+", claude["version"]):
    raise SystemExit(f'claude version is not a plain semver: {claude["version"]}')
PY

# 2. CLI 계약이 유효한 semver 최소 버전을 들고 있어야 한다. 가드가 이걸 읽는다.
contract="$PLUGIN_ROOT/cli-contract.json"
[ -f "$contract" ] || fail "reason=cli_contract_missing"
python3 - "$contract" <<'PY' || fail "reason=cli_contract_invalid"
import json, re, sys
c = json.load(open(sys.argv[1]))
for key in ("command", "minimumVersion", "versionArgs", "versionPattern"):
    if key not in c:
        raise SystemExit(f"missing key: {key}")
if not re.fullmatch(r"\d+\.\d+\.\d+", c["minimumVersion"]):
    raise SystemExit(f'minimumVersion is not semver: {c["minimumVersion"]}')
PY

# 3. 가드 스크립트는 문법이 성립하고 실행 가능해야 한다.
guard="$SCRIPT_DIR/require-cli.sh"
[ -f "$guard" ] || fail "reason=guard_missing"
[ -x "$guard" ] || fail "reason=guard_not_executable"
bash -n "$guard" || fail "reason=guard_syntax_error"

# 4. 스킬 집합이 정확히 일치해야 한다. 진입 스킬(plugin name 과 같은 이름)은 필수다.
actual="$(cd "$PLUGIN_ROOT/skills" && ls -d */ 2>/dev/null | tr -d '/' | sort | tr '\n' ' ')"
expected="$(echo "$EXPECTED_SKILLS" | tr ' ' '\n' | sort | tr '\n' ' ')"
[ "$actual" = "$expected" ] || fail "reason=skill_set_mismatch expected=[$expected] actual=[$actual]"
[ -f "$PLUGIN_ROOT/skills/$ENTRY_SKILL/SKILL.md" ] || fail "reason=entry_skill_missing"

# 5. 각 스킬은 프론트매터 name 이 디렉터리명과 같고, 죽은 계약 필드가 없어야 한다.
for dir in "$PLUGIN_ROOT"/skills/*/; do
  name="$(basename "$dir")"
  skill="$dir/SKILL.md"
  [ -f "$skill" ] || fail "reason=skill_md_missing skill=$name"
  grep -q "^name: $name$" "$skill" || fail "reason=skill_name_mismatch skill=$name"
  ! grep -q '^contract_version:' "$skill" || fail "reason=contract_version_present skill=$name"
done

# 6. Sherpa CLI 를 호출하는 스킬은 가드를 거쳐야 한다. agent-messenger 는 상류 CLI 만 쓰므로 제외한다.
for name in context kakaotalk-local-search planner sherpa; do
  grep -q 'require-cli.sh' "$PLUGIN_ROOT/skills/$name/SKILL.md" \
    || fail "reason=guard_not_referenced skill=$name"
done

# 7. 배포물에 이 머신의 절대 경로가 새어 나가면 안 된다.
#    패턴을 문자 클래스로 쓴다 — 리터럴로 적으면 이 스크립트가 자기 자신을 잡는다.
readonly HOME_PATH_PATTERN='/[U]sers/'
if leaked="$(grep -rlE "$HOME_PATH_PATTERN" "$PLUGIN_ROOT" 2>/dev/null)"; then
  fail "reason=absolute_path_leak files=$(echo "$leaked" | tr '\n' ',')"
fi

# 8. 스킬이 부르는 CLI 명령이 실제로 존재해야 한다.
#    supply 스킬은 대응 명령이 없는 채로 오래 살아남았고, 호출하면 invalidRequest 로
#    죽었다. 그 재발을 여기서 막는다. 바이너리는 게이트가 넘겨주고, 없으면 건너뛰되
#    건너뛴 사실을 남긴다 — 조용히 통과하면 검사가 없는 것과 같다.
binary="${SHERPA_BINARY:-$(command -v sherpa 2>/dev/null || true)}"
if [ -n "$binary" ] && [ -x "$binary" ]; then
  "$binary" --help > "$PLUGIN_ROOT/.help-snapshot" 2>&1 || true
  python3 "$SCRIPT_DIR/checks/verify_commands.py" "$PLUGIN_ROOT" \
    || fail "reason=skill_calls_unknown_command"
  rm -f "$PLUGIN_ROOT/.help-snapshot"
  echo "[check:sherpa:commands] verified against ${binary##*/}" >&2
else
  echo "[check:sherpa:commands] skipped reason=no_binary — command existence is UNVERIFIED" >&2
fi

# 9. 스킬이 참조하는 스크립트가 실제로 있어야 한다.
python3 "$SCRIPT_DIR/checks/verify_references.py" "$PLUGIN_ROOT" \
  || fail "reason=skill_references_missing_script"

# 10. description 은 클라이언트가 그대로 싣는다. 길이와 꺾쇠를 지킨다.
python3 "$SCRIPT_DIR/checks/verify_descriptions.py" "$PLUGIN_ROOT" \
  || fail "reason=skill_description_invalid"

# 11. SessionStart 훅이 CLI 어긋남을 세션 첫머리에 알리고, 정상일 때는 침묵하며,
#     어떤 상태에서도 세션을 실패시키지 않아야 한다.
python3 "$SCRIPT_DIR/checks/verify_session_start.py" "$PLUGIN_ROOT" \
  || fail "reason=session_start_hook_invalid"

# 8. 생성물이 섞인 채로 배포되면 안 된다 (저장소 규칙: 플러그인 안에 빌드 산출물을 두지 않는다).
for junk in __pycache__ .DS_Store .venv node_modules; do
  found="$(find "$PLUGIN_ROOT" -name "$junk" -print -quit)"
  [ -z "$found" ] || fail "reason=build_artifact_present artifact=$junk path=${found#"$PLUGIN_ROOT/"}"
done

echo "[check:sherpa:success] skills=$(echo "$EXPECTED_SKILLS" | wc -w | tr -d ' ') minimum_cli=$(python3 -c "import json;print(json.load(open('$contract'))['minimumVersion'])")" >&2
