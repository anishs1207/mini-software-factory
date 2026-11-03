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
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SECRETS = next((path for path in (ROOT / "agents" / "secrets.env", ROOT / "agents" / ".env")
               if path.is_file()), ROOT / "agents" / "secrets.env")
REQUIRED_SECRETS = (
    "OLLAMA_API_KEY",
    "OPENROUTER_API_KEY",
    "GH_TOKEN",
)
EXPECTED_REPOSITORY = "anishs1207/confer-assignment"


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def github_api(path, token, method="GET", payload=None):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        "https://api.github.com/" + path,
        data=body,
        method=method,
        headers={"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "software-factory-bootstrap",
                 "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"GitHub API {method} {path} failed (HTTP {error.code}); check GH_TOKEN permissions") from None


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
    for name in ("OPENROUTER_REASONING_MODEL",):
        if name in values and (not values[name].endswith(":free") or "replace" in values[name].lower()):
            raise RuntimeError(name + " must name an OpenRouter :free model")


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
    for command in ("git", "ssh", "scp", "aws"):
        if not shutil.which(command):
            raise RuntimeError(f"{command} is required on the Terraform machine")
    key = Path(os.environ.get("FACTORY_SSH_PRIVATE_KEY", "")).expanduser()
    if not key.is_file():
        raise RuntimeError("Set ssh_private_key_path to an existing local SSH private key")
    if not SECRETS.is_file():
        raise RuntimeError("Create local agents/secrets.env or agents/.env from agents/.env.sample before terraform apply")
    values = secret_values(SECRETS)
    validate_secrets(values)
    if git("status", "--porcelain"):
        raise RuntimeError("Commit all repository changes before terraform apply so the VM clones the same revision")
    branch = git("branch", "--show-current")
    if not branch:
        raise RuntimeError("Check out the repository default branch before terraform apply")
    origin = git("remote", "get-url", "origin")
    clone_url = https_clone_url(origin)
    if clone_url.removeprefix("https://github.com/").removesuffix(".git").lower() != EXPECTED_REPOSITORY:
        raise RuntimeError("origin must be https://github.com/" + EXPECTED_REPOSITORY)
    slug = clone_url.removeprefix("https://github.com/").removesuffix(".git")
    repo = github_api("repos/" + slug, values["GH_TOKEN"])
    default_branch = repo.get("default_branch")
    if branch != default_branch:
        raise RuntimeError("Apply from the published default branch, not a feature branch")
    revision = git("rev-parse", "HEAD")
    remote_revision = github_api(f"repos/{slug}/git/ref/heads/{branch}", values["GH_TOKEN"])["object"]["sha"]
    if revision != remote_revision:
        raise RuntimeError("Push the current default-branch commit to origin before terraform apply")
    profile = os.environ.get("FACTORY_AWS_PROFILE", "default")
    identity = json.loads(run(["aws", "sts", "get-caller-identity", "--profile", profile,
                               "--output", "json"], capture_output=True).stdout)
    print("AWS account for EC2 apply: " + identity["Account"], flush=True)
    protect_repository(clone_url, branch, values["GH_TOKEN"])
    return key.resolve(), clone_url, revision


def protect_repository(clone_url, branch, token):
    """Require server-side gates before any automated PR can be merged."""
    slug = clone_url.removeprefix("https://github.com/").removesuffix(".git")
    repo = github_api(f"repos/{slug}", token)
    if repo.get("full_name", "").lower() != slug.lower() or repo.get("default_branch") != branch:
        raise RuntimeError("GH_TOKEN points to a different repository or default branch")
    try:
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
        github_api(f"repos/{slug}/branches/{branch}/protection", token, method="PUT", payload=payload)
        state = github_api(f"repos/{slug}/branches/{branch}/protection", token)
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
    except RuntimeError as error:
        raise RuntimeError("GH_TOKEN needs repository admin permission to configure branch protection "
                           "(public repo on GitHub Free): " + str(error)) from None


def ssh_options(key):
    return ["-i", str(key), "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10"]


def remote_script(target, options, script, *args):
    command = "bash -se -- " + " ".join(shlex.quote(arg) for arg in args)
    run(["ssh", *options, target, command], input=script)


def bootstrap():
    key, clone_url, revision = preflight()
    host = os.environ.get("FACTORY_VM_IP", "")
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
git remote set-url origin "$repo_url"
if [[ "$(git rev-parse HEAD)" != "$expected_revision" ]]; then
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || {
    echo 'The VM checkout has tracked local changes; inspect them before updating the factory.' >&2
    exit 1
  }
  git fetch --no-tags origin
  git merge --ff-only "$expected_revision"
fi
[[ "$(git rev-parse HEAD)" == "$expected_revision" ]] || {
  echo 'The VM checkout does not match the committed local default branch.' >&2
  exit 1
}
mkdir -p "$HOME/.config/briefing-agents"
if [[ ! -f "$HOME/.config/briefing-agents/setup-revision" ]] \
  || [[ "$(cat "$HOME/.config/briefing-agents/setup-revision")" != "$expected_revision" ]]; then
  bash agents/setup/agent-setup.sh
  printf '%s\n' "$expected_revision" > "$HOME/.config/briefing-agents/setup-revision"
fi
gh auth status >/dev/null
bash agents/check-campaign-arm.sh
bash agents/enable-queue.sh
""", clone_url, revision)
    print("Agent factory installed. Write spec.md on the VM, then tell the manager: implement ./spec.md", flush=True)
    if os.environ.get("FACTORY_NO_AUTO_CHAT") == "1":
        return
    command = ["ssh", "-tt", *options, target,
               "cd ~/briefing-repo && bash agents/manager-chat.sh"]
    if sys.platform == "win32":
        subprocess.Popen(command, creationflags=subprocess.CREATE_NEW_CONSOLE)
    elif shutil.which("x-terminal-emulator"):
        subprocess.Popen(["x-terminal-emulator", "-e", *command])
    else:
        print("Open manager with: " + " ".join(command), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--preflight", action="store_true")
    action.add_argument("--bootstrap", action="store_true")
    args = parser.parse_args()
    try:
        if args.preflight:
            preflight()
            print("Bootstrap preflight passed: published repo, local secrets, SSH key, and tools are ready.")
        else:
            bootstrap()
    except (OSError, subprocess.CalledProcessError, RuntimeError, ValueError) as error:
        print("Bootstrap failed: " + str(error), file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
