#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
dependent="${1:-}"
blocker="${2:-}"
[[ "$dependent" =~ ^[0-9]+$ && "$blocker" =~ ^[0-9]+$ && "$dependent" != "$blocker" ]] \
  || { echo 'Usage: agents/link-dependency.sh DEPENDENT_ISSUE BLOCKING_ISSUE' >&2; exit 2; }
repo_slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
campaign_label="$(cat "$HOME/.config/briefing-agents/campaign-label")"
for ticket in "$dependent" "$blocker"; do
  gh issue view "$ticket" --json labels --jq '.labels[].name' | grep -Fxq "$campaign_label" \
    || { echo "Issue #$ticket is outside the active product campaign." >&2; exit 1; }
done
blocker_id="$(gh api "repos/$repo_slug/issues/$blocker" --jq .id)"
[[ "$blocker_id" =~ ^[0-9]+$ ]] || { echo 'Blocking issue has no numeric GitHub ID.' >&2; exit 1; }
gh api --method POST "repos/$repo_slug/issues/$dependent/dependencies/blocked_by" \
  -F "issue_id=$blocker_id" >/dev/null
current_labels="$(gh issue view "$dependent" --json labels --jq '.labels[].name')"
args=()
while IFS= read -r label; do
  [[ "$label" == factory:* ]] || continue
  args+=(--remove-label "$label")
done <<< "$current_labels"
gh issue edit "$dependent" "${args[@]}" --add-label factory:waiting >/dev/null
echo "Issue #$dependent waits for #$blocker."
