#!/usr/bin/env python3
"""Exercise the durable pre-push guard and setup installation contract."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / "agents" / "pre-push-product.sh"
SETUP = ROOT / "agents" / "setup" / "agent-setup.sh"


def git(path, *args):
    result = subprocess.run(["git", "-C", str(path), *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


class PrePushProductTests(unittest.TestCase):
    def test_rejects_push_targeting_refs_heads_main(self):
        for local_ref in ("refs/heads/main", "HEAD", "refs/heads/agent/builder2/issue-29"):
            payload = f"{local_ref} 1111111111111111111111111111111111111111 refs/heads/main 0000000000000000000000000000000000000000\n"
            result = subprocess.run(["bash", "agents/pre-push-product.sh"], input=payload, text=True,
                                    capture_output=True, cwd=ROOT)
            self.assertNotEqual(result.returncode, 0, msg=payload)
            self.assertIn("refs/heads/main", result.stderr)

    def test_rejects_non_main_default_branch(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            git(repo, "init", "-b", "trunk")
            (repo / "agents").mkdir()
            (repo / "agents" / "pre-push-product.sh").write_bytes(HOOK.read_bytes())
            (repo / "README.md").write_text("base\n", encoding="utf-8")
            git(repo, "add", ".")
            git(repo, "-c", "user.name=Factory Setup", "-c", "user.email=setup@example.invalid",
                "commit", "-m", "base")
            git(repo, "update-ref", "refs/remotes/origin/trunk", git(repo, "rev-parse", "HEAD"))
            git(repo, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk")
            head = git(repo, "rev-parse", "HEAD")
            payload = f"HEAD {head} refs/heads/trunk {'0' * 40}\n"
            result = subprocess.run(["bash", "agents/pre-push-product.sh"], input=payload, text=True,
                                    capture_output=True, cwd=repo)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("refs/heads/trunk", result.stderr)

    def test_preserves_generated_file_check(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            git(repo, "init", "-b", "main")
            (repo / "README.md").write_text("base\n", encoding="utf-8")
            git(repo, "add", "README.md")
            git(repo, "-c", "user.name=Factory Setup", "-c", "user.email=setup@example.invalid",
                "commit", "-m", "base")
            git(repo, "update-ref", "refs/remotes/origin/main", git(repo, "rev-parse", "HEAD"))
            git(repo, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
            (repo / "agents").mkdir()
            (repo / "agents" / "pre-push-product.sh").write_bytes(HOOK.read_bytes())
            (repo / "agents" / "check-generated-history.sh").write_bytes(
                (ROOT / "agents" / "check-generated-history.sh").read_bytes())
            git(repo, "switch", "-c", "agent/builder1/issue-1")
            (repo / "node_modules").mkdir()
            (repo / "node_modules" / "generated").write_text("x\n", encoding="utf-8")
            git(repo, "add", "node_modules")
            git(repo, "-c", "user.name=Factory Builder 1",
                "-c", "user.email=builder1@users.noreply.github.com",
                "commit", "-m", "generated")
            head = git(repo, "rev-parse", "HEAD")
            payload = f"refs/heads/agent/builder1/issue-1 {head} refs/heads/agent/builder1/issue-1 0000000000000000000000000000000000000000\n"
            result = subprocess.run(["bash", "agents/pre-push-product.sh"], input=payload, text=True,
                                    capture_output=True, cwd=repo)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("generated files", result.stderr)


class AgentSetupTests(unittest.TestCase):
    def test_installs_pre_push_hook_with_mode_0700(self):
        text = SETUP.read_text(encoding="utf-8")
        self.assertIn('install -m 700 "$repo_dir/agents/pre-push-product.sh" "$repo_dir/.git/hooks/pre-push"',
                      text)
        self.assertIn('mkdir -p "$repo_dir/.git/hooks"', text)


if __name__ == "__main__":
    unittest.main()
