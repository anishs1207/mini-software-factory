#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
role="${1:-}"
issue="${2:-}"
case "$role" in
  manager|ingest|page|reviewer|tester) ;;
  *) echo 'Usage: agents/dispatch.sh {manager|ingest|page|reviewer|tester} [issue-number]' >&2; exit 2 ;;
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

# Serialize all model invocations, including the manager, for the free tier.
mkdir -p "$HOME/.cache"
if [[ "${BRIEFING_MODEL_LOCK_HELD:-}" != 1 ]]; then
  exec 9>"$HOME/.cache/briefing-agent.lock"
  flock -n 9 || { echo 'Another agent is using the single-request model tier.' >&2; exit 1; }
fi

work_dir="$repo_dir"
if [[ "$role" == ingest || "$role" == page ]]; then
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
{
  printf 'Repository: %s\nWork directory: %s\nRole: %s\n' "$repo_dir" "$work_dir" "$role"
  if [[ "$work_dir" != "$repo_dir" ]]; then
    printf 'Do all implementation commands in the work directory. Its branch is already created for this issue.\n'
  fi
  printf 'Read instructions-to-agent.md, agents/README.md, and your role instructions. Use GitHub Issues and PRs for all handoffs. Do not print secrets.\n'
  if [[ -n "$issue" ]]; then
    gh issue view "$issue" --json number,title,body,url,author,labels,assignees,comments \
      | jq -er --arg actor "$trusted_actor" 'select(.author.login == $actor) | "Issue #\(.number): \(.title)\nURL: \(.url)\n\n\(.body)\n\nTrusted comments:\n" + ([.comments[]? | select(.author.login == $actor) | "- " + .author.login + ": " + .body] | join("\n"))'
  else
    printf 'Start with ISSUES.md. Create the initial ticket trail, then assign and dispatch one issue at a time.\n'
  fi
} > "$prompt"

case "$role" in
  ingest|page)
    openclaw gateway usage-cost --agent "$role" --json > "$usage_dir/$run_id.before.json" 2>/dev/null || true
    if openclaw agent --agent "$role" --message-file "$prompt" --json > "$usage_dir/$run_id.openclaw.json"; then result=0; else result=$?; fi
    jq -r 'if type == "object" then (.final // .error.message // .status // "Agent run finished") else . end' \
      "$usage_dir/$run_id.openclaw.json" 2>/dev/null || cat "$usage_dir/$run_id.openclaw.json"
    openclaw gateway usage-cost --agent "$role" --json > "$usage_dir/$run_id.after.json" 2>/dev/null || true
    ;;
  *)
    if hermes -p "$role" chat --toolsets coding --oneshot --query-file "$prompt" \
      --usage-file "$usage_dir/$run_id.hermes.json"; then result=0; else result=$?; fi
    ;;
esac
finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 "$repo_dir/agents/activity.py" record \
  --usage-dir "$usage_dir" --run-id "$run_id" --agent "$role" --issue "${issue:-}" \
  --started-at "$started_at" --finished-at "$finished_at" --exit-code "$result" \
  --source-stage "${BRIEFING_SOURCE_STAGE:-manual}"
if [[ -n "$issue" ]]; then
  activity_comment="$(python3 "$repo_dir/agents/activity.py" comment --usage-dir "$usage_dir" --run-id "$run_id")"
  gh issue comment "$issue" --body "$activity_comment" >/dev/null
fi
printf 'ACTIVITY: %s\n' "$usage_dir/$run_id.activity.json"
exit "$result"
