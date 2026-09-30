#!/usr/bin/env python3
"""Lint Korean Calendar Event titles and notes without echoing their content."""

from __future__ import annotations

import json
import re
import sys
from typing import Any

MAX_INPUT_BYTES = 128 * 1024
SCHEMA = "sherpa.planner.korean-writing-lint.v1"

TITLE_RULES = (
    ("title.completion", re.compile(r"완료|했음|했다|했어요|됐음|되었음|종료됨|수령함|도착함|처리됨")),
    ("title.future", re.compile(r"예정(?:임|입니다)?|진행\s*예정|할\s*예정")),
    ("title.passive", re.compile(r"(?:배송|설치|점검|결제|상환)(?:이|가)?\s*(?:진행|처리)?(?:될|됨|되었)")),
)

NOTE_RULES = (
    ("notes.completion_sentence", re.compile(r"(?:배송|설치|점검|처리)\s*(?:이|가)?\s*완료|완료되었|완료했")),
    ("notes.future_sentence", re.compile(r"예정입니다|진행될\s*예정|할\s*예정입니다")),
    ("notes.translationese", re.compile(r"와\s*관련하여|에\s*있어서|되어진|을\s*통하여")),
)


def reject(message: str) -> None:
    print(json.dumps({"schema": SCHEMA, "valid": False, "errors": [message], "warnings": []}, ensure_ascii=False))
    raise SystemExit(2)


def load_payload() -> dict[str, Any]:
    raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
    if not raw or len(raw) > MAX_INPUT_BYTES:
        reject("input.invalid_size")
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError):
        reject("input.invalid_json")
    if not isinstance(payload, dict) or set(payload) - {"title", "notes", "official_title"}:
        reject("input.invalid_shape")
    if not isinstance(payload.get("title"), str) or not payload["title"].strip():
        reject("title.required")
    if payload.get("notes") is not None and not isinstance(payload.get("notes"), str):
        reject("notes.invalid_type")
    if not isinstance(payload.get("official_title", False), bool):
        reject("official_title.invalid_type")
    return payload


def main() -> None:
    payload = load_payload()
    title = payload["title"]
    notes = payload.get("notes") or ""
    official_title = payload.get("official_title", False)

    errors = [] if official_title else [rule for rule, pattern in TITLE_RULES if pattern.search(title)]
    warnings = [rule for rule, pattern in NOTE_RULES if pattern.search(notes)]
    if "  " in title or title != title.strip():
        warnings.append("title.spacing")

    result = {
        "schema": SCHEMA,
        "valid": not errors,
        "errors": sorted(set(errors)),
        "warnings": sorted(set(warnings)),
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    raise SystemExit(0 if not errors else 1)


if __name__ == "__main__":
    main()
