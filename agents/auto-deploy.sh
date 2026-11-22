#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${FACTORY_AUTODEPLOY_REPO_DIR:-}" ]]; then
  product_dir="$FACTORY_AUTODEPLOY_REPO_DIR"
else
  source "$repo_dir/agents/product-repository.sh"
  factory_product_context "$repo_dir"
fi
release_root="${FACTORY_RELEASE_ROOT:-/home/ubuntu/factory-product}"
state_dir="${FACTORY_AUTODEPLOY_STATE_DIR:-$HOME/.local/state/factory-autodeploy}"
lock_file="${FACTORY_AUTODEPLOY_LOCK_FILE:-$HOME/.cache/factory-autodeploy.lock}"
export PATH="${FACTORY_AUTODEPLOY_BIN_DIR:+$FACTORY_AUTODEPLOY_BIN_DIR:}$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

mkdir -p "$state_dir" "$(dirname "$lock_file")"
chmod 700 "$state_dir"
exec 9>"$lock_file"
flock -n 9 || { echo 'Another auto-deploy check is running.'; exit 0; }
cd "$product_dir"

repo_slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
default_branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
git fetch --quiet --no-tags origin "$default_branch"
target="$(git rev-parse "origin/$default_branch")"
if [[ ! -L "$release_root/current" && -z "${FACTORY_AUTODEPLOY_CURRENT_OVERRIDE:-}" ]]; then
  echo 'No product release is installed yet; waiting for initial deployment.'
  exit 0
fi
current="${FACTORY_AUTODEPLOY_CURRENT_OVERRIDE:-$(basename "$(readlink -f "$release_root/current")")}"
[[ "$target" =~ ^[0-9a-f]{40}$ && "$current" =~ ^[0-9a-f]{40}$ ]] || {
  echo 'Invalid current or target revision.' >&2
  exit 1
}
if ! git cat-file -e "$current^{commit}" 2>/dev/null; then
  echo 'The live release belongs to another product repository; waiting for the first manual release of this product.'
  exit 0
fi
if [[ "$target" == "$current" ]]; then
  echo "Already live: $target"
  exit 0
fi
git merge-base --is-ancestor "$current" "$target" || {
  echo "Current release $current is not an ancestor of $target; manual inspection required." >&2
  exit 1
}

mapfile -t commits < <(git rev-list --first-parent --reverse "$current..$target")
for revision in "${commits[@]}"; do
  prs="$(gh api "repos/$repo_slug/commits/$revision/pulls?per_page=100")"
  pr="$(jq -cer --arg revision "$revision" '[.[] | select(.merged_at != null and .merge_commit_sha == $revision)] | first // empty' <<< "$prs")" || {
    echo "Unreviewed direct main commit $revision; automatic deployment refused." >&2
    exit 1
  }
  head="$(jq -r .head.sha <<< "$pr")"
  number="$(jq -r .number <<< "$pr")"
  statuses="$(gh api "repos/$repo_slug/commits/$head/status")"
  gate_state="$(jq -r '[.statuses[] | select(.context == "factory-gates")][0].state // "missing"' <<< "$statuses")"
  if [[ "$gate_state" != success ]]; then
    # Factory-only PRs can lack a completed product reviewer/tester status.
    # They still require a human PR merge and the GitHub Actions verify check below.
    factory_only=false
    if [[ "$product_dir" == "$repo_dir" || -n "${FACTORY_AUTODEPLOY_REPO_DIR:-}" ]] &&
      git diff --name-only "$revision^1" "$revision" | bash "$repo_dir/agents/product-paths.sh"; then
      factory_only=true
    fi
    if [[ "$factory_only" != true ]]; then
      echo "PR #$number lacks a successful factory-gates status at $head; waiting."
      exit 0
    fi
    echo "PR #$number is factory-only; requiring the verify check without factory-gates."
  fi
  checks="$(gh api "repos/$repo_slug/commits/$head/check-runs?per_page=100")"
  if ! jq -e 'any(.check_runs[]; .name == "verify" and .app.slug == "github-actions" and .status == "completed" and .conclusion == "success")' <<< "$checks" >/dev/null; then
    echo "PR #$number lacks a successful verify check at $head; waiting."
    exit 0
  fi
done

# Factory changes require valid PR and CI evidence but do not rebuild a product.
if [[ "$product_dir" == "$repo_dir" || -n "${FACTORY_AUTODEPLOY_REPO_DIR:-}" ]] &&
  git diff --name-only "$current" "$target" | bash "$repo_dir/agents/product-paths.sh"; then
  echo "No product changes since live revision $current; deployment not needed."
  exit 0
fi
if ! git cat-file -e "$target:product-service.sh" 2>/dev/null; then
  echo 'No VM service adapter in target revision; deployment not applicable.'
  exit 0
fi

if [[ "${FACTORY_AUTODEPLOY_DRY_RUN:-0}" == 1 ]]; then
  echo "Eligible for deployment: $target after ${#commits[@]} gated main commit(s)."
  exit 0
fi

attempt_file="$state_dir/attempt"
attempts=0
last_attempt=0
last_sha=''
if [[ -f "$attempt_file" ]]; then
  read -r last_sha attempts last_attempt < "$attempt_file" || true
fi
now="$(date +%s)"
if [[ "$last_sha" == "$target" ]]; then
  if (( attempts >= 3 )); then
    echo "Deployment of $target failed three times; waiting for a new commit." >&2
    exit 0
  fi
  if (( now - last_attempt < 900 )); then
    echo "Deployment of $target is in its 15-minute retry cooldown."
    exit 0
  fi
else
  attempts=0
fi
printf '%s %s %s\n' "$target" "$((attempts + 1))" "$now" > "$attempt_file"

deployment_status() {
  local state="$1" description="$2"
  gh api --method POST "repos/$repo_slug/statuses/$target" \
    -f state="$state" -f context=auto-deploy -f description="$description" \
    -f target_url="https://github.com/$repo_slug/commit/$target" >/dev/null || true
}

deployment_status pending "Deploying merged revision $target"
echo "Deploying $target after ${#commits[@]} gated main commit(s)."
if bash "$repo_dir/agents/release-product.sh" deploy "$target"; then
  rm -f -- "$attempt_file"
  deployment_status success "Live revision $target passed product smoke checks"
  echo "Deployed and verified $target"
  exit 0
fi

echo "Deployment or verification failed for $target." >&2
if [[ "$(basename "$(readlink -f "$release_root/current")")" == "$target" ]]; then
  bash "$repo_dir/agents/release-product.sh" rollback || true
fi
deployment_status failure "Deploy or live verification failed; previous release restored"
exit 1
