#!/usr/bin/env bash
# Shared GitHub guards for issue scheduling and the human merge check.

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
    state="$(jq -r .state <<< "$data")"
    if [[ "$state" != CLOSED ]]; then
      blocked_by+=("#$blocker (issue open)")
      continue
    fi
    labels="$(jq -r '[.labels[].name | select(. == "agent:ingest" or . == "agent:page")][0] // empty' <<< "$data")"
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

# GitHub may briefly report UNKNOWN while it computes mergeability. The compare
# endpoint independently verifies that the current base is in the PR history.
pr_freshness() {
  local branch="$1" data base head compare
  data="$(gh pr view "$branch" --json state,mergeable,mergeStateStatus,baseRefOid,headRefOid)" || return 2
  [[ "$(jq -r .state <<< "$data")" == OPEN ]] || return 2
  if jq -e '.mergeable == "CONFLICTING" or .mergeStateStatus == "DIRTY"' <<< "$data" >/dev/null; then
    freshness_reason='PR has merge conflicts'
    return 1
  fi
  base="$(jq -r .baseRefOid <<< "$data")"
  head="$(jq -r .headRefOid <<< "$data")"
  [[ "$base" =~ ^[0-9a-fA-F]{40}$ && "$head" =~ ^[0-9a-fA-F]{40}$ ]] || return 2
  compare="$(gh api "repos/$repo_slug/compare/$base...$head" --jq .status)" || return 2
  case "$compare" in
    ahead|identical) return 0 ;;
    behind|diverged) freshness_reason='PR branch is behind the current base branch'; return 1 ;;
    *) return 2 ;;
  esac
}
