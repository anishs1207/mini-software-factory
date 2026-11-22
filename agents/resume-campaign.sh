#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/agents/product-repository.sh"
factory_product_context "$repo_dir"
cd "$product_dir"
issue="${1:-}"
[[ "$issue" =~ ^[1-9][0-9]*$ ]] || { echo 'Usage: bash agents/resume-campaign.sh ISSUE' >&2; exit 2; }
[[ -s "$repo_dir/spec.md" ]] || { echo 'Restore the campaign spec as spec.md in the factory checkout first.' >&2; exit 1; }

issue_json="$(gh issue view "$issue" --json state,labels,comments)"
[[ "$(jq -r .state <<< "$issue_json")" == OPEN ]] || { echo 'Recovery issue is not open.' >&2; exit 1; }
campaign="$(jq -r '[.labels[].name | select(startswith("product:"))] | first // empty' <<< "$issue_json")"
builder="$(jq -r '[.labels[].name | select(. == "agent:builder1" or . == "agent:builder2")] | first // empty' <<< "$issue_json")"
[[ "$campaign" =~ ^product:[0-9a-f]{12}$ && -n "$builder" ]] || { echo 'Issue lacks campaign or builder label.' >&2; exit 1; }
role="${builder#agent:}"
branch="agent/$role/issue-$issue"
pr_json="$(gh pr view "$branch" --json state,headRefOid,headRefName)"
head="$(jq -r .headRefOid <<< "$pr_json")"
jq -e --arg branch "$branch" '.state == "OPEN" and .headRefName == $branch and (.headRefOid | length == 40)' <<< "$pr_json" >/dev/null
trusted_actor="$(gh api user -q .login)"
jq -e --arg actor "$trusted_actor" --arg head "$head" \
  'any(.comments[]; .author.login == $actor and (.body | startswith("REVIEW: APPROVED")) and (.body | contains("Head: " + $head)))' \
  <<< "$issue_json" >/dev/null || { echo 'No reviewer approval for the current PR head.' >&2; exit 1; }

config="$HOME/.config/briefing-agents"
worktree_root="$HOME/.cache/briefing-worktrees"
if [[ "$product_dir" != "$repo_dir" ]]; then worktree_root="$worktree_root/${GH_REPO//\//_}"; fi
mkdir -p "$config" "$worktree_root"
hash="$(sha256sum "$repo_dir/spec.md" | cut -d' ' -f1)"
printf '%s\n' spec.md > "$config/spec-path"
printf '%s\n' "$campaign" > "$config/campaign-label"
printf '%s\n' "$hash" > "$config/spec-sha256"
printf '%s\n' "$campaign" > "$config/queue-armed"

work_dir="$worktree_root/$role-issue-$issue"
git fetch origin "$branch:refs/remotes/origin/$branch"
if [[ ! -d "$work_dir" ]]; then
  git worktree add -b "$branch" "$work_dir" "origin/$branch"
fi
[[ "$(git -C "$work_dir" rev-parse HEAD)" == "$head" ]] || { echo 'Recovered worktree does not match the PR head.' >&2; exit 1; }

if jq -e 'any(.labels[].name; . == "factory:in-progress")' <<< "$issue_json" >/dev/null; then
  gh issue edit "$issue" --remove-label factory:in-progress --add-label factory:test >/dev/null
elif ! jq -e 'any(.labels[].name; . == "factory:test")' <<< "$issue_json" >/dev/null; then
  echo 'Issue is not at the interrupted tester handoff.' >&2
  exit 1
fi
echo "Resumed $campaign: issue #$issue, PR head $head, next stage tester."
