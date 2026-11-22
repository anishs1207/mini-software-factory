#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
source "$repo_dir/agents/product-repository.sh"
[[ $# -eq 1 ]] || { echo 'Usage: bash agents/start-campaign.sh ./spec.md' >&2; exit 2; }
spec="$(realpath -e -- "$1")"
case "$spec" in
  "$repo_dir"/*) ;;
  *) echo 'The spec must be inside the VM repository.' >&2; exit 2 ;;
esac
[[ -f "$spec" && -s "$spec" && "$spec" == *.md ]] || { echo 'Provide a nonempty Markdown spec.' >&2; exit 2; }
relative="${spec#"$repo_dir"/}"
hash="$(sha256sum "$spec" | cut -d' ' -f1)"
slug="$(factory_product_slug_from_spec "$spec")"
slug="$(gh repo view "$slug" --json nameWithOwner --jq .nameWithOwner)"
factory_slug="$(git remote get-url origin)"
factory_slug="${factory_slug#https://github.com/}"
factory_slug="${factory_slug#git@github.com:}"
factory_slug="${factory_slug%.git}"
[[ "${slug,,}" != "${factory_slug,,}" ]] || {
  echo 'The product repository must differ from the factory repository.' >&2; exit 1;
}
default_branch="$(gh repo view "$slug" --json defaultBranchRef --jq .defaultBranchRef.name)"
[[ -n "$default_branch" ]] || { echo "Initialize $slug with a default branch before starting a campaign." >&2; exit 1; }
config="$HOME/.config/briefing-agents"
mkdir -p "$config"
if [[ -f "$config/campaign-label" && "$(cat "$config/campaign-label")" != "product:${hash:0:12}" ]]; then
  if [[ -f "$config/repo-slug" ]]; then export GH_REPO="$(cat "$config/repo-slug")"; fi
  active="$(gh issue list --state open --label "$(cat "$config/campaign-label")" --limit 1 --json number --jq 'length')"
  [[ "$active" == 0 ]] || { echo 'Finish or close the previous campaign before selecting a new spec.' >&2; exit 1; }
fi
product_dir="$HOME/factory-products/$slug"
if [[ ! -d "$product_dir/.git" ]]; then
  mkdir -p "$(dirname "$product_dir")"
  gh repo clone "$slug" "$product_dir"
fi
origin="$(git -C "$product_dir" remote get-url origin)"
[[ "$origin" == "https://github.com/$slug" || "$origin" == "https://github.com/$slug.git" ||
   "$origin" == "git@github.com:$slug" || "$origin" == "git@github.com:$slug.git" ]] || {
  echo "The existing product checkout has an unexpected origin: $product_dir" >&2; exit 1;
}
git -C "$product_dir" fetch --no-tags origin "$default_branch"
export GH_REPO="$slug"
printf '%s\n' "$relative" > "$config/spec-path"
printf 'product:%s\n' "${hash:0:12}" > "$config/campaign-label"
printf '%s\n' "$hash" > "$config/spec-sha256"
printf '%s\n' "$slug" > "$config/repo-slug"
gh label create "product:${hash:0:12}" --force >/dev/null
gh repo set-default "$slug"
printf 'product:%s\n' "${hash:0:12}" > "$config/queue-armed"
echo "Campaign product:${hash:0:12} uses $relative in $slug. Manager: create implementation issues now."
