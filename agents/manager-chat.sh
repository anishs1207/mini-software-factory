#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
credentials="$HOME/.config/briefing-agents/credentials.env"
[[ -f "$credentials" ]] || { echo 'Run the VM agent bootstrap first.' >&2; exit 1; }
set -a
source "$credentials"
set +a
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
mkdir -p "$HOME/.cache"

# Interactive Hermes does not support --usage-file. Run each user turn as a
# resumed one-shot so its provider usage can be recorded without losing chat
# history or the manager's tools.
usage_dir="$repo_dir/.local-evidence/usage"
mkdir -p "$usage_dir"
chmod 700 "$repo_dir/.local-evidence" "$usage_dir"
umask 077
prompt="$(mktemp)"
trap 'rm -f "$prompt"' EXIT
session_ref=""
turn=0
printf 'Manager ready. Enter a request (for example: implement ./spec.md). Type /exit to leave.\n'
while IFS= read -r -e -p 'manager> ' query; do
  [[ -n "${query//[[:space:]]/}" ]] || continue
  [[ "$query" != /exit && "$query" != /quit ]] || break
  turn=$((turn + 1))
  printf '%s\n' "$query" > "$prompt"
  run_id="$(date -u +%Y%m%dT%H%M%SZ)-manager-chat-$$-$turn"
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  task="Manager chat request $turn"
  purpose="manager_conversation"
  issue=""
  if [[ "$query" =~ ^[[:space:]]*implement[[:space:]]+ ]]; then
    purpose="spec_planning"
    task="Plan and ticket product spec"
  elif [[ "$query" =~ \#([0-9]+) ]]; then
    issue="${BASH_REMATCH[1]}"
    purpose="issue_management"
    task="Manager chat about issue #$issue"
  fi
  if [[ "$purpose" == spec_planning ]]; then
    unset GH_REPO
  elif [[ -f "$HOME/.config/briefing-agents/repo-slug" ]]; then
    export GH_REPO="$(cat "$HOME/.config/briefing-agents/repo-slug")"
  fi
  resume=()
  [[ -z "$session_ref" ]] || resume=(--resume "$session_ref")
  # Each active turn shares the Beam slot with queued agents.
  if bash "$repo_dir/agents/beam-slot.sh" hermes -p manager --usage-file "$usage_dir/$run_id.hermes.json" \
    chat --toolsets coding --oneshot --query-file "$prompt" "${resume[@]}"; then
    result=0
  else
    result=$?
  fi
  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  python3 "$repo_dir/agents/activity.py" record \
    --usage-dir "$usage_dir" --run-id "$run_id" --agent manager --issue "$issue" \
    --task "$task" --purpose "$purpose" --source-stage interactive-chat \
    --started-at "$started_at" --finished-at "$finished_at" --exit-code "$result"
  python3 "$repo_dir/agents/activity.py" comment --usage-dir "$usage_dir" --run-id "$run_id"
  if [[ -f "$usage_dir/$run_id.hermes.json" ]]; then
    session_id="$(jq -er '.session_id | select(type == "string" and length > 0)' \
      "$usage_dir/$run_id.hermes.json" 2>/dev/null || true)"
    session_ref="${session_id:-latest}"
  fi
  if [[ "$result" -ne 0 ]]; then
    printf 'Manager turn failed (exit %s); usage was saved when available.\n' "$result" >&2
  fi
done
