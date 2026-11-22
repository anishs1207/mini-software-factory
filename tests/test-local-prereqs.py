#!/usr/bin/env python3
"""Exercise Terraform's automatic local SSH inputs without a network call."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "agents" / "setup" / "local-prereqs.py"


class LocalPrereqTests(unittest.TestCase):
    def test_generates_ignored_key_and_uses_explicit_ipv4(self):
        scratch = ROOT / ".local-evidence" / "test-local-prereqs"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            query = {"workspace_root": directory, "ssh_allowed_cidr": "203.0.113.4/32",
                     "ssh_public_key_path": "", "ssh_private_key_path": ""}
            result = subprocess.run([sys.executable, str(SCRIPT)], input=json.dumps(query),
                                    text=True, capture_output=True, check=True)
            output = json.loads(result.stdout)
            self.assertEqual(output["ssh_allowed_cidr"], "203.0.113.4/32")
            self.assertTrue(Path(output["ssh_private_key_path"]).is_file())
            self.assertTrue(output["public_key"].startswith("ssh-ed25519 "))
            again = subprocess.run([sys.executable, str(SCRIPT)], input=json.dumps(query),
                                   text=True, capture_output=True, check=True)
            self.assertEqual(json.loads(again.stdout), output)


if __name__ == "__main__":
    unittest.main()
