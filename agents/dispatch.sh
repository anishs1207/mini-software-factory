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
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
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

# Serialize calls per provider; different providers may work concurrently.
mkdir -p "$HOME/.cache"
if [[ "${FACTORY_MODEL_LOCK_HELD:-}" != 1 ]]; then
  if [[ "$role" == manager || "$role" == reviewer ]]; then provider=openrouter; else provider=ollama; fi
  exec 9>"$HOME/.cache/briefing-$provider.lock"
  flock -n 9 || { echo "Another $provider agent is active." >&2; exit 1; }
fi

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
} > "$prompt"

case "$role" in
  builder1|builder2)
    openclaw gateway usage-cost --agent "$role" --json > "$usage_dir/$run_id.before.json" 2>/dev/null || true
    if openclaw agent --agent "$role" --message-file "$prompt" --json > "$usage_dir/$run_id.openclaw.json"; then result=0; else result=$?; fi
    jq -r 'if type == "object" then (.final // .error.message // .status // "Agent run finished") else . end' \
      "$usage_dir/$run_id.openclaw.json" 2>/dev/null || cat "$usage_dir/$run_id.openclaw.json"
    openclaw gateway usage-cost --agent "$role" --json > "$usage_dir/$run_id.after.json" 2>/dev/null || true
    ;;
  *)
    if hermes -p "$role" --usage-file "$usage_dir/$run_id.hermes.json" \
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
