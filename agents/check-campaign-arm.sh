#!/usr/bin/env bash
set -Eeuo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/agents/product-repository.sh"
config="$HOME/.config/briefing-agents"
[[ -f "$config/queue-armed" ]] || exit 0
campaign="$(cat "$config/queue-armed")"
selected="$(cat "$config/spec-path" 2>/dev/null || true)"
active="$(cat "$config/campaign-label" 2>/dev/null || true)"
actual_hash="$(sha256sum "$repo_dir/$selected" 2>/dev/null | cut -d' ' -f1 || true)"
expected_hash="$(cat "$config/spec-sha256" 2>/dev/null || true)"
[[ -n "$expected_hash" ]] || expected_hash="${campaign#product:}"
if [[ "$selected" != /* && "$selected" != ../* && "$selected" != */../* \
      && -f "$repo_dir/$selected" && "$active" == "$campaign" \
      && "${actual_hash:0:${#expected_hash}}" == "$expected_hash" ]]; then
  if [[ -f "$config/repo-slug" ]]; then
    selected_slug="$(factory_product_slug_from_spec "$repo_dir/$selected")"
    stored_slug="$(cat "$config/repo-slug")"
    [[ "${selected_slug,,}" == "${stored_slug,,}" ]] || {
      rm -f -- "$config/queue-armed"
      echo 'The active spec repository changed; queue disarmed.' >&2
      exit 0
    }
  fi
  exit 0
fi
rm -f -- "$config/queue-armed"
echo 'The active spec changed or disappeared; queue disarmed.' >&2
