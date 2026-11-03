#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
[[ $# -eq 1 ]] || { echo 'Usage: bash agents/start-campaign.sh ./spec.md' >&2; exit 2; }
spec="$(realpath -e -- "$1")"
case "$spec" in
  "$repo_dir"/*) ;;
  *) echo 'The spec must be inside the VM repository.' >&2; exit 2 ;;
esac
[[ -f "$spec" && -s "$spec" && "$spec" == *.md ]] || { echo 'Provide a nonempty Markdown spec.' >&2; exit 2; }
relative="${spec#"$repo_dir"/}"
hash="$(sha256sum "$spec" | cut -d' ' -f1)"
config="$HOME/.config/briefing-agents"
mkdir -p "$config"
if [[ -f "$config/campaign-label" && "$(cat "$config/campaign-label")" != "product:${hash:0:12}" ]]; then
  active="$(gh issue list --state open --label "$(cat "$config/campaign-label")" --limit 1 --json number --jq 'length')"
  [[ "$active" == 0 ]] || { echo 'Finish or close the previous campaign before selecting a new spec.' >&2; exit 1; }
fi
printf '%s\n' "$relative" > "$config/spec-path"
printf 'product:%s\n' "${hash:0:12}" > "$config/campaign-label"
gh label create "product:${hash:0:12}" --force >/dev/null
printf 'product:%s\n' "${hash:0:12}" > "$config/queue-armed"
echo "Campaign product:${hash:0:12} uses $relative. Manager: create implementation issues now."
