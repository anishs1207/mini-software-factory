#!/usr/bin/env python3
"""Exercise dispatch identity configuration without running agents."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
DISPATCH = ROOT / "agents" / "dispatch.sh"


class DispatchIdentityTests(unittest.TestCase):
    def test_sets_explicit_factory_manager_identity(self):
        text = DISPATCH.read_text(encoding="utf-8")
        self.assertIn("GIT_AUTHOR_NAME='Factory Manager'", text)
        self.assertIn("GIT_COMMITTER_NAME='Factory Manager'", text)
        self.assertIn("manager@users.noreply.github.com", text)

    def test_sets_explicit_builder_identities(self):
        text = DISPATCH.read_text(encoding="utf-8")
        self.assertIn("GIT_AUTHOR_NAME='Factory Builder 1'", text)
        self.assertIn("GIT_COMMITTER_NAME='Factory Builder 1'", text)
        self.assertIn("GIT_AUTHOR_NAME='Factory Builder 2'", text)
        self.assertIn("GIT_COMMITTER_NAME='Factory Builder 2'", text)

    def test_sets_builder_worktree_local_git_identity(self):
        text = DISPATCH.read_text(encoding="utf-8")
        self.assertIn('git -C "$work_dir" config user.name "Factory Builder ${role#builder}"', text)
        self.assertIn('git -C "$work_dir" config user.email "${role}@users.noreply.github.com"', text)

    def test_resets_shared_repository_default_identity(self):
        text = DISPATCH.read_text(encoding="utf-8")
        self.assertIn('git config --local --unset user.name || true', text)
        self.assertIn('git config --local --unset user.email || true', text)


if __name__ == "__main__":
    unittest.main()
