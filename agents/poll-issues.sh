#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
export PATH="$HOME/.npm-global/bin:$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
[[ -f "$HOME/.config/briefing-agents/campaign-label" && -f "$HOME/.config/briefing-agents/spec-path" ]] || exit 0
[[ -f "$HOME/.config/briefing-agents/queue-armed" ]] || exit 0
[[ "$(cat "$HOME/.config/briefing-agents/queue-armed")" == "$(cat "$HOME/.config/briefing-agents/campaign-label")" ]] || exit 0
mkdir -p "$HOME/.cache" "$repo_dir/.local-evidence/dispatch-logs"
chmod 700 "$repo_dir/.local-evidence" "$repo_dir/.local-evidence/dispatch-logs"
exec 8>"$HOME/.cache/briefing-issue-poller-ollama.lock"
flock -n 8 || exit 0
exec 7>"$HOME/.cache/briefing-queue-state.lock"
flock -x 7
gh auth status >/dev/null
gh repo view >/dev/null
trusted_actor="$(gh api user -q .login)"
repo_slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
source "$repo_dir/agents/queue-guards.sh"
max_build_attempts="${FACTORY_MAX_BUILD_ATTEMPTS:-6}"
[[ "$max_build_attempts" =~ ^[1-9][0-9]*$ ]] || { echo 'FACTORY_MAX_BUILD_ATTEMPTS must be a positive integer.' >&2; exit 2; }

set_stage() {
  local issue_number="$1" next_stage="$2" current
  local -a args=()
  while IFS= read -r current; do
    [[ -n "$current" ]] && args+=(--remove-label "$current")
  done < <(gh issue view "$issue_number" --json labels --jq '.labels[].name | select(startswith("factory:"))')
  gh issue edit "$issue_number" "${args[@]}" --add-label "$next_stage" >/dev/null
}

has_stage() {
  gh issue view "$1" --json labels --jq '.labels[].name' | grep -Fxq "$2"
}

post_gate_status() {
  local head="$1" state="$2" description="$3"
  gh api --method POST "repos/$repo_slug/statuses/$head" \
    -f state="$state" -f context=factory-gates -f description="$description" \
    -f target_url="$issue_url" >/dev/null
}

ci_state() {
  local head checks
  head="$(gh pr view "$1" --json headRefOid --jq .headRefOid 2>/dev/null)" || { echo missing; return; }
  [[ "$head" =~ ^[0-9a-fA-F]{40}$ ]] || { echo missing; return; }
  checks="$(gh api --paginate "repos/$repo_slug/commits/$head/check-runs?per_page=100" 2>/dev/null)" || { echo missing; return; }
  jq -s -r '
    [.[].check_runs[]? | select(.name == "verify" and .app.slug == "github-actions")] as $runs |
    if ($runs | length) == 0 then "missing"
    elif any($runs[]; .conclusion == "failure" or .conclusion == "cancelled" or .conclusion == "timed_out" or .conclusion == "action_required") then "fail"
    elif all($runs[]; .status == "completed" and .conclusion == "success") then "pass"
    else "pending" end
  ' <<< "$checks" || echo missing
}

verify_builder_head() {
  local builder="$1" work_dir="$2" head="$3" base_branch
  base_branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)" || return 1
  git -C "$work_dir" fetch --no-tags origin "$base_branch" >/dev/null || return 1
  python3 "$repo_dir/agents/verify-pr-authors.py" "$work_dir" "$head" "$base_branch" "$builder"
}

route_stale_pr() {
  local ticket="$1" branch="$2" head="$3" reason="$4"
  issue_url="$(gh issue view "$ticket" --json url --jq .url)"
  post_gate_status "$head" failure "$reason" || return 1
  gh issue comment "$ticket" --body "HANDOFF: PR $branch needs builder repair: $reason. Update the branch against the current default branch, resolve conflicts, and provide a new commit. Review and test must rerun." >/dev/null
  set_stage "$ticket" factory:ready
}

# Reconcile GitHub merges and dependency labels before dispatching another agent.
# This also corrects a manually applied ready label on a blocked ticket.
stage_rows="$(stage_issues all factory:merge-ready)" || exit 1
while IFS= read -r ticket; do
  [[ -n "$ticket" ]] || continue
  ticket_data="$(gh issue view "$ticket" --json labels,state)"
  builder="$(jq -r '([.labels[].name | select(. == "agent:builder1" or . == "agent:builder2")][0] // empty) | split(":")[-1]' <<< "$ticket_data")"
  [[ -n "$builder" ]] || continue
  branch="agent/$builder/issue-$ticket"
  pr_data="$(gh pr view "$branch" --json state,mergedAt,headRefOid 2>/dev/null || true)"
  if jq -e '.state == "MERGED" and .mergedAt != null' <<< "$pr_data" >/dev/null 2>&1; then
    gh issue comment "$ticket" --body "HANDOFF: PR for $branch merged by the human owner; issue complete." >/dev/null
    set_stage "$ticket" factory:done
    if [[ "$(jq -r .state <<< "$ticket_data")" != CLOSED ]]; then
      gh issue close "$ticket" --reason completed >/dev/null
    fi
    continue
  fi
  if jq -e '.state == "OPEN"' <<< "$pr_data" >/dev/null 2>&1; then
    if pr_freshness "$branch"; then
      head="$(jq -r .headRefOid <<< "$pr_data")"
      ticket_comments="$(gh issue view "$ticket" --json comments)"
      if ! jq -e --arg actor "$trusted_actor" --arg head "$head" '
        ([.comments[] | select(.author.login == $actor and (.body | startswith("REVIEW:")))] | last | .body // "") as $review |
        ([.comments[] | select(.author.login == $actor and (.body | startswith("TEST:")))] | last | .body // "") as $test |
        ($review | startswith("REVIEW: APPROVED")) and (($review | split("\n") | index("Head: " + $head)) != null) and
        ($test | startswith("TEST: PASSED")) and (($test | split("\n") | index("Head: " + $head)) != null)
      ' <<< "$ticket_comments" >/dev/null; then
        issue_url="$(gh issue view "$ticket" --json url --jq .url)"
        post_gate_status "$head" pending 'Review and test must repeat for the new PR head'
        gh issue comment "$ticket" --body 'HANDOFF: PR head changed after approval; independent review and test must repeat.' >/dev/null
        set_stage "$ticket" factory:review
      fi
    else
      result=$?
      if [[ "$result" -eq 1 ]]; then
        head="$(jq -r .headRefOid <<< "$pr_data")"
        route_stale_pr "$ticket" "$branch" "$head" "$freshness_reason"
      else
        echo "Cannot check PR freshness for $branch; leaving ticket at merge-ready." >&2
      fi
    fi
  elif jq -e '.state == "CLOSED"' <<< "$pr_data" >/dev/null 2>&1; then
    gh issue comment "$ticket" --body 'HANDOFF: PR was closed without merge; manager must inspect and choose the next action.' >/dev/null
    set_stage "$ticket" factory:needs-manager
  fi
done < <(jq -r '.[].number' <<< "$stage_rows")

stage_rows="$(stage_issues open factory:waiting)" || exit 1
while IFS= read -r ticket; do
  [[ -n "$ticket" ]] || continue
  if dependency_state "$ticket"; then
    # A waiting ticket with no links may still be under construction.
    ((dependency_count > 0)) || continue
    ticket_data="$(gh issue view "$ticket" --json labels)"
    if jq -e 'any(.labels[].name; . == "agent:builder1" or . == "agent:builder2")' <<< "$ticket_data" >/dev/null; then
      next_stage=factory:ready
    else
      next_stage=factory:needs-manager
    fi
    gh issue comment "$ticket" --body 'HANDOFF: All prerequisite issues are closed and their builder PRs are merged; ticket is unblocked.' >/dev/null
    set_stage "$ticket" "$next_stage"
  else
    result=$?
    [[ "$result" -eq 1 ]] || { echo "Cannot verify dependencies for issue #$ticket." >&2; exit 1; }
  fi
done < <(jq -r '.[].number' <<< "$stage_rows")

stage_rows="$(stage_issues open factory:ready)" || exit 1
while IFS= read -r ticket; do
  [[ -n "$ticket" ]] || continue
  if dependency_state "$ticket"; then
    continue
  else
    result=$?
    [[ "$result" -eq 1 ]] || { echo "Cannot verify dependencies for issue #$ticket." >&2; exit 1; }
    gh issue comment "$ticket" --body "HANDOFF: Ticket waits for ${blocked_by[*]}; ready label was removed." >/dev/null
    set_stage "$ticket" factory:waiting
  fi
done < <(jq -r '.[].number' <<< "$stage_rows")

# One ticket per timer run. Manager handles recoveries and its own delivery ticket.
stage='' issue='' role='' labels=''
for candidate_stage in factory:review factory:test factory:needs-manager factory:ready; do
  stage_rows="$(stage_issues open "$candidate_stage")" || exit 1
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    candidate_issue="${row%%$'\t'*}"
    candidate_labels="${row#*$'\t'}"
    case "$candidate_stage" in
      factory:review) candidate_role=reviewer ;;
      factory:test) candidate_role=tester ;;
      factory:needs-manager) candidate_role=manager ;;
      factory:ready)
        candidate_role=''
        if [[ ",$candidate_labels," == *,agent:builder1,* ]]; then candidate_role=builder1
        elif [[ ",$candidate_labels," == *,agent:builder2,* ]]; then candidate_role=builder2
        fi ;;
    esac
    if [[ -n "$candidate_role" ]]; then
      issue="$candidate_issue"; labels="$candidate_labels"; stage="$candidate_stage"; role="$candidate_role"
      break
    fi
  done < <(jq -r '.[] | [.number, ([.labels[].name] | join(","))] | @tsv' <<< "$stage_rows")
  [[ -z "$issue" ]] || break
done
[[ -n "$issue" ]] || exit 0
issue_url="$(gh issue view "$issue" --json url --jq .url)"
if [[ "$stage" != factory:needs-manager ]]; then
  builder_count="$(gh issue view "$issue" --json labels --jq '[.labels[].name | select(. == "agent:builder1" or . == "agent:builder2")] | length')"
  if [[ "$builder_count" != 1 ]]; then
    gh issue comment "$issue" --body 'HANDOFF: Exactly one builder must own this implementation issue; manager must correct its labels.' >/dev/null
    set_stage "$issue" factory:needs-manager
    exit 1
  fi
fi
if dependency_state "$issue"; then
  :
else
  result=$?
  if [[ "$result" -eq 1 ]]; then
    gh issue comment "$issue" --body "HANDOFF: Ticket waits for ${blocked_by[*]}." >/dev/null
    set_stage "$issue" factory:waiting
    exit 0
  fi
  echo "Cannot verify dependencies for issue #$issue." >&2
  exit 1
fi
if [[ -z "$role" ]]; then
  gh issue comment "$issue" --body 'Queue could not route this ready issue: add agent:builder1 or agent:builder2.' >/dev/null
  set_stage "$issue" factory:needs-manager
  exit 1
fi

if [[ "$role" == builder1 || "$role" == builder2 ]]; then
  attempts="$(gh issue view "$issue" --json comments | jq -r --arg actor "$trusted_actor" --arg role "$role" \
    '[.comments[] | select(.author.login == $actor and (.body | startswith("HANDOFF: queue -> " + $role + ";")))] | length')"
  if (( attempts >= max_build_attempts )); then
    gh issue comment "$issue" --body "HANDOFF: Build attempt limit reached ($attempts/$max_build_attempts). Human must inspect the failures before any further builder run." >/dev/null
    set_stage "$issue" factory:blocked
    exit 1
  fi
fi

expected_head=''
if [[ "$role" == reviewer || "$role" == tester ]]; then
  if [[ ",$labels," == *,agent:builder1,* ]]; then builder=builder1
  elif [[ ",$labels," == *,agent:builder2,* ]]; then builder=builder2
  else
    gh issue comment "$issue" --body 'HANDOFF: Missing builder label; manager must restore routing.' >/dev/null
    set_stage "$issue" factory:needs-manager
    exit 1
  fi
  branch="agent/$builder/issue-$issue"
  pr_state="$(gh pr view "$branch" --json state,headRefOid,updatedAt 2>/dev/null || true)"
  if ! jq -e '.state == "OPEN" and (.headRefOid | length == 40)' <<< "$pr_state" >/dev/null 2>&1; then
    gh issue comment "$issue" --body 'HANDOFF: Expected open PR missing; manager must inspect.' >/dev/null
    set_stage "$issue" factory:needs-manager
    exit 1
  fi
  expected_head="$(jq -r .headRefOid <<< "$pr_state")"
  if pr_freshness "$branch"; then
    :
  else
    result=$?
    if [[ "$result" -eq 1 ]]; then
      route_stale_pr "$issue" "$branch" "$expected_head" "$freshness_reason"
      exit 0
    fi
    echo "Cannot verify PR freshness for $branch." >&2
    exit 1
  fi
  changed_files="$(gh pr diff "$branch" --name-only)"
  if grep -Eq '^(\.github/|agents/|factory-tests/|infra/|spec/|deliverables/|instructions-to-agent\.md$|agent-setup\.sh$)' <<< "$changed_files"; then
    gh issue comment "$issue" --body 'HANDOFF: Builder PR changes factory-owned CI, queue, infra, or requirements files; manager must inspect and request a product-only PR.' >/dev/null
    set_stage "$issue" factory:needs-manager
    exit 1
  fi
  work_dir="$HOME/.cache/briefing-worktrees/$builder-issue-$issue"
  if ! verify_builder_head "$builder" "$work_dir" "$expected_head"; then
    gh issue comment "$issue" --body 'HANDOFF: PR head or commit authorship does not match the assigned builder worktree; manager must inspect.' >/dev/null
    set_stage "$issue" factory:needs-manager
    exit 1
  fi
  case "$(ci_state "$branch")" in
    pass) ;;
    pending)
      last_update="$(jq -r .updatedAt <<< "$pr_state")"
      if [[ $(( $(date -u +%s) - $(date -u -d "$last_update" +%s) )) -lt 900 ]]; then exit 0; fi
      gh issue comment "$issue" --body 'HANDOFF: Agent PR CI stayed pending for over 15 minutes; manager must inspect.' >/dev/null
      set_stage "$issue" factory:needs-manager
      exit 1 ;;
    *)
      gh issue comment "$issue" --body 'HANDOFF: Agent PR CI is missing or failing; manager must inspect and requeue a fix.' >/dev/null
      set_stage "$issue" factory:needs-manager
      exit 1 ;;
  esac
  if [[ "$role" == reviewer ]]; then
    if [[ "$(git -C "$work_dir" rev-parse HEAD 2>/dev/null || true)" != "$expected_head" ]] \
      || [[ ! -f "$work_dir/product-check.sh" ]] \
      || ! (cd "$work_dir" && bash "$repo_dir/agents/run-product-command.sh" timeout 300s bash product-check.sh); then
      gh issue comment "$issue" --body 'HANDOFF: Product checks failed or the reviewer worktree does not match the PR head; manager must inspect.' >/dev/null
      set_stage "$issue" factory:needs-manager
      exit 1
    fi
  fi
  if [[ "$role" == tester ]]; then
    review_json="$(gh issue view "$issue" --json comments)"
    if ! jq -e --arg actor "$trusted_actor" --arg head "$expected_head" \
      '([.comments[] | select(.author.login == $actor and (.body | startswith("REVIEW:")))] | last | .body // "") as $body | ($body | startswith("REVIEW: APPROVED")) and (($body | split("\n") | index("Head: " + $head)) != null)' \
      <<< "$review_json" >/dev/null; then
      gh issue comment "$issue" --body 'HANDOFF: No reviewer approval for this PR head; returning to review.' >/dev/null
      set_stage "$issue" factory:review
      exit 1
    fi
  fi
fi

previous_pr_head=''
if [[ "$role" == builder1 || "$role" == builder2 ]]; then
  previous_pr_head="$(gh pr view "agent/$role/issue-$issue" --json headRefOid --jq .headRefOid 2>/dev/null || true)"
fi
set_stage "$issue" factory:in-progress
gh issue comment "$issue" --body "HANDOFF: queue -> $role; issue #$issue; prior stage $stage." >/dev/null
before_comments="$(gh issue view "$issue" --json comments --jq '.comments | length')"
log_file="$repo_dir/.local-evidence/dispatch-logs/$(date -u +%Y%m%dT%H%M%SZ)-$role-$issue.log"
flock -u 7
if FACTORY_SOURCE_STAGE="$stage" bash "$repo_dir/agents/dispatch.sh" "$role" "$issue" 2>&1 | tee "$log_file"; then
  result=0
else
  result="${PIPESTATUS[0]}"
fi
if [[ "$result" -ne 0 ]]; then
  if grep -Eiq '(^|[^0-9])(402|429)([^0-9]|$)|rate.?limit|quota|payment required' "$log_file"; then
    reason='Model quota or rate limit; inspect the log and configure a working model for this provider.'
  else
    reason='Agent dispatch failed; inspect the service journal and local dispatch log.'
  fi
  gh issue comment "$issue" --body "HANDOFF: $role -> manager. $reason" >/dev/null
  if [[ "$role" == manager ]]; then set_stage "$issue" factory:blocked
  else set_stage "$issue" factory:needs-manager; fi
  exit 1
fi

if [[ "$role" == builder1 || "$role" == builder2 ]]; then
  branch="agent/$role/issue-$issue"
  [[ -f "$HOME/.cache/briefing-worktrees/$role-issue-$issue/product-check.sh" ]] || {
    gh issue comment "$issue" --body 'HANDOFF: Builder did not provide product-check.sh with runnable product tests.' >/dev/null
    set_stage "$issue" factory:needs-manager
    exit 1
  }
  pr_json="$(gh pr view "$branch" --json number,url,state,body,headRefName,headRefOid,commits 2>/dev/null || true)"
  body="$(jq -r '.body // ""' <<< "$pr_json" 2>/dev/null || true)"
  if ! jq -e --arg branch "$branch" '.state == "OPEN" and .headRefName == $branch and (.commits | length > 0)' <<< "$pr_json" >/dev/null 2>&1 \
    || ! grep -Eiq "(Closes|Fixes)[[:space:]]+#${issue}([^0-9]|$)" <<< "$body" \
    || ! grep -Eiq "^Agent:[[:space:]]*${role}[[:space:]]*$" <<< "$body" \
    || ! grep -Eiq '^Model:[[:space:]]*[^[:space:]]' <<< "$body" \
    || ! grep -Eiq '^Tokens:[[:space:]]*[^[:space:]]' <<< "$body" \
    || ! grep -Eiq '^Tests:[[:space:]]*[^[:space:]]' <<< "$body" \
    || { [[ -n "$previous_pr_head" ]] && [[ "$(jq -r .headRefOid <<< "$pr_json")" == "$previous_pr_head" ]]; }; then
    gh issue comment "$issue" --body "HANDOFF: $role -> manager. PR gate failed: check branch, issue link, Agent/Model/Tokens/Tests fields, agent commit author, and a new commit on retries." >/dev/null
    set_stage "$issue" factory:needs-manager
    exit 1
  fi
  if ! verify_builder_head "$role" "$HOME/.cache/briefing-worktrees/$role-issue-$issue" "$(jq -r .headRefOid <<< "$pr_json")"; then
    gh issue comment "$issue" --body "HANDOFF: $role -> manager. PR head or product commits are not authored by the assigned agent." >/dev/null
    set_stage "$issue" factory:needs-manager
    exit 1
  fi
  pr_url="$(jq -r .url <<< "$pr_json")"
  if ! post_gate_status "$(jq -r .headRefOid <<< "$pr_json")" pending 'Awaiting independent review and test'; then
    gh issue comment "$issue" --body 'HANDOFF: Could not post the required factory-gates commit status; manager must inspect GitHub permissions.' >/dev/null
    set_stage "$issue" factory:needs-manager
    exit 1
  fi
  gh issue comment "$issue" --body "HANDOFF: $role -> reviewer. PR: $pr_url" >/dev/null
  gh pr comment "$branch" --body "HANDOFF: $role -> reviewer for issue #$issue. Head: $(jq -r .headRefOid <<< "$pr_json"). CI, review, and testing must pass before the human merges." >/dev/null || {
    set_stage "$issue" factory:needs-manager; exit 1;
  }
  set_stage "$issue" factory:review
  exit 0
fi

after_json="$(gh issue view "$issue" --json comments,labels)"
stage_count="$(jq '[.labels[].name | select(startswith("factory:"))] | length' <<< "$after_json")"
case "$role" in
  reviewer) verdict_prefix='REVIEW:' ;;
  tester) verdict_prefix='TEST:' ;;
  *) verdict_prefix='MANAGER:' ;;
esac
new_verdict="$(jq -r --argjson before "$before_comments" --arg actor "$trusted_actor" --arg prefix "$verdict_prefix" \
  '[.comments[$before:][]? | select(.author.login == $actor and (.body | startswith($prefix))) | .body] | last // ""' <<< "$after_json")"
current_head=''
if [[ "$role" == reviewer || "$role" == tester ]]; then
  current_head="$(gh pr view "$branch" --json headRefOid --jq .headRefOid 2>/dev/null || true)"
fi
if [[ "$stage_count" -ne 1 ]] || has_stage "$issue" factory:in-progress \
  || { [[ -n "$expected_head" ]] && [[ "$expected_head" != "$current_head" ]]; }; then
  verdict_ok=false
elif [[ "$role" == reviewer ]]; then
  verdict_ok=false
  if grep -Fxq "Head: $expected_head" <<< "$new_verdict"; then
    if has_stage "$issue" factory:test && grep -q '^REVIEW: APPROVED' <<< "$new_verdict"; then verdict_ok=true; fi
    if has_stage "$issue" factory:ready && grep -q '^REVIEW: CHANGES REQUESTED' <<< "$new_verdict"; then verdict_ok=true; fi
  fi
elif [[ "$role" == tester ]]; then
  verdict_ok=false
  if grep -Fxq "Head: $expected_head" <<< "$new_verdict"; then
    if has_stage "$issue" factory:merge-ready && grep -q '^TEST: PASSED' <<< "$new_verdict"; then verdict_ok=true; fi
    if has_stage "$issue" factory:ready && grep -q '^TEST: FAILED' <<< "$new_verdict"; then verdict_ok=true; fi
  fi
else
  verdict_ok=false
  if grep -q '^MANAGER:' <<< "$new_verdict"; then
    for allowed in factory:ready factory:review factory:test factory:merge-ready factory:done factory:blocked; do
      if has_stage "$issue" "$allowed"; then verdict_ok=true; break; fi
    done
  fi
fi
if [[ "$verdict_ok" != true ]]; then
  gh issue comment "$issue" --body "HANDOFF: $role -> manager. Missing or inconsistent gate verdict/next-stage label; inspect the agent log." >/dev/null
  if [[ "$role" == manager ]]; then set_stage "$issue" factory:blocked
  else set_stage "$issue" factory:needs-manager; fi
  exit 1
fi

if [[ "$role" == tester ]]; then
  if has_stage "$issue" factory:ready; then
    bug_number="$(sed -n 's/^Bug: #\([1-9][0-9]*\)$/\1/p' <<< "$new_verdict" | head -n 1)"
    if [[ -z "$bug_number" ]]; then
      gh issue comment "$issue" --body 'HANDOFF: TEST: FAILED requires a Bug: #NUMBER line.' >/dev/null
      set_stage "$issue" factory:needs-manager
      exit 1
    fi
    bug_data="$(gh issue view "$bug_number" --json author,body,labels,state 2>/dev/null || true)"
    if ! jq -e --arg actor "$trusted_actor" --arg campaign "$campaign_label" --arg builder "agent:$builder" --arg original "Bug for #$issue" '
      .state == "OPEN" and .author.login == $actor and
      (.body | contains($original)) and
      any(.labels[].name; . == $campaign) and
      any(.labels[].name; . == $builder) and
      any(.labels[].name; . == "factory:blocked")
    ' <<< "$bug_data" >/dev/null 2>&1; then
      gh issue comment "$issue" --body 'HANDOFF: TEST: FAILED requires a linked, blocked bug issue for the assigned builder.' >/dev/null
      set_stage "$issue" factory:needs-manager
      exit 1
    fi
  else
    while IFS= read -r bug_number; do
      [[ -n "$bug_number" ]] || continue
      bug_data="$(gh issue view "$bug_number" --json state,labels 2>/dev/null || true)"
      if ! jq -e '.state == "CLOSED" and any(.labels[].name; . == "factory:done")' <<< "$bug_data" >/dev/null 2>&1; then
        gh issue comment "$issue" --body "HANDOFF: Bug #$bug_number must be marked done and closed before testing can pass." >/dev/null
        set_stage "$issue" factory:needs-manager
        exit 1
      fi
    done < <(gh issue view "$issue" --json comments | jq -r --arg actor "$trusted_actor" '
      [.comments[] | select(.author.login == $actor and (.body | startswith("TEST: FAILED"))) | .body | split("\n")[] | select(startswith("Bug: #")) | ltrimstr("Bug: #") | select(test("^[1-9][0-9]*$"))] | unique[]')
  fi
fi

if [[ "$role" == reviewer || "$role" == tester ]]; then
  gh pr comment "$branch" --body "$new_verdict" >/dev/null || {
    gh issue comment "$issue" --body "HANDOFF: $role verdict could not be mirrored to the PR." >/dev/null
    set_stage "$issue" factory:needs-manager
    exit 1
  }
fi

if [[ "$role" == reviewer ]] && has_stage "$issue" factory:ready; then
  post_gate_status "$expected_head" failure 'Reviewer requested changes' || {
    set_stage "$issue" factory:needs-manager; exit 1;
  }
elif [[ "$role" == tester ]]; then
  if has_stage "$issue" factory:merge-ready; then
    post_gate_status "$expected_head" success 'CI, reviewer, and tester passed for this commit' || {
      set_stage "$issue" factory:needs-manager; exit 1;
    }
  else
    post_gate_status "$expected_head" failure 'Tester found a defect' || {
      set_stage "$issue" factory:needs-manager; exit 1;
    }
  fi
fi
