#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
issue="${1:-}"
[[ "$issue" =~ ^[0-9]+$ ]] || { echo 'Usage: agents/merge-check.sh ISSUE_NUMBER' >&2; exit 2; }
gh auth status >/dev/null
repo_slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
source "$repo_dir/agents/queue-guards.sh"
if dependency_state "$issue"; then
  :
else
  result=$?
  if [[ "$result" -eq 1 ]]; then
    echo "Issue still waits for ${blocked_by[*]}." >&2
  else
    echo 'Could not verify GitHub issue dependencies.' >&2
  fi
  exit 1
fi
data="$(gh issue view "$issue" --json labels,comments)"
jq -e --arg campaign "$campaign_label" 'any(.labels[].name; . == $campaign)' <<< "$data" >/dev/null \
  || { echo 'Issue is outside the active product campaign.' >&2; exit 1; }
jq -e '[.labels[].name | select(startswith("factory:"))] == ["factory:merge-ready"]' <<< "$data" >/dev/null \
  || { echo 'Issue is not at the merge-ready gate.' >&2; exit 1; }
builder="$(jq -r '[.labels[].name | select(. == "agent:builder1" or . == "agent:builder2")] | if length == 1 then .[0] | split(":")[1] else empty end' <<< "$data")"
[[ -n "$builder" ]] || { echo 'Exactly one builder label is required.' >&2; exit 1; }
branch="agent/$builder/issue-$issue"
if pr_freshness "$branch"; then
  :
else
  result=$?
  if [[ "$result" -eq 1 ]]; then
    echo "$freshness_reason; return it to the builder before merging." >&2
  else
    echo 'Could not verify PR freshness against its base branch.' >&2
  fi
  exit 1
fi
changed_files="$(gh pr diff "$branch" --name-only)"
if grep -Eq '^(\.github/|agents/|factory-tests/|infra/|spec/|deliverables/|instructions-to-agent\.md$)' <<< "$changed_files"; then
  echo 'Builder PR modifies factory-owned files; inspect separately before merge.' >&2
  exit 1
fi
pr="$(gh pr view "$branch" --json state,url,headRefOid)"
jq -e '.state == "OPEN" and (.headRefOid | length == 40)' <<< "$pr" >/dev/null
head="$(jq -r .headRefOid <<< "$pr")"
base_branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
work_dir="$HOME/.cache/briefing-worktrees/$builder-issue-$issue"
git -C "$work_dir" fetch --no-tags origin "$base_branch" >/dev/null
python3 "$repo_dir/agents/verify-pr-authors.py" "$work_dir" "$head" "$base_branch" "$builder"
actor="$(gh api user -q .login)"
jq -e --arg actor "$actor" --arg head "$head" '
  ([.comments[] | select(.author.login == $actor and (.body | startswith("REVIEW:")))] | last | .body // "") as $review |
  ([.comments[] | select(.author.login == $actor and (.body | startswith("TEST:")))] | last | .body // "") as $test |
  ($review | startswith("REVIEW: APPROVED")) and (($review | split("\n") | index("Head: " + $head)) != null) and
  ($test | startswith("TEST: PASSED")) and (($test | split("\n") | index("Head: " + $head)) != null)
' <<< "$data" >/dev/null || { echo 'Review and test must both pass for the current PR head.' >&2; exit 1; }
checks="$(gh pr checks "$branch" --json bucket,name,workflow 2>/dev/null || true)"
jq -e '
  [.[] | select(.workflow == "Agent PR" or .name == "verify") | .bucket] as $b |
  ($b | length) > 0 and all($b[]; . == "pass")
' <<< "${checks:-[]}" >/dev/null || { echo 'Agent PR CI has not passed for this head.' >&2; exit 1; }
status="$(gh api "repos/$repo_slug/commits/$head/status")"
jq -e '[.statuses[] | select(.context == "factory-gates")][0].state == "success"' <<< "$status" >/dev/null \
  || { echo 'The factory-gates commit status has not passed for this head.' >&2; exit 1; }
printf 'Ready for human review: %s at %s\n' "$(jq -r .url <<< "$pr")" "$head"
