#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
mkdir -p "$HOME/.cache" "$repo_dir/.local-evidence/dispatch-logs"
chmod 700 "$repo_dir/.local-evidence" "$repo_dir/.local-evidence/dispatch-logs"
exec 8>"$HOME/.cache/briefing-issue-poller.lock"
flock -n 8 || exit 0
exec 9>"$HOME/.cache/briefing-agent.lock"
flock -n 9 || exit 0
export BRIEFING_MODEL_LOCK_HELD=1
gh auth status >/dev/null
gh repo view >/dev/null
trusted_actor="$(gh api user -q .login)"

set_stage() {
  local issue_number="$1" next_stage="$2" current
  local -a args=()
  while IFS= read -r current; do
    [[ -n "$current" ]] && args+=(--remove-label "$current")
  done < <(gh issue view "$issue_number" --json labels --jq '.labels[].name | select(startswith("briefing:"))')
  gh issue edit "$issue_number" "${args[@]}" --add-label "$next_stage" >/dev/null
}

has_stage() {
  gh issue view "$1" --json labels --jq '.labels[].name' | grep -Fxq "$2"
}

ci_state() {
  local checks
  checks="$(gh pr checks "$1" --json bucket,name,workflow 2>/dev/null || true)"
  jq -r '
    [.[] | select(.workflow == "Agent PR" or .name == "verify") | .bucket] as $b |
    if ($b | length) == 0 then "missing"
    elif any($b[]; . == "fail" or . == "cancel") then "fail"
    elif all($b[]; . == "pass") then "pass"
    else "pending" end
  ' <<< "${checks:-[]}" 2>/dev/null || printf 'missing\n'
}

# One ticket per timer run. Manager handles recoveries and its own delivery ticket.
stage='' issue='' role='' labels=''
for candidate_stage in briefing:review briefing:test briefing:needs-manager briefing:ready; do
  row="$(gh issue list --state open --label "$candidate_stage" --limit 100 --json number,labels \
    | jq -r 'first(.[] | [.number, ([.labels[].name] | join(","))] | @tsv) // empty')"
  [[ -n "$row" ]] || continue
  issue="${row%%$'\t'*}"
  labels="${row#*$'\t'}"
  stage="$candidate_stage"
  case "$stage" in
    briefing:review) role=reviewer ;;
    briefing:test) role=tester ;;
    briefing:needs-manager) role=manager ;;
    briefing:ready)
      if [[ ",$labels," == *,agent:ingest,* ]]; then role=ingest
      elif [[ ",$labels," == *,agent:page,* ]]; then role=page
      fi ;;
  esac
  break
done
[[ -n "$issue" ]] || exit 0
if [[ -z "$role" ]]; then
  gh issue comment "$issue" --body 'Queue could not route this ready issue: add agent:ingest or agent:page.' >/dev/null
  set_stage "$issue" briefing:needs-manager
  exit 1
fi

expected_head=''
if [[ "$role" == reviewer || "$role" == tester ]]; then
  if [[ ",$labels," == *,agent:ingest,* ]]; then builder=ingest
  elif [[ ",$labels," == *,agent:page,* ]]; then builder=page
  else
    gh issue comment "$issue" --body 'HANDOFF: Missing builder label; manager must restore routing.' >/dev/null
    set_stage "$issue" briefing:needs-manager
    exit 1
  fi
  branch="agent/$builder/issue-$issue"
  pr_state="$(gh pr view "$branch" --json state,headRefOid,updatedAt 2>/dev/null || true)"
  if ! jq -e '.state == "OPEN" and (.headRefOid | length == 40)' <<< "$pr_state" >/dev/null 2>&1; then
    gh issue comment "$issue" --body 'HANDOFF: Expected open PR missing; manager must inspect.' >/dev/null
    set_stage "$issue" briefing:needs-manager
    exit 1
  fi
  expected_head="$(jq -r .headRefOid <<< "$pr_state")"
  case "$(ci_state "$branch")" in
    pass) ;;
    pending)
      last_update="$(jq -r .updatedAt <<< "$pr_state")"
      if [[ $(( $(date -u +%s) - $(date -u -d "$last_update" +%s) )) -lt 900 ]]; then exit 0; fi
      gh issue comment "$issue" --body 'HANDOFF: Agent PR CI stayed pending for over 15 minutes; manager must inspect.' >/dev/null
      set_stage "$issue" briefing:needs-manager
      exit 1 ;;
    *)
      gh issue comment "$issue" --body 'HANDOFF: Agent PR CI is missing or failing; manager must inspect and requeue a fix.' >/dev/null
      set_stage "$issue" briefing:needs-manager
      exit 1 ;;
  esac
  if [[ "$role" == tester ]]; then
    review_json="$(gh issue view "$issue" --json comments)"
    if ! jq -e --arg actor "$trusted_actor" --arg head "$expected_head" \
      '([.comments[] | select(.author.login == $actor and (.body | startswith("REVIEW:")))] | last | .body // "") as $body | ($body | startswith("REVIEW: APPROVED")) and (($body | split("\n") | index("Head: " + $head)) != null)' \
      <<< "$review_json" >/dev/null; then
      gh issue comment "$issue" --body 'HANDOFF: No reviewer approval for this PR head; returning to review.' >/dev/null
      set_stage "$issue" briefing:review
      exit 1
    fi
  fi
fi

previous_pr_head=''
if [[ "$role" == ingest || "$role" == page ]]; then
  previous_pr_head="$(gh pr view "agent/$role/issue-$issue" --json headRefOid --jq .headRefOid 2>/dev/null || true)"
fi
set_stage "$issue" briefing:in-progress
gh issue comment "$issue" --body "HANDOFF: queue -> $role; issue #$issue; prior stage $stage." >/dev/null
before_comments="$(gh issue view "$issue" --json comments --jq '.comments | length')"
log_file="$repo_dir/.local-evidence/dispatch-logs/$(date -u +%Y%m%dT%H%M%SZ)-$role-$issue.log"
if bash "$repo_dir/agents/dispatch.sh" "$role" "$issue" 2>&1 | tee "$log_file"; then
  result=0
else
  result="${PIPESTATUS[0]}"
fi
if [[ "$result" -ne 0 ]]; then
  if grep -Eiq '(^|[^0-9])(402|429)([^0-9]|$)|rate.?limit|quota|payment required' "$log_file"; then
    reason='Model quota/rate limit remained after fallback; inspect the log and configure a working free model.'
  else
    reason='Agent dispatch failed; inspect the service journal and local dispatch log.'
  fi
  gh issue comment "$issue" --body "HANDOFF: $role -> manager. $reason" >/dev/null
  if [[ "$role" == manager ]]; then set_stage "$issue" briefing:blocked
  else set_stage "$issue" briefing:needs-manager; fi
  exit 1
fi

if [[ "$role" == ingest || "$role" == page ]]; then
  branch="agent/$role/issue-$issue"
  pr_json="$(gh pr view "$branch" --json number,url,state,body,headRefName,headRefOid,commits 2>/dev/null || true)"
  body="$(jq -r '.body // ""' <<< "$pr_json" 2>/dev/null || true)"
  author="$(git -C "$HOME/.cache/briefing-worktrees/$role-issue-$issue" log -1 --format=%an 2>/dev/null || true)"
  expected_author="Briefing Ingest Agent"
  [[ "$role" == page ]] && expected_author="Briefing Page Agent"
  if ! jq -e --arg branch "$branch" '.state == "OPEN" and .headRefName == $branch and (.commits | length > 0)' <<< "$pr_json" >/dev/null 2>&1 \
    || ! grep -Eiq "(Closes|Fixes)[[:space:]]+#${issue}([^0-9]|$)" <<< "$body" \
    || ! grep -Eiq "^Agent:[[:space:]]*${role}[[:space:]]*$" <<< "$body" \
    || ! grep -Eiq '^Model:[[:space:]]*[^[:space:]]' <<< "$body" \
    || ! grep -Eiq '^Tokens:[[:space:]]*[^[:space:]]' <<< "$body" \
    || ! grep -Eiq '^Tests:[[:space:]]*[^[:space:]]' <<< "$body" \
    || [[ "$author" != "$expected_author" ]] \
    || { [[ -n "$previous_pr_head" ]] && [[ "$(jq -r .headRefOid <<< "$pr_json")" == "$previous_pr_head" ]]; }; then
    gh issue comment "$issue" --body "HANDOFF: $role -> manager. PR gate failed: check branch, issue link, Agent/Model/Tokens/Tests fields, agent commit author, and a new commit on retries." >/dev/null
    set_stage "$issue" briefing:needs-manager
    exit 1
  fi
  pr_url="$(jq -r .url <<< "$pr_json")"
  gh issue comment "$issue" --body "HANDOFF: $role -> reviewer. PR: $pr_url" >/dev/null
  set_stage "$issue" briefing:review
  exit 0
fi

after_json="$(gh issue view "$issue" --json comments,labels)"
stage_count="$(jq '[.labels[].name | select(startswith("briefing:"))] | length' <<< "$after_json")"
new_verdict="$(jq -r --argjson before "$before_comments" --arg actor "$trusted_actor" \
  '[.comments[$before:][]? | select(.author.login == $actor) | .body] | last // ""' <<< "$after_json")"
current_head=''
if [[ "$role" == reviewer || "$role" == tester ]]; then
  current_head="$(gh pr view "$branch" --json headRefOid --jq .headRefOid 2>/dev/null || true)"
fi
if [[ "$stage_count" -ne 1 ]] || has_stage "$issue" briefing:in-progress \
  || { [[ -n "$expected_head" ]] && [[ "$expected_head" != "$current_head" ]]; }; then
  verdict_ok=false
elif [[ "$role" == reviewer ]]; then
  verdict_ok=false
  if grep -Fxq "Head: $expected_head" <<< "$new_verdict"; then
    if has_stage "$issue" briefing:test && grep -q '^REVIEW: APPROVED' <<< "$new_verdict"; then verdict_ok=true; fi
    if has_stage "$issue" briefing:ready && grep -q '^REVIEW: CHANGES REQUESTED' <<< "$new_verdict"; then verdict_ok=true; fi
  fi
elif [[ "$role" == tester ]]; then
  verdict_ok=false
  if grep -Fxq "Head: $expected_head" <<< "$new_verdict"; then
    if has_stage "$issue" briefing:merge-ready && grep -q '^TEST: PASSED' <<< "$new_verdict"; then verdict_ok=true; fi
    if has_stage "$issue" briefing:ready && grep -q '^TEST: FAILED' <<< "$new_verdict"; then verdict_ok=true; fi
  fi
else
  verdict_ok=false
  if grep -q '^MANAGER:' <<< "$new_verdict"; then
    for allowed in briefing:ready briefing:review briefing:test briefing:merge-ready briefing:done briefing:blocked; do
      if has_stage "$issue" "$allowed"; then verdict_ok=true; break; fi
    done
  fi
fi
if [[ "$verdict_ok" != true ]]; then
  gh issue comment "$issue" --body "HANDOFF: $role -> manager. Missing or inconsistent gate verdict/next-stage label; inspect the agent log." >/dev/null
  if [[ "$role" == manager ]]; then set_stage "$issue" briefing:blocked
  else set_stage "$issue" briefing:needs-manager; fi
  exit 1
fi
