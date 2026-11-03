#!/usr/bin/env python3
"""Check per-run accounting, retries, and honest missing-data reporting."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ACTIVITY = ROOT / "agents" / "activity.py"


class ActivityTests(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / ".local-evidence" / "test-activity"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.usage = Path(self.temp.name)

    def command(self, *args):
        return subprocess.run(
            [sys.executable, str(ACTIVITY), *args, "--usage-dir", str(self.usage)],
            capture_output=True, text=True, check=True, env={**os.environ, "OPENCLAW_BUILDER_MODEL": "configured/model"},
        ).stdout

    def record(self, run_id, role="builder1", issue="12"):
        self.command(
            "record", "--run-id", run_id, "--agent", role, "--issue", issue,
            "--started-at", "2026-11-03T00:00:00Z", "--finished-at", "2026-11-03T00:01:00Z",
            "--exit-code", "0", "--source-stage", "factory:ready",
        )
        return json.loads((self.usage / f"{run_id}.activity.json").read_text())

    def test_openclaw_usage_and_repeat_dispatch(self):
        (self.usage / "first.openclaw.json").write_text(json.dumps({
            "model": "model-a", "provider": "ollama-cloud",
            "usage": {"input": 20, "output": 5, "total": 25},
        }))
        first = self.record("first")
        self.assertEqual(first["model"], "ollama-cloud/model-a")
        self.assertEqual(first["tokens"]["total"], 25)
        self.assertEqual(first["report_phase"], "coding")
        self.assertEqual(first["configured_model"], "configured/model")
        self.assertIn("Tokens: 25 (measured)", self.command("comment", "--run-id", "first"))
        (self.usage / "second.openclaw.json").write_text(json.dumps({
            "model": "free-model", "provider": "openrouter",
            "usage": {"input": 8, "output": 2, "total": 10},
        }))
        second = self.record("second")
        self.assertEqual(second["report_phase"], "retries")
        self.assertEqual(second["attempt"], 2)
        self.assertEqual(second["model"], "openrouter/free-model")
        report = self.command("report")
        self.assertIn("ollama-cloud/model-a\tcoding\t25", report)
        self.assertIn("openrouter/free-model\tretries\t10", report)

    def test_openclaw_gateway_run_stats(self):
        (self.usage / "gateway.openclaw.json").write_text(json.dumps({
            "result": {"payloads": [{"text": "Done"}], "meta": {"agentMeta": {
                "provider": "ollama-cloud", "model": "coder:cloud",
                "usage": {"input": 120, "output": 8, "total": 128},
            }}},
        }))
        item = self.record("gateway")
        self.assertEqual(item["model"], "ollama-cloud/coder:cloud")
        self.assertEqual(item["tokens"]["input"], 120)
        self.assertEqual(item["tokens"]["output"], 8)
        self.assertEqual(item["tokens"]["total"], 128)
        self.assertEqual(item["tokens"]["status"], "measured")

    def test_role_models_are_recorded(self):
        original = {name: os.environ.get(name) for name in
                    ("OLLAMA_MODEL", "OPENROUTER_API_KEY", "OPENROUTER_REASONING_MODEL")}
        os.environ["OLLAMA_MODEL"] = "beam"
        os.environ["OPENROUTER_API_KEY"] = "router-key"
        os.environ["OPENROUTER_REASONING_MODEL"] = "nvidia/nemotron-3-ultra-550b-a55b:free"
        def restore():
            for name, value in original.items():
                if value is None:
                    os.environ.pop(name, None)
                else:
                    os.environ[name] = value
        self.addCleanup(restore)
        self.assertEqual(self.record("builder", role="builder1")["configured_model"],
                         "ollama-cloud/beam")
        self.assertEqual(self.record("tester", role="tester")["configured_model"],
                         "beam")
        self.assertEqual(self.record("reviewer", role="reviewer")["configured_model"],
                         "openrouter/nvidia/nemotron-3-ultra-550b-a55b:free")

    def test_hermes_includes_auxiliary_without_hiding_it(self):
        (self.usage / "review.hermes.json").write_text(json.dumps({
            "provider": "ollama-cloud", "model": "gpt-oss:120b", "total_tokens": 100,
            "auxiliary": {"total_tokens": 15},
            "total_including_auxiliary": {"total_tokens": 115},
        }))
        item = self.record("review", role="reviewer")
        self.assertEqual(item["tokens"]["total"], 115)
        self.assertEqual(item["tokens"]["main"], 100)
        self.assertEqual(item["tokens"]["auxiliary"], 15)
        self.assertIn("auxiliary model attribution", item["model_attribution"])
        self.assertEqual(item["report_phase"], "review/test")
        report = self.command("report")
        self.assertIn("ollama-cloud/gpt-oss:120b\treview/test\t100", report)
        self.assertIn("unknown (Hermes auxiliary)\treview/test\t15", report)

    def test_missing_usage_is_unknown_until_explicit_estimate(self):
        item = self.record("missing")
        self.assertIsNone(item["tokens"]["total"])
        self.assertEqual(item["tokens"]["status"], "unavailable")
        self.assertIn("unknown_runs", self.command("report"))
        self.command(
            "estimate", "--run-id", "missing", "--model", "openrouter/free-model",
            "--tokens", "40", "--method", "PR #7 provider usage estimate",
        )
        item = json.loads((self.usage / "missing.activity.json").read_text())
        self.assertEqual(item["tokens"]["status"], "estimated")
        self.assertEqual(item["tokens"]["total"], 40)
        self.assertIn("openrouter/free-model\tcoding\t0\t40", self.command("report"))

    def test_local_report_groups_issue_and_manager_chat_purpose(self):
        (self.usage / "build.openclaw.json").write_text(json.dumps({
            "result": {"meta": {"agentMeta": {"provider": "ollama-cloud",
                "model": "coder", "usage": {"input": 30, "output": 10, "total": 40}}}},
        }))
        self.command(
            "record", "--run-id", "build", "--agent", "builder1", "--issue", "12",
            "--task", "Issue #12: Build search", "--purpose", "implementation",
            "--started-at", "2026-11-03T00:00:00Z", "--finished-at", "2026-11-03T00:01:00Z",
            "--exit-code", "0", "--source-stage", "factory:ready",
        )
        (self.usage / "chat.hermes.json").write_text(json.dumps({
            "provider": "openrouter", "model": "planner", "total_tokens": 17,
        }))
        for run_id in ("chat", "chat2"):
            self.command(
                "record", "--run-id", run_id, "--agent", "manager",
                "--task", "Plan and ticket product spec", "--purpose", "spec_planning",
                "--started-at", "2026-11-03T00:00:00Z", "--finished-at", "2026-11-03T00:01:00Z",
                "--exit-code", "0", "--source-stage", "interactive-chat",
            )
        chat2 = json.loads((self.usage / "chat2.activity.json").read_text())
        self.assertEqual(chat2["report_phase"], "planning")
        self.assertIn("Issue: unassigned", self.command("comment", "--run-id", "chat"))
        report = self.command("report")
        self.assertIn("12\tbuilder1\timplementation\t40\t0\t0\t1", report)
        self.assertIn("unassigned\tmanager\tspec_planning\t17\t0\t1\t2", report)


if __name__ == "__main__":
    unittest.main()
