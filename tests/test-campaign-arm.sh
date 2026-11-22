#!/usr/bin/env bash
set -Eeuo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$repo_dir/.local-evidence"
scratch="$(mktemp -d "$repo_dir/.local-evidence/test-campaign-arm.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
export HOME="$scratch/home"
config="$HOME/.config/briefing-agents"
mkdir -p "$config"
printf '# Product A\n' > "$scratch/spec.md"
relative="${scratch#"$repo_dir"/}/spec.md"
campaign="product:$(sha256sum "$scratch/spec.md" | cut -c1-12)"
printf '%s\n' "$relative" > "$config/spec-path"
printf '%s\n' "$campaign" > "$config/campaign-label"
printf '%s\n' "$campaign" > "$config/queue-armed"
bash "$repo_dir/agents/check-campaign-arm.sh"
[[ -f "$config/queue-armed" ]]
printf '# Product B\n' > "$scratch/spec.md"
bash "$repo_dir/agents/check-campaign-arm.sh"
[[ ! -f "$config/queue-armed" ]]
echo 'Rebootstrap preserves a matching campaign and disarms a changed spec.'
