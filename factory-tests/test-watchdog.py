#!/usr/bin/env python3
"""Exercise the gate watchdog without starting an agent or VM."""

import subprocess
import sys
import unittest
from pathlib import Path


WATCHDOG = Path(__file__).resolve().parents[1] / "agents" / "agent-watchdog.py"


@unittest.skipUnless(sys.platform.startswith("linux"), "watchdog uses POSIX process groups")
class WatchdogTests(unittest.TestCase):
    def run_child(self, source):
        return subprocess.run(
            [sys.executable, str(WATCHDOG), "--max-slow-calls", "2",
             sys.executable, "-u", "-c", source],
            capture_output=True, text=True, timeout=10,
        )

    def test_success_and_child_failure_are_preserved(self):
        self.assertEqual(self.run_child("print('done')").returncode, 0)
        self.assertEqual(self.run_child("raise SystemExit(7)").returncode, 7)

    def test_repeated_slow_calls_stop_run(self):
        result = self.run_child("print('tool 151.0s'); print('tool 150.0s')")
        self.assertEqual(result.returncode, 124)
        self.assertIn("WATCHDOG:", result.stdout)

    def test_repeated_failed_command_stops_run(self):
        result = self.run_child("for _ in range(3): print(chr(0x2717) + ' $ false')")
        self.assertEqual(result.returncode, 124)
        self.assertIn("same terminal command failed 3 times", result.stdout)


if __name__ == "__main__":
    unittest.main()
