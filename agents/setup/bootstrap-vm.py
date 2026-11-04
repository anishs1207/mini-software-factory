#!/usr/bin/env python3
"""Prepare a new Google Compute Engine VM during terraform apply without putting secrets in state."""

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
    for command in ("git", "ssh", "scp", "gcloud"):
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
    project = os.environ.get("FACTORY_GCP_PROJECT", "confer-assignment")
    active_project = run(["gcloud", "config", "get-value", "project"], capture_output=True).stdout.strip()
    if active_project != project:
        raise RuntimeError(f"gcloud active project is {active_project!r}; select {project!r}")
    run(["gcloud", "auth", "print-access-token"], capture_output=True)
    print("Google Cloud project for Compute Engine apply: " + project, flush=True)
    return key.resolve(), clone_url, revision, branch


def ssh_options(key):
    return ["-i", str(key), "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10"]


def remote_script(target, options, script, *args):
    command = "bash -se -- " + " ".join(shlex.quote(arg) for arg in args)
    payload = script.replace("\r\n", "\n").encode("utf-8")
    subprocess.run(["ssh", *options, target, command], input=payload, check=True)


def bootstrap():
    key, clone_url, revision, branch = preflight()
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
expected_branch="$3"
repo_dir="$HOME/briefing-repo"
sed -i 's/\r$//' "$repo_dir/agents/secrets.env"
chmod 600 "$repo_dir/agents/secrets.env"
set -a
source "$repo_dir/agents/secrets.env"
set +a
export GH_PROMPT_DISABLED=1
gh auth status >/dev/null
gh_login="$(gh api user -q .login)"
python3 - "$gh_login" <<'PY'
import os
from pathlib import Path
import sys

token = os.environ["GH_TOKEN"]
if not token or "\\n" in token or "\\r" in token:
    raise RuntimeError("Invalid GH_TOKEN")
config = Path.home() / ".config" / "gh"
config.mkdir(mode=0o700, parents=True, exist_ok=True)
config.chmod(0o700)
hosts = config / "hosts.yml"
hosts.write_text(
    f"github.com:\\n    oauth_token: {token}\\n    user: {sys.argv[1]}\\n    git_protocol: https\\n"
)
hosts.chmod(0o600)
PY
env -u GH_TOKEN -u GITHUB_TOKEN gh auth status >/dev/null
gh auth setup-git --hostname github.com --force >/dev/null
if [[ ! -d "$repo_dir/.git" ]]; then
  git clone "$repo_url" "$HOME/briefing-source"
  mv "$repo_dir/agents/secrets.env" "$HOME/briefing-source/agents/secrets.env"
  rmdir "$repo_dir/agents" "$repo_dir"
  mv "$HOME/briefing-source" "$repo_dir"
fi
cd "$repo_dir"
git remote set-url origin "$repo_url"
if [[ "$(git branch --show-current)" != "$expected_branch" ]]; then
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || {
    echo 'The VM checkout has tracked local changes; inspect them before switching branches.' >&2
    exit 1
  }
  git switch "$expected_branch"
fi
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
""", clone_url, revision, branch)
    resume_issue = os.environ.get("FACTORY_RESUME_ISSUE", "")
    if resume_issue:
        if not re.fullmatch(r"[1-9][0-9]*", resume_issue):
            raise RuntimeError("FACTORY_RESUME_ISSUE must be a positive issue number")
        local_spec = ROOT / "spec" / "spec.md"
        if not local_spec.is_file():
            raise RuntimeError("Cannot resume the campaign: local spec/spec.md is missing")
        run(["scp", *options, str(local_spec), target + ":briefing-repo/spec.md"])
        remote_script(target, options, """set -Eeuo pipefail
cd "$HOME/briefing-repo"
bash agents/resume-campaign.sh "$1"
bash agents/check-campaign-arm.sh
bash agents/enable-queue.sh
""", resume_issue)
    else:
        remote_script(target, options, """set -Eeuo pipefail
cd "$HOME/briefing-repo"
bash agents/check-campaign-arm.sh
bash agents/enable-queue.sh
""")
    print("Agent factory installed. Manager chat and issue queue are ready.", flush=True)
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
