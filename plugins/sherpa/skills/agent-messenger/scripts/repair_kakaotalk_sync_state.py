#!/usr/bin/env python3
"""Quarantine malformed Agent Messenger KakaoTalk sync-state caches."""

from __future__ import annotations

import json
import os
import stat
import sys
import time
from pathlib import Path

ACTION = "[skill:agent-messenger:repair-kakaotalk-sync-state]"
CONFIG_ENV = "AGENT_MESSENGER_CONFIG_DIR"
MAX_STATE_BYTES = 1024 * 1024
SYNC_STATE_GLOB = "kakaotalk-sync-state-*.json"


class RepairError(RuntimeError):
    """A safe, stable repair failure."""


def _log(level: str, message: str, **context: object) -> None:
    priorities = {"debug": 10, "info": 20, "warn": 30, "error": 40}
    configured = os.environ.get("LOG_LEVEL", "warn").lower()
    threshold = priorities.get(configured, priorities["warn"])
    if priorities[level] < threshold:
        return

    suffix = " ".join(f"{key}={value}" for key, value in sorted(context.items()))
    print(f"{ACTION} {message}{' ' + suffix if suffix else ''}", file=sys.stderr)


def _config_dir() -> Path:
    configured = os.environ.get(CONFIG_ENV)
    return Path(configured) if configured else Path.home() / ".config" / "agent-messenger"


def _backup_path(path: Path) -> Path:
    timestamp = time.time_ns()
    for suffix in range(100):
        candidate = path.with_name(f"{path.name}.invalid-{timestamp + suffix}")
        if not candidate.exists():
            return candidate
    raise RepairError("backup_name_unavailable")


def _read_regular_file(path: Path) -> tuple[bytes, os.stat_result]:
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode):
        raise RepairError("sync_state_not_regular_file")
    if before.st_size > MAX_STATE_BYTES:
        raise RepairError("sync_state_too_large")

    payload = path.read_bytes()
    after = path.lstat()
    if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
        after.st_dev,
        after.st_ino,
        after.st_size,
        after.st_mtime_ns,
    ):
        raise RepairError("sync_state_changed_during_read")
    return payload, after


def repair(config_dir: Path) -> dict[str, int | str]:
    if not config_dir.exists():
        return {"status": "ok", "scanned": 0, "quarantined": 0}
    if not config_dir.is_dir():
        raise RepairError("config_path_not_directory")

    scanned = 0
    quarantined = 0
    for path in sorted(config_dir.glob(SYNC_STATE_GLOB)):
        scanned += 1
        payload, observed = _read_regular_file(path)
        try:
            json.loads(payload)
            continue
        except (UnicodeDecodeError, json.JSONDecodeError):
            pass

        current = path.lstat()
        if (observed.st_dev, observed.st_ino, observed.st_size, observed.st_mtime_ns) != (
            current.st_dev,
            current.st_ino,
            current.st_size,
            current.st_mtime_ns,
        ):
            raise RepairError("sync_state_changed_before_quarantine")

        backup = _backup_path(path)
        path.rename(backup)
        backup.chmod(0o600)
        quarantined += 1

    return {
        "status": "repaired" if quarantined else "ok",
        "scanned": scanned,
        "quarantined": quarantined,
    }


def main() -> int:
    _log("info", "start")
    try:
        result = repair(_config_dir())
    except (OSError, RepairError) as error:
        code = str(error) if isinstance(error, RepairError) else "filesystem_error"
        _log("error", "failure", code=code, error_type=type(error).__name__)
        print(json.dumps({"status": "failed", "error": code}, separators=(",", ":")))
        return 1

    _log(
        "info",
        "success",
        quarantined=result["quarantined"],
        scanned=result["scanned"],
    )
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
