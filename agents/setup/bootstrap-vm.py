#!/usr/bin/env python3
"""Prepare a new AWS EC2 VM during terraform apply without putting secrets in state."""

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SECRETS = next((path for path in (ROOT / "agents" / "secrets.env", ROOT / "agents" / ".env")
               if path.is_file()), ROOT / "agents" / "secrets.env")
REQUIRED_SECRETS = (
    "OLLAMA_API_KEY",
    "OPENROUTER_API_KEY",
    "GH_TOKEN",
)


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def git(*args):
    return run(["git", "-C", str(ROOT), *args], capture_output=True).stdout.strip()


def secret_values(path):
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if not match:
            continue
        value = match.group(2).split(" #", 1)[0].strip().strip("'\"")
        values[match.group(1)] = value
    return values


def validate_secrets(values):
    missing = [name for name in REQUIRED_SECRETS
               if not values.get(name) or "replace" in values[name].lower()]
    if missing:
        raise RuntimeError("Fill these agents/secrets.env entries: " + ", ".join(missing))
    for name in ("OPENROUTER_REASONING_MODEL", "HERMES_FALLBACK_MODEL"):
        if name in values and (not values[name].endswith(":free") or "replace" in values[name].lower()):
            raise RuntimeError(name + " must name an OpenRouter :free model")
    name = "OPENCLAW_FALLBACK_MODEL"
    if name in values and (not values[name].startswith("openrouter/") or
                           not values[name].endswith(":free") or "replace" in values[name].lower()):
        raise RuntimeError(name + " must name an openrouter/*:free model")


def tracked_spec_path():
    requested = Path(os.environ.get("BRIEFING_SPEC_PATH", "spec/PRODUCT_SPEC.md"))
    if requested.is_absolute():
        raise RuntimeError("spec_path must be relative to the repository")
    path = (ROOT / requested).resolve()
    if not path.is_relative_to(ROOT.resolve()) or not path.is_file():
        raise RuntimeError("spec_path must name a file inside this repository")
    relative = path.relative_to(ROOT).as_posix()
    try:
        git("ls-files", "--error-unmatch", relative)
    except subprocess.CalledProcessError:
        raise RuntimeError("Commit spec_path before terraform apply: " + relative) from None
    return relative


def https_clone_url(origin):
    if origin.startswith("git@github.com:"):
        path = origin[len("git@github.com:"):]
    elif origin.startswith("https://github.com/"):
        path = origin[len("https://github.com/"):]
    else:
        raise ValueError("origin must be a github.com SSH or HTTPS repository URL")
    if "@" in path or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?", path):
        raise ValueError("origin must not contain credentials or unexpected URL characters")
    return "https://github.com/" + path


def preflight():
    for command in ("git", "ssh", "scp", "gh", "aws"):
        if not shutil.which(command):
            raise RuntimeError(f"{command} is required on the Terraform machine")
    key = Path(os.environ.get("BRIEFING_SSH_PRIVATE_KEY", "")).expanduser()
    if not key.is_file():
        raise RuntimeError("Set ssh_private_key_path to an existing local SSH private key")
    if not SECRETS.is_file():
        raise RuntimeError("Create local agents/secrets.env or agents/.env from agents/.env.sample before terraform apply")
    values = secret_values(SECRETS)
    validate_secrets(values)
    spec_path = tracked_spec_path()
    if git("status", "--porcelain"):
        raise RuntimeError("Commit all repository changes before terraform apply so the VM clones the same revision")
    branch = git("branch", "--show-current")
    if not branch:
        raise RuntimeError("Check out the repository default branch before terraform apply")
    origin = git("remote", "get-url", "origin")
    clone_url = https_clone_url(origin)
    default_line = next((line for line in git("ls-remote", "--symref", "origin", "HEAD").splitlines()
                         if line.startswith("ref: refs/heads/") and line.endswith("\tHEAD")), "")
    default_branch = default_line.removeprefix("ref: refs/heads/").removesuffix("\tHEAD")
    if branch != default_branch:
        raise RuntimeError("Apply from the published default branch, not a feature branch")
    revision = git("rev-parse", "HEAD")
    remote_ref = git("ls-remote", "origin", "refs/heads/" + branch)
    remote_revision = remote_ref.split()[0] if remote_ref else ""
    if revision != remote_revision:
        raise RuntimeError("Push the current default-branch commit to origin before terraform apply")
    profile = os.environ.get("BRIEFING_AWS_PROFILE", "default")
    identity = json.loads(run(["aws", "sts", "get-caller-identity", "--profile", profile,
                               "--output", "json"], capture_output=True).stdout)
    print("AWS account for EC2 apply: " + identity["Account"], flush=True)
    protect_repository(clone_url, branch)
    return key.resolve(), clone_url, revision, spec_path


def protect_repository(clone_url, branch):
    """Require server-side gates before any automated PR can be merged."""
    slug = clone_url.removeprefix("https://github.com/").removesuffix(".git")
    try:
        run(["gh", "auth", "status"], capture_output=True)
        repo = json.loads(run(["gh", "repo", "view", slug, "--json", "nameWithOwner,defaultBranchRef"],
                              capture_output=True).stdout)
        if repo["nameWithOwner"].lower() != slug.lower() or repo["defaultBranchRef"]["name"] != branch:
            raise RuntimeError("Local GitHub CLI points to a different repository or default branch")
        payload = {
            "required_status_checks": {"strict": True, "contexts": ["verify", "factory-gates"]},
            "enforce_admins": True,
            "required_pull_request_reviews": {"required_approving_review_count": 0,
                                                "dismiss_stale_reviews": True},
            "restrictions": None,
            "required_conversation_resolution": True,
            "allow_force_pushes": False,
            "allow_deletions": False,
        }
        run(["gh", "api", "--method", "PUT", f"repos/{slug}/branches/{branch}/protection", "--input", "-"],
            input=json.dumps(payload), capture_output=True)
        state = json.loads(run(["gh", "api", f"repos/{slug}/branches/{branch}/protection"],
                               capture_output=True).stdout)
        checks = state.get("required_status_checks") or {}
        reviews = state.get("required_pull_request_reviews") or {}
        if not (set(checks.get("contexts") or []) >= {"verify", "factory-gates"}
                and checks.get("strict") is True
                and "required_approving_review_count" in reviews
                and reviews["required_approving_review_count"] == 0
                and reviews.get("dismiss_stale_reviews") is True
                and (state.get("enforce_admins") or {}).get("enabled")
                and (state.get("allow_force_pushes") or {}).get("enabled") is False
                and (state.get("allow_deletions") or {}).get("enabled") is False):
            raise RuntimeError("GitHub did not confirm required PRs, CI, and factory gates")
    except subprocess.CalledProcessError as error:
        raise RuntimeError("Configure local gh as the repository owner and enable branch protection "
                           "(public repo on the free plan) before apply: " +
                           (error.stderr or str(error)).strip()) from None


def ssh_options(key):
    return ["-i", str(key), "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10"]


def remote_script(target, options, script, *args):
    command = "bash -se -- " + " ".join(shlex.quote(arg) for arg in args)
    run(["ssh", *options, target, command], input=script)


def bootstrap():
    key, clone_url, revision, spec_path = preflight()
    spec_hash = os.environ.get("BRIEFING_SPEC_HASH", "")
    if not re.fullmatch(r"[0-9a-f]{64}", spec_hash):
        raise RuntimeError("Terraform did not supply the selected spec SHA-256")
    host = os.environ.get("BRIEFING_VM_IP", "")
    if not re.fullmatch(r"[0-9.]+", host):
        raise RuntimeError("Terraform did not supply a valid VM public IPv4 address")
    target = "ubuntu@" + host
    options = ssh_options(key)
    print("Waiting for VM SSH...", flush=True)
    for attempt in range(30):
        probe = subprocess.run(["ssh", *options, target, "true"], capture_output=True, text=True)
        if probe.returncode == 0:
            break
        if attempt == 29:
            raise RuntimeError("VM SSH was not reachable after five minutes; check subnet and SSH ingress")
        time.sleep(10)
    print("Installing GitHub CLI and cloning the published revision...", flush=True)
    remote_script(target, options, """set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y git gh
mkdir -p "$HOME/briefing-repo/agents"
""")
    run(["scp", *options, SECRETS.name, target + ":briefing-repo/agents/secrets.env"], cwd=SECRETS.parent)
    remote_script(target, options, """set -Eeuo pipefail
repo_url="$1"
expected_revision="$2"
spec_path="$3"
spec_hash="$4"
repo_dir="$HOME/briefing-repo"
chmod 600 "$repo_dir/agents/secrets.env"
set -a
source "$repo_dir/agents/secrets.env"
set +a
export GH_PROMPT_DISABLED=1
gh auth status >/dev/null
gh auth setup-git --hostname github.com --force >/dev/null
if [[ ! -d "$repo_dir/.git" ]]; then
  git clone "$repo_url" "$HOME/briefing-source"
  mv "$repo_dir/agents/secrets.env" "$HOME/briefing-source/agents/secrets.env"
  rmdir "$repo_dir/agents" "$repo_dir"
  mv "$HOME/briefing-source" "$repo_dir"
fi
cd "$repo_dir"
if [[ "$(git rev-parse HEAD)" != "$expected_revision" ]]; then
  [[ -z "$(git status --porcelain)" ]] || {
    echo 'The VM checkout has local changes; inspect them before updating the factory.' >&2
    exit 1
  }
  git fetch --no-tags origin
  git merge --ff-only "$expected_revision"
fi
[[ "$(git rev-parse HEAD)" == "$expected_revision" ]] || {
  echo 'The VM checkout does not match the committed local default branch.' >&2
  exit 1
}
[[ -f "$repo_dir/$spec_path" ]] || { echo 'Selected product spec is missing from the VM checkout.' >&2; exit 1; }
mkdir -p "$HOME/.config/briefing-agents"
printf '%s\n' "$spec_path" > "$HOME/.config/briefing-agents/spec-path"
if [[ ! -f "$HOME/.config/briefing-agents/setup-complete" ]]; then
  bash agents/setup/agent-setup.sh
  touch "$HOME/.config/briefing-agents/setup-complete"
fi
gh auth status >/dev/null
bash agents/enable-queue.sh
if [[ ! -f "$HOME/.config/briefing-agents/manager-started" ]] \
  || [[ "$(cat "$HOME/.config/briefing-agents/manager-started")" != "$spec_path $spec_hash" ]]; then
  mkdir -p .local-evidence/dispatch-logs
  chmod 700 .local-evidence .local-evidence/dispatch-logs
  bash agents/dispatch.sh manager 2>&1 | tee .local-evidence/dispatch-logs/manager-startup.log
  bot_login="$(gh api user --jq .login)"
  issue_data="$(gh issue list --state all --limit 100 --json author,labels,title)"
  if ! jq -e --arg bot "$bot_login" '
    [.[] | select(.author.login == $bot)] as $tickets |
    ($tickets | length) >= 7 and
    any($tickets[]; any(.labels[]?.name; . == "agent:ingest")) and
    any($tickets[]; any(.labels[]?.name; . == "agent:page")) and
    any($tickets[]; any(.labels[]?.name; . == "briefing:ready" or . == "briefing:waiting" or . == "briefing:needs-manager"))
  ' <<< "$issue_data" >/dev/null; then
    echo 'Manager ended without a complete inspectable ticket trail; retry apply after inspecting the manager log.' >&2
    exit 1
  fi
  printf '%s %s\n' "$spec_path" "$spec_hash" > "$HOME/.config/briefing-agents/manager-started"
fi
""", clone_url, revision, spec_path, spec_hash)
    print("Agent factory installed. The manager has been dispatched; inspect GitHub Issues and the VM timer.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--preflight", action="store_true")
    action.add_argument("--bootstrap", action="store_true")
    args = parser.parse_args()
    try:
        if args.preflight:
            preflight()
            print("Bootstrap preflight passed: committed repo, local secrets, SSH key, and tools are ready.")
        else:
            bootstrap()
    except (OSError, subprocess.CalledProcessError, RuntimeError, ValueError) as error:
        print("Bootstrap failed: " + str(error), file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
