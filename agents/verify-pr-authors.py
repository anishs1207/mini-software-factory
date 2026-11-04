#!/usr/bin/env python3
"""Verify a builder PR head and every PR-specific commit's author and committer."""

import argparse
import re
import subprocess
import sys
from pathlib import Path


AUTHORS = {
    "builder1": ("Factory Builder 1", "builder1@users.noreply.github.com"),
    "builder2": ("Factory Builder 2", "builder2@users.noreply.github.com"),
}


def git(worktree: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(worktree), *args], check=True,
                          capture_output=True, text=True).stdout.strip()


def verify(worktree: Path, head: str, base_branch: str, builder: str) -> int:
    if builder not in AUTHORS or not re.fullmatch(r"[0-9a-fA-F]{40}", head):
        raise ValueError("Expected a known builder and a 40-character PR head SHA")
    if not re.fullmatch(r"[A-Za-z0-9._/-]+", base_branch) or base_branch.startswith("-"):
        raise ValueError("Invalid base branch")
    if git(worktree, "rev-parse", "HEAD") != head:
        raise ValueError("Local builder worktree does not match the PR head")
    base = git(worktree, "rev-parse", "--verify", f"refs/remotes/origin/{base_branch}")
    common = git(worktree, "merge-base", base, head)
    commits = git(worktree, "rev-list", f"{common}..{head}").splitlines()
    if not commits:
        raise ValueError("PR has no agent-authored product commit")
    expected_name, expected_email = AUTHORS[builder]
    for commit in commits:
        author = git(worktree, "show", "-s", "--format=%an%x00%ae%x00%cn%x00%ce", commit).split("\x00")
        if author[:2] != [expected_name, expected_email]:
            raise ValueError(f"Commit {commit[:12]} is not authored by {expected_name}")
        if author[2:] != [expected_name, expected_email]:
            raise ValueError(f"Commit {commit[:12]} is not committed by {expected_name}")
    return len(commits)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("worktree", type=Path)
    parser.add_argument("head")
    parser.add_argument("base_branch")
    parser.add_argument("builder", choices=AUTHORS)
    args = parser.parse_args()
    try:
        count = verify(args.worktree, args.head, args.base_branch, args.builder)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Agent authorship gate failed: {error}", file=sys.stderr)
        raise SystemExit(1) from None
    print(f"Verified {count} {args.builder} product commit(s) at PR head {args.head[:12]}.")


if __name__ == "__main__":
    main()
