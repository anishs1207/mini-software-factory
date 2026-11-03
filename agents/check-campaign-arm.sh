#!/usr/bin/env bash
set -Eeuo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$HOME/.config/briefing-agents"
[[ -f "$config/queue-armed" ]] || exit 0
campaign="$(cat "$config/queue-armed")"
selected="$(cat "$config/spec-path" 2>/dev/null || true)"
active="$(cat "$config/campaign-label" 2>/dev/null || true)"
if [[ "$selected" != /* && "$selected" != ../* && "$selected" != */../* \
      && -f "$repo_dir/$selected" && "$active" == "$campaign" \
      && "product:$(sha256sum "$repo_dir/$selected" | cut -c1-12)" == "$campaign" ]]; then
  exit 0
fi
rm -f -- "$config/queue-armed"
echo 'The active spec changed or disappeared; queue disarmed.' >&2
