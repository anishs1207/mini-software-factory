#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$repo_dir/agents/activity.py" report --usage-dir "$repo_dir/.local-evidence/usage"
