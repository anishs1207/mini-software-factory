#!/usr/bin/env python3
"""Prepare a new OCI VM during terraform apply without putting secrets in state."""

import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SECRETS = ROOT / "agents" / "secrets.env"
REQUIRED_SECRETS = (
    "OLLAMA_API_KEY",
    "OPENROUTER_API_KEY",
    "OPENCLAW_FALLBACK_MODEL",
    "HERMES_FALLBACK_MODEL",
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
    for command in ("git", "ssh", "scp"):
        if not shutil.which(command):
            raise RuntimeError(f"{command} is required on the Terraform machine")
    key = Path(os.environ.get("BRIEFING_SSH_PRIVATE_KEY", "")).expanduser()
    if not key.is_file():
        raise RuntimeError("Set ssh_private_key_path to an existing local SSH private key")
    if not SECRETS.is_file():
        raise RuntimeError("Create local agents/secrets.env from agents/.env.sample before terraform apply")
    values = secret_values(SECRETS)
    missing = [name for name in REQUIRED_SECRETS
               if not values.get(name) or "replace" in values[name].lower()]
    if missing:
        raise RuntimeError("Fill these agents/secrets.env entries: " + ", ".join(missing))
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
    return key.resolve(), clone_url, revision


def ssh_options(key):
    return ["-i", str(key), "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10"]


def remote_script(target, options, script, *args):
    command = "bash -se -- " + " ".join(shlex.quote(arg) for arg in args)
    run(["ssh", *options, target, command], input=script)


def bootstrap():
    key, clone_url, revision = preflight()
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
    run(["scp", *options, "secrets.env", target + ":briefing-repo/agents/secrets.env"], cwd=SECRETS.parent)
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
[[ "$(git rev-parse HEAD)" == "$expected_revision" ]] || {
  echo 'The VM checkout does not match the committed local default branch.' >&2
  exit 1
}
if [[ ! -f "$HOME/.config/briefing-agents/setup-complete" ]]; then
  bash agents/setup/agent-setup.sh
  touch "$HOME/.config/briefing-agents/setup-complete"
fi
gh auth status >/dev/null
bash agents/enable-queue.sh
if [[ ! -f "$HOME/.config/briefing-agents/manager-started" ]]; then
  bash agents/dispatch.sh manager
  touch "$HOME/.config/briefing-agents/manager-started"
fi
""", clone_url, revision)
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
