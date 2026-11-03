#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
gh auth status >/dev/null
repo="$(gh repo view --json nameWithOwner,isPrivate,defaultBranchRef)"
slug="$(jq -r .nameWithOwner <<< "$repo")"
branch="$(jq -r .defaultBranchRef.name <<< "$repo")"
payload="$(mktemp)"
trap 'rm -f "$payload"' EXIT
jq -n '{
  required_status_checks: {strict: true, contexts: ["verify", "factory-gates"]},
  enforce_admins: true,
  required_pull_request_reviews: {required_approving_review_count: 0, dismiss_stale_reviews: true},
  restrictions: null,
  required_conversation_resolution: true,
  allow_force_pushes: false,
  allow_deletions: false
}' > "$payload"

if ! gh api --method PUT "repos/$slug/branches/$branch/protection" --input "$payload" >/dev/null; then
  if [[ "$(jq -r .isPrivate <<< "$repo")" == true ]]; then
    echo 'Branch protection failed. GitHub Free supports protected branches on public repos; private repos need an eligible paid plan. The repo remains unprotected.' >&2
  else
    echo 'Branch protection failed. Check repository admin permission and the GitHub API response. The repo remains unprotected.' >&2
  fi
  exit 1
fi

state="$(gh api "repos/$slug/branches/$branch/protection")"
jq -e '
  (.required_status_checks.contexts | index("verify") != null and index("factory-gates") != null) and
  (.required_pull_request_reviews != null) and
  (.required_pull_request_reviews.required_approving_review_count == 0) and
  .enforce_admins.enabled and
  (.allow_force_pushes.enabled == false) and
  (.allow_deletions.enabled == false)
' <<< "$state" >/dev/null || { echo 'Branch protection response did not confirm all expected rules.' >&2; exit 1; }
printf 'Protected %s/%s: PR, verify, and factory-gates required; admins included; force pushes blocked.\n' "$slug" "$branch"
