"""문서 구조를 검사한다.

두 가지를 본다.

1. frontmatter 다음에 곧바로 `# 제목`이 와야 한다. 상태 안내를 제목 앞에 붙이는
   실수를 이 세션에서만 두 번 했다. 렌더러는 그런 문서를 제목 없는 문서로 읽는다.
2. 상대 링크가 실재하는 파일을 가리켜야 한다.
3. `CLAUDE.md` 는 `@AGENTS.md` import 한 줄이어야 한다. 규칙의 본문은 `AGENTS.md`
   하나다. 이 파일이 사라지면 Claude Code 세션은 규칙 없이 일하고, 본문이 여기로
   복제되면 두 파일이 갈라진다. 둘 다 조용히 일어나므로 게이트가 잡는다.
"""

import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
targets = (
    sorted(root.glob("docs/**/*.md"))
    + sorted(root.glob(".handoff/**/*.md"))
    + [root / "README.md", root / "AGENTS.md"]
)

problems: list[str] = []
for path in targets:
    if not path.is_file():
        continue
    text = path.read_text()
    rel = path.relative_to(root)

    body = re.sub(r"^---\n.*?\n---\n", "", text, count=1, flags=re.S).lstrip()
    if body and not body.startswith("#"):
        problems.append(f"{rel}: body starts before the title — {body.splitlines()[0][:60]}")

    for match in re.finditer(r"\]\((?!https?://|#)([^)]+)\)", text):
        target = (path.parent / match.group(1).split("#")[0]).resolve()
        if not target.exists():
            problems.append(f"{rel}: dead link {match.group(1)}")

claude_md = root / "CLAUDE.md"
if not (root / "AGENTS.md").is_file():
    problems.append("AGENTS.md: missing — it is the body CLAUDE.md imports")
if claude_md.is_symlink():
    problems.append("CLAUDE.md: is a symbolic link — a clone with core.symlinks=false flattens it")
elif not claude_md.is_file():
    problems.append("CLAUDE.md: missing — Claude Code sessions would run without AGENTS.md")
elif claude_md.read_text().strip() != "@AGENTS.md":
    problems.append("CLAUDE.md: must be the single line @AGENTS.md — rules belong in AGENTS.md")

if problems:
    raise SystemExit("\n".join(problems))
