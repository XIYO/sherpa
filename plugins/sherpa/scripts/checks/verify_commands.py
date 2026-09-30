"""스킬이 부르는 sherpa 명령이 CLI 에 실제로 있는지 확인한다.

supply 스킬은 대응 명령이 없는 채로 오래 살아남았고, 호출하면 invalidRequest 로
죽었다. --help 가 나열하는 명령 집합을 진실로 삼아 그 재발을 막는다.
"""

import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
help_text = (root / ".help-snapshot").read_text()

known_top: set[str] = set()
known_pairs: set[tuple[str, str]] = set()
for match in re.finditer(r"^\s+sherpa ([a-z][a-z-]*)(?: ([a-z][a-z-]*))?", help_text, re.M):
    known_top.add(match.group(1))
    if match.group(2):
        known_pairs.add((match.group(1), match.group(2)))

if not known_top:
    raise SystemExit("could not read any command from --help; refusing to pass silently")

bad: list[str] = []
for skill in sorted(root.glob("skills/*/SKILL.md")):
    for match in re.finditer(r"sherpa ([a-z][a-z-]*)(?: ([a-z][a-z-]*))?", skill.read_text()):
        top, sub = match.group(1), match.group(2)
        if top not in known_top:
            bad.append(f"{skill.parent.name}: sherpa {top}")
        elif sub and any(t == top for t, _ in known_pairs) and (top, sub) not in known_pairs:
            bad.append(f"{skill.parent.name}: sherpa {top} {sub}")

if bad:
    raise SystemExit("unknown commands: " + "; ".join(sorted(set(bad))))
