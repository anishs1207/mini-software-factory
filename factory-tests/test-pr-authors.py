#!/usr/bin/env python3
"""Exercise the PR head and agent-commit gate with local git repositories."""

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "agents" / "verify-pr-authors.py"
SPEC = importlib.util.spec_from_file_location("verify_pr_authors", SOURCE)
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


def git(path, *args):
    result = subprocess.run(["git", "-C", str(path), *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


class AuthorGateTests(unittest.TestCase):
    def test_agent_commits_match_pr_head_and_human_commit_is_rejected(self):
        scratch = ROOT / ".local-evidence" / "test-pr-authors"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            base = Path(directory)
            worktree = base / "source"
            subprocess.run(["git", "init", "-b", "main", str(worktree)], check=True, capture_output=True)
            (worktree / "README.md").write_text("base\n", encoding="utf-8")
            git(worktree, "add", "README.md")
            git(worktree, "-c", "user.name=Factory Setup", "-c", "user.email=setup@example.invalid",
                "commit", "-m", "base")
            git(worktree, "update-ref", "refs/remotes/origin/main", git(worktree, "rev-parse", "HEAD"))
            git(worktree, "switch", "-c", "agent/builder1/issue-1")
            (worktree / "product.txt").write_text("agent code\n", encoding="utf-8")
            git(worktree, "add", "product.txt")
            git(worktree, "-c", "user.name=Factory Builder 1",
                "-c", "user.email=builder1@users.noreply.github.com", "commit", "-m", "implement")
            first_head = git(worktree, "rev-parse", "HEAD")
            self.assertEqual(VERIFY.verify(worktree, first_head, "main", "builder1"), 1)
            with self.assertRaisesRegex(ValueError, "does not match"):
                VERIFY.verify(worktree, "0" * 40, "main", "builder1")
            (worktree / "product.txt").write_text("human edit\n", encoding="utf-8")
            git(worktree, "add", "product.txt")
            git(worktree, "-c", "user.name=Human", "-c", "user.email=human@example.invalid",
                "commit", "-m", "manual change")
            with self.assertRaisesRegex(ValueError, "not authored"):
                VERIFY.verify(worktree, git(worktree, "rev-parse", "HEAD"), "main", "builder1")


if __name__ == "__main__":
    unittest.main()
