#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
credentials="$HOME/.config/briefing-agents/credentials.env"
[[ -f "$credentials" ]] || { echo 'Run the VM agent bootstrap first.' >&2; exit 1; }
set -a
source "$credentials"
set +a
export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
mkdir -p "$HOME/.cache"
exec 9>"$HOME/.cache/briefing-agent.lock"
flock -n 9 || { echo 'Another agent is using the single-request model tier; try again shortly.' >&2; exit 1; }
exec hermes -p manager chat
