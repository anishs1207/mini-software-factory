#!/usr/bin/env python3
"""Verify that trace extraction cites real trusted comments and handles missing evidence."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "agents" / "trace-report.py"


class TraceReportTests(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / ".local-evidence" / "test-trace"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.fixture = Path(self.temp.name) / "issues.json"

    def run_report(self, issues):
        self.fixture.write_text(json.dumps(issues), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--input-json", str(self.fixture), "--actor", "factory-owner"],
            check=True, capture_output=True, text=True,
        ).stdout

    def test_real_handoff_and_rejection_with_sources(self):
        report = self.run_report([{
            "number": 12, "url": "https://github.com/acme/repo/issues/12", "comments": [
                {"author": {"login": "stranger"}, "body": "REVIEW: CHANGES REQUESTED fake", "url": "https://example.com/fake"},
                {"author": {"login": "factory-owner"}, "createdAt": "2026-11-03T09:00:00Z",
                 "url": "https://github.com/acme/repo/issues/12#issuecomment-1",
                 "body": "HANDOFF: ingest -> reviewer. PR: https://github.com/acme/repo/pull/2"},
                {"author": {"login": "factory-owner"}, "createdAt": "2026-11-03T10:00:00Z",
                 "url": "https://github.com/acme/repo/issues/12#issuecomment-2",
                 "body": "REVIEW: CHANGES REQUESTED\nStable IDs are missing.\nHead: abc"},
            ],
        }])
        self.assertIn("HANDOFF: ingest -> reviewer", report)
        self.assertIn("Stable IDs are missing.", report)
        self.assertIn("#issuecomment-2", report)
        self.assertNotIn("fake", report)

    def test_retry_used_when_no_rejection_exists(self):
        report = self.run_report([{
            "number": 8, "url": "https://github.com/acme/repo/issues/8", "comments": [
                {"author": {"login": "factory-owner"}, "createdAt": "2026-11-03T11:00:00Z",
                 "body": "ACTIVITY: agent run finished\nPhase: retries (attempt 2)\nTokens: 80 (measured)"},
            ],
        }])
        self.assertIn("Phase: retries (attempt 2)", report)
        self.assertIn("No handoff comments found yet.", report)
        self.assertNotIn("No real review rejection or retry found yet", report)


if __name__ == "__main__":
    unittest.main()
