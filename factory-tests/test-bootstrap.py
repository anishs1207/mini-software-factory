#!/usr/bin/env python3
"""Check bootstrap input validation without contacting OCI or GitHub."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "agents" / "setup" / "bootstrap-vm.py"
SPEC = importlib.util.spec_from_file_location("briefing_bootstrap", SCRIPT)
BOOTSTRAP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BOOTSTRAP)


class BootstrapTests(unittest.TestCase):
    def test_public_and_ssh_github_urls_normalize_without_credentials(self):
        expected = "https://github.com/example/briefing.git"
        self.assertEqual(BOOTSTRAP.https_clone_url(expected), expected)
        self.assertEqual(BOOTSTRAP.https_clone_url("git@github.com:example/briefing.git"), expected)
        with self.assertRaises(ValueError):
            BOOTSTRAP.https_clone_url("https://token@github.com/example/briefing.git")

    def test_secret_parser_reads_values_without_exposing_them(self):
        scratch = ROOT / ".local-evidence" / "test-bootstrap"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            path = Path(directory) / "secrets.env"
            path.write_text("GH_TOKEN='example-token'\nOLLAMA_API_KEY=example-key\n# comment\n", encoding="utf-8")
            values = BOOTSTRAP.secret_values(path)
            self.assertEqual(values["GH_TOKEN"], "example-token")
            self.assertEqual(values["OLLAMA_API_KEY"], "example-key")
            self.assertNotIn("comment", values)

    def test_branch_protection_requires_human_review_and_both_checks(self):
        calls = []

        def fake_run(command, **kwargs):
            calls.append((command, kwargs))
            if command[:3] == ["gh", "repo", "view"]:
                body = {"nameWithOwner": "example/briefing", "defaultBranchRef": {"name": "main"}}
            elif command[:3] == ["gh", "api", "repos/example/briefing/branches/main/protection"]:
                body = {"required_status_checks": {"contexts": ["verify", "factory-gates"], "strict": True},
                        "required_pull_request_reviews": {"required_approving_review_count": 1,
                                                          "dismiss_stale_reviews": True},
                        "enforce_admins": {"enabled": True}, "allow_force_pushes": {"enabled": False},
                        "allow_deletions": {"enabled": False}}
            else:
                body = {}
            return type("Result", (), {"stdout": json.dumps(body)})()

        with patch.object(BOOTSTRAP, "run", side_effect=fake_run):
            BOOTSTRAP.protect_repository("https://github.com/example/briefing.git", "main")
        put_call = next(kwargs for command, kwargs in calls if command[:4] == ["gh", "api", "--method", "PUT"])
        payload = json.loads(put_call["input"])
        self.assertEqual(payload["required_pull_request_reviews"]["required_approving_review_count"], 1)
        self.assertEqual(payload["required_status_checks"]["contexts"], ["verify", "factory-gates"])


if __name__ == "__main__":
    unittest.main()
