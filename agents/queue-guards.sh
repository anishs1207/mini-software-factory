#!/usr/bin/env bash
# Shared GitHub guards for issue scheduling and the human merge check.
campaign_label="$(cat "$HOME/.config/briefing-agents/campaign-label")"
[[ "$campaign_label" =~ ^product:[0-9a-f]{12}$ ]] || { echo 'Missing active product campaign label.' >&2; exit 1; }

stage_issues() {
  local state="$1" stage="$2"
  gh api --paginate "repos/$repo_slug/issues?state=$state&labels=$campaign_label,$stage&per_page=100" \
    | jq -s 'add // [] | map(select(.pull_request == null))'
}

dependency_state() {
  local issue="$1" raw blockers blocker data state labels branch prs
  blocked_by=()
  dependency_count=0
  raw="$(gh api --paginate "repos/$repo_slug/issues/$issue/dependencies/blocked_by?per_page=100")" || return 2
  jq -s -e --arg repo "$repo_slug" \
    'add // [] | all(.[]; (.repository_url | endswith("/repos/" + $repo)) and (.number | type == "number"))' \
    <<< "$raw" >/dev/null || return 2
  blockers="$(jq -s -r 'add // [] | .[].number' <<< "$raw")" || return 2
  while IFS= read -r blocker; do
    [[ -n "$blocker" ]] || continue
    [[ "$blocker" =~ ^[0-9]+$ ]] || return 2
    ((dependency_count+=1))
    data="$(gh issue view "$blocker" --json state,labels)" || return 2
    jq -e --arg campaign "$campaign_label" 'any(.labels[].name; . == $campaign)' <<< "$data" >/dev/null || return 2
    state="$(jq -r .state <<< "$data")"
    if [[ "$state" != CLOSED ]]; then
      blocked_by+=("#$blocker (issue open)")
      continue
    fi
    labels="$(jq -r '[.labels[].name | select(. == "agent:builder1" or . == "agent:builder2")][0] // empty' <<< "$data")"
    if [[ -n "$labels" ]]; then
      branch="agent/${labels#agent:}/issue-$blocker"
      prs="$(gh api "repos/$repo_slug/pulls?head=${repo_slug%%/*}:$branch&state=all&per_page=100")" || return 2
      if ! jq -e 'any(.[]; .merged_at != null)' <<< "$prs" >/dev/null; then
        blocked_by+=("#$blocker (builder PR not merged)")
      fi
    fi
  done <<< "$blockers"
  ((${#blocked_by[@]} == 0))
}

# GitHub may briefly report unknown mergeability while it checks the PR.
# A base branch advancing with unrelated commits does not invalidate the PR.
pr_freshness() {
  local branch="$1" number data attempt
  number="$(gh pr view "$branch" --json number --jq .number)" || return 2
  [[ "$number" =~ ^[1-9][0-9]*$ ]] || return 2
  for attempt in 1 2 3; do
    if data="$(gh api "repos/$repo_slug/pulls/$number")"; then
      [[ "$(jq -r .state <<< "$data")" == open ]] || return 2
      if jq -e '.mergeable == false or .mergeable_state == "dirty"' <<< "$data" >/dev/null; then
        freshness_reason='PR has merge conflicts'
        return 1
      fi
      jq -e '.mergeable == true' <<< "$data" >/dev/null && return 0
    fi
    (( attempt == 3 )) || sleep 3
  done
  return 2
}
