#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
role="${1:-}"
issue="${2:-}"
case "$role" in
  manager|builder1|builder2|reviewer|tester) ;;
  *) echo 'Usage: agents/dispatch.sh {manager|builder1|builder2|reviewer|tester} [issue-number]' >&2; exit 2 ;;
esac
if [[ "$role" != manager && ! "$issue" =~ ^[0-9]+$ ]]; then
  echo 'A numeric GitHub issue number is required for this role.' >&2; exit 2
fi
if [[ "$role" == manager && -n "$issue" && ! "$issue" =~ ^[0-9]+$ ]]; then
  echo 'Issue number must be numeric.' >&2; exit 2
fi
cd "$repo_dir"
export PATH="$HOME/.npm-global/bin:$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
credentials="$HOME/.config/briefing-agents/credentials.env"
[[ -f "$credentials" ]] || { echo 'Run agents/setup/agent-setup.sh first.' >&2; exit 1; }
set -a
source "$credentials"
set +a
gh auth status >/dev/null
gh repo view >/dev/null
git rev-parse --is-inside-work-tree >/dev/null
git remote get-url origin >/dev/null || { echo 'This checkout needs a GitHub origin remote before agents can push PR branches.' >&2; exit 1; }
trusted_actor="$(gh api user -q .login)"

work_dir="$repo_dir"
if [[ "$role" == builder1 || "$role" == builder2 ]]; then
  default_branch="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name')"
  branch="agent/$role/issue-$issue"
  work_dir="$HOME/.cache/briefing-worktrees/$role-issue-$issue"
  if [[ ! -d "$work_dir" ]]; then
    mkdir -p "$(dirname "$work_dir")"
    git fetch origin "$default_branch"
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      git worktree add "$work_dir" "$branch"
    else
      git worktree add -b "$branch" "$work_dir" "origin/$default_branch"
    fi
  fi
  hook_dir="$(git -C "$work_dir" rev-parse --git-path hooks)"
  mkdir -p "$hook_dir"
  install -m 700 "$repo_dir/agents/pre-push-product.sh" "$hook_dir/pre-push"
fi

prompt="$(mktemp)"
trap 'rm -f "$prompt"' EXIT
usage_dir="$repo_dir/.local-evidence/usage"
mkdir -p "$usage_dir"
chmod 700 "$repo_dir/.local-evidence" "$usage_dir"
umask 077
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$role-${issue:-startup}-$$"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
spec_path="$(cat "$HOME/.config/briefing-agents/spec-path")"
campaign_label="$(cat "$HOME/.config/briefing-agents/campaign-label")"
[[ -f "$repo_dir/$spec_path" && "$campaign_label" =~ ^product:[0-9a-f]{12}$ ]] \
  || { echo 'Selected product spec or campaign label is missing.' >&2; exit 1; }
actual_label="product:$(sha256sum "$repo_dir/$spec_path" | cut -c1-12)"
[[ "$actual_label" == "$campaign_label" ]] || { echo 'Spec changed during the active campaign; restore it before dispatch.' >&2; exit 1; }
task="Campaign planning for $spec_path"
case "$role" in
  manager) purpose=planning ;;
  builder1|builder2) purpose=implementation ;;
  reviewer) purpose=code_review ;;
  tester) purpose=integration_testing ;;
esac
if [[ -n "$issue" ]]; then
  issue_title="$(gh issue view "$issue" --json title -q .title)"
  task="Issue #$issue: $issue_title"
fi
{
  printf 'Repository: %s\nWork directory: %s\nRole: %s\n' "$repo_dir" "$work_dir" "$role"
  printf 'Product spec: %s\nCampaign label: %s\nRead the selected spec before this issue.\n' "$spec_path" "$campaign_label"
  if [[ "$work_dir" != "$repo_dir" ]]; then
    printf 'Do all implementation commands in the work directory. Its branch is already created for this issue.\n'
    printf 'Never commit or push generated dependencies or build output such as node_modules/ or .next/. Add them to .gitignore before staging files.\n'
    if [[ "$(git -C "$work_dir" rev-list --objects "origin/$default_branch..HEAD" -- node_modules .next | wc -l)" -gt 0 ]]; then
      printf 'The existing branch history contains generated files. Do not push it. If the branch is unpublished, clean the local branch history and verify git rev-list shows no node_modules/ or .next/ entries before opening a PR. Preserve product source and tests. If it is published, report BLOCKED instead of rewriting remote history.\n'
    fi
  fi
  printf 'Read agents/README.md and your role instructions. Use GitHub Issues and PRs for all handoffs. Do not print secrets.\n'
  if [[ "$role" == manager ]]; then
    if [[ -n "$issue" ]]; then
      printf 'Handle the dispatched manager issue using the selected spec and trusted issue history. If this is a release issue, deploy only merged code and record the real result.\n'
    else
      printf 'Turn the product spec into outcome-sized GitHub Issues with acceptance criteria, dependencies, builder roles, and the campaign label. Choose the number and structure from the spec.\n'
    fi
  fi
  if [[ -n "$issue" ]]; then
    gh issue view "$issue" --json number,title,body,url,author,labels,assignees,comments \
      | jq -er --arg actor "$trusted_actor" --arg campaign "$campaign_label" 'select(.author.login == $actor and any(.labels[].name; . == $campaign)) | "Issue #\(.number): \(.title)\nURL: \(.url)\n\n\(.body)\n\nTrusted comments:\n" + ([.comments[]? | select(.author.login == $actor) | "- " + .author.login + ": " + .body] | join("\n"))'
  else
    printf 'Create the initial ticket trail for this spec; the queue dispatches one issue at a time.\n'
  fi
  if [[ "$role" == builder1 || "$role" == builder2 ]]; then
    if [[ "$(git -C "$work_dir" rev-list --objects "origin/$default_branch..HEAD" -- node_modules .next | wc -l)" -gt 0 ]]; then
      printf 'PRIORITY: The unpushed branch history contains generated dependencies. Keep source and tests, add node_modules/ and .next/ to .gitignore, rewrite the unpublished local commit to exclude those directories, and verify git rev-list --objects origin/%s..HEAD -- node_modules .next is empty before pushing. The installed pre-push hook will reject oversized history.\n' "$default_branch"
    fi
  fi
} > "$prompt"

case "$role" in
  builder1|builder2)
    max_turns="${FACTORY_MAX_BUILDER_TURNS:-8}"
    max_seconds="${FACTORY_MAX_BUILDER_SECONDS:-3600}"
    [[ "$max_turns" =~ ^[1-9][0-9]*$ && "$max_seconds" =~ ^[1-9][0-9]*$ ]] || {
      echo 'Builder turn and time limits must be positive integers.' >&2; exit 2;
    }
    deadline=$(( $(date -u +%s) + max_seconds ))
    session_key="agent:$role:issue-$issue-$run_id"
    followup_hint=''
    for ((turn=1; turn<=max_turns; turn++)); do
      remaining=$(( deadline - $(date -u +%s) ))
      if (( remaining <= 0 )); then
        echo "Builder time limit reached before turn $turn; no complete PR." >&2
        exit 1
      fi
      if (( turn > 1 )); then
        cat > "$prompt" <<PROMPT
Continue issue #$issue in the same session and worktree $work_dir. Finish the implementation, run product-check.sh and other required tests, commit as your assigned agent author, push, and open the PR with the required evidence fields. The queue has not received a complete PR yet. Continue using tools now; do not stop with a promise to work in another turn. If you cannot proceed, state BLOCKED: followed by the specific reason.
PROMPT
        if [[ -n "$followup_hint" ]]; then printf '%s\n' "$followup_hint" >> "$prompt"; fi
      fi
      turn_id="$run_id-turn$turn"
      turn_started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      openclaw gateway usage-cost --agent "$role" --json > "$usage_dir/$turn_id.before.json" 2>/dev/null || true
      remaining=$(( deadline - $(date -u +%s) ))
      (( remaining > 0 )) || remaining=1
      (( remaining <= 600 )) || remaining=600
      if bash "$repo_dir/agents/beam-slot.sh" openclaw agent --agent "$role" \
        --session-key "$session_key" --message-file "$prompt" --timeout "$remaining" --json \
        > "$usage_dir/$turn_id.openclaw.json"; then result=0; else result=$?; fi
      if [[ "$result" -eq 0 ]] && ! jq -e '.status == "ok"' "$usage_dir/$turn_id.openclaw.json" >/dev/null 2>&1; then
        echo "Builder turn $turn returned no successful OpenClaw result." >&2
        result=1
      fi
      openclaw gateway usage-cost --agent "$role" --json > "$usage_dir/$turn_id.after.json" 2>/dev/null || true
      turn_finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      python3 "$repo_dir/agents/activity.py" record \
        --usage-dir "$usage_dir" --run-id "$turn_id" --agent "$role" --issue "$issue" \
        --task "$task (turn $turn)" --purpose "$purpose" \
        --started-at "$turn_started" --finished-at "$turn_finished" --exit-code "$result" \
        --source-stage "${FACTORY_SOURCE_STAGE:-manual}"
      activity_comment="$(python3 "$repo_dir/agents/activity.py" comment --usage-dir "$usage_dir" --run-id "$turn_id")"
      gh issue comment "$issue" --body "$activity_comment" >/dev/null
      printf 'ACTIVITY: %s\n' "$usage_dir/$turn_id.activity.json"
      final_text="$(jq -r '[.result.payloads[]?.text | select(type == "string")] | join("\n")' "$usage_dir/$turn_id.openclaw.json" 2>/dev/null || true)"
      if [[ "$result" -ne 0 ]]; then
        if grep -Fq 'consecutive identical tool failures' <<< "$final_text" \
          && (( turn < max_turns )); then
          followup_hint='The previous turn stopped after repeated invalid tool arguments. Correct the arguments before retrying. For the process tool, use action exactly "poll" with the returned sessionId; do not add XML or punctuation. Inspect current files and continue the work. Preserve any completed product code.'
          echo "Builder turn $turn hit a recoverable tool-argument error; continuing the same session." >&2
          continue
        fi
        printf '%s\n' "$final_text" >&2
        exit "$result"
      fi
      followup_hint=''
      printf 'Builder turn %s/%s finished.\n' "$turn" "$max_turns"
      if grep -Eiq '^BLOCKED:[[:space:]]*[^[:space:]]' <<< "$final_text"; then
        printf '%s\n' "$final_text" >&2
        exit 1
      fi
      pr_ready=false
      if [[ -f "$work_dir/product-check.sh" ]] \
        && git -C "$work_dir" cat-file -e HEAD:product-check.sh 2>/dev/null \
        && [[ "$(git -C "$work_dir" rev-list --objects "origin/$default_branch..HEAD" -- node_modules .next | wc -l)" -eq 0 ]]; then
        pr_state="$(gh pr view "$branch" --json state,body,commits,headRefName,headRefOid 2>/dev/null || true)"
        pr_body="$(jq -r '.body // ""' <<< "$pr_state" 2>/dev/null || true)"
        if jq -e --arg branch "$branch" '.state == "OPEN" and .headRefName == $branch and (.commits | length > 0)' \
          <<< "$pr_state" >/dev/null 2>&1 \
          && [[ "$(git -C "$work_dir" rev-parse HEAD)" == "$(jq -r .headRefOid <<< "$pr_state")" ]] \
          && grep -Eiq "(Closes|Fixes)[[:space:]]+#${issue}([^0-9]|$)" <<< "$pr_body" \
          && grep -Eiq "^Agent:[[:space:]]*${role}[[:space:]]*$" <<< "$pr_body" \
          && grep -Eiq '^Model:[[:space:]]*[^[:space:]]' <<< "$pr_body" \
          && grep -Eiq '^Tokens:[[:space:]]*[^[:space:]]' <<< "$pr_body" \
          && grep -Eiq '^Tests:[[:space:]]*[^[:space:]]' <<< "$pr_body"; then
          pr_ready=true
        fi
      fi
      if [[ "$pr_ready" == true ]] && gh pr diff "$branch" --name-only \
        | grep -Eq '^(\.github/|agents/|factory-tests/|infra/|spec/|deliverables/|instructions-to-agent\.md$|agent-setup\.sh$)'; then
        pr_ready=false
        followup_hint="The PR diff still includes factory-owned files. If those files match the current default branch, merge origin/$default_branch into your issue branch and push the merge commit, then rerun product-check.sh. Otherwise remove your factory-file edits. Do not finish until the PR diff contains product files only."
      fi
      if [[ "$pr_ready" == true ]]; then
        echo "Builder supplied a PR and product-check.sh after $turn turn(s)."
        break
      fi
      if (( $(date -u +%s) >= deadline )); then
        echo "Builder time limit reached after $turn turn(s); no complete PR." >&2
        exit 1
      fi
      if (( turn == max_turns )); then
        echo "Builder turn limit reached ($max_turns); no complete PR." >&2
        exit 1
      fi
    done
    exit 0
    ;;
  *)
    if bash "$repo_dir/agents/beam-slot.sh" hermes -p "$role" --usage-file "$usage_dir/$run_id.hermes.json" \
      chat --toolsets coding --oneshot --query-file "$prompt"; then result=0; else result=$?; fi
    ;;
esac
finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 "$repo_dir/agents/activity.py" record \
  --usage-dir "$usage_dir" --run-id "$run_id" --agent "$role" --issue "${issue:-}" \
  --task "$task" --purpose "$purpose" \
  --started-at "$started_at" --finished-at "$finished_at" --exit-code "$result" \
  --source-stage "${FACTORY_SOURCE_STAGE:-manual}"
if [[ -n "$issue" ]]; then
  activity_comment="$(python3 "$repo_dir/agents/activity.py" comment --usage-dir "$usage_dir" --run-id "$run_id")"
  gh issue comment "$issue" --body "$activity_comment" >/dev/null
fi
printf 'ACTIVITY: %s\n' "$usage_dir/$run_id.activity.json"
exit "$result"
