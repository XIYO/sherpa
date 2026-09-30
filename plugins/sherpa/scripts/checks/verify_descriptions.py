"""스킬 description 은 클라이언트가 그대로 싣는다. 길이와 꺾쇠를 지킨다."""

import pathlib
import re
import sys

MAX_LENGTH = 1024

root = pathlib.Path(sys.argv[1])
bad: list[str] = []
for skill in sorted(root.glob("skills/*/SKILL.md")):
    match = re.search(r"^description:[ ]?(.*)$", skill.read_text(), re.M)
    if not match:
        bad.append(f"{skill.parent.name}: missing description")
        continue
    value = match.group(1).strip()
    if not value:
        bad.append(f"{skill.parent.name}: empty description")
    if len(value) > MAX_LENGTH:
        bad.append(f"{skill.parent.name}: description is {len(value)} chars (max {MAX_LENGTH})")
    if "<" in value or ">" in value:
        bad.append(f"{skill.parent.name}: description contains angle brackets")

if bad:
    raise SystemExit("; ".join(bad))
