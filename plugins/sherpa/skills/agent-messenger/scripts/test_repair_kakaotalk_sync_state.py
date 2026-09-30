from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("repair_kakaotalk_sync_state.py")


class RepairKakaoTalkSyncStateTests(unittest.TestCase):
    def run_script(self, config_dir: Path) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment["AGENT_MESSENGER_CONFIG_DIR"] = str(config_dir)
        environment["LOG_LEVEL"] = "error"
        return subprocess.run(
            [sys.executable, str(SCRIPT)],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

    def test_quarantines_json_with_the_reproduced_trailing_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            config_dir = Path(temporary_directory)
            state = config_dir / "kakaotalk-sync-state-test-device.json"
            original = json.dumps({"version": 2, "revision": 1}, indent=2).encode() + b"broken-tail-value"
            state.write_bytes(original)

            result = self.run_script(config_dir)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                json.loads(result.stdout),
                {"status": "repaired", "scanned": 1, "quarantined": 1},
            )
            self.assertFalse(state.exists())
            backups = list(config_dir.glob(f"{state.name}.invalid-*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), original)
            self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)
            self.assertNotIn("test-device", result.stdout + result.stderr)
            self.assertNotIn("broken-tail-value", result.stdout + result.stderr)

    def test_keeps_valid_json_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            config_dir = Path(temporary_directory)
            state = config_dir / "kakaotalk-sync-state-test-device.json"
            original = b'{"version":2,"revision":1}'
            state.write_bytes(original)

            result = self.run_script(config_dir)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                json.loads(result.stdout),
                {"status": "ok", "scanned": 1, "quarantined": 0},
            )
            self.assertEqual(state.read_bytes(), original)
            self.assertEqual(list(config_dir.glob(f"{state.name}.invalid-*")), [])

    def test_rejects_a_symlink_without_touching_its_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            config_dir = Path(temporary_directory)
            target = config_dir / "target.json"
            target.write_text("not-json", encoding="utf-8")
            state = config_dir / "kakaotalk-sync-state-test-device.json"
            state.symlink_to(target)

            result = self.run_script(config_dir)

            self.assertEqual(result.returncode, 1)
            self.assertEqual(
                json.loads(result.stdout),
                {"status": "failed", "error": "sync_state_not_regular_file"},
            )
            self.assertEqual(target.read_text(encoding="utf-8"), "not-json")
            self.assertTrue(state.is_symlink())


if __name__ == "__main__":
    unittest.main()
