"""스킬이 가리키는 스크립트와 참조 문서가 실제로 있는지 확인한다.

스킬은 자기 디렉터리의 파일을 상대경로로 부르지만, 다른 스킬의 것을 명시적으로
가리키기도 한다 — agent-messenger 가 "the Context skill's scripts/…" 라고 쓰는
식이다. 그래서 플러그인 전체에서 찾는다. 목적은 위치 강제가 아니라 죽은 참조를
막는 것이다.
"""

import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
available = {path.name for path in root.rglob("*") if path.is_file()}

missing: list[str] = []
for skill in sorted(root.glob("skills/*/SKILL.md")):
    for match in re.finditer(r"(?:scripts|references)/([A-Za-z0-9_.-]+\.(?:py|sh|md))", skill.read_text()):
        if match.group(1) not in available:
            missing.append(f"{skill.parent.name}: {match.group(0)}")

if missing:
    raise SystemExit("missing: " + "; ".join(sorted(set(missing))))
