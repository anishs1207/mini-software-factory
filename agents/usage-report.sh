#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage_dir="$repo_dir/.local-evidence/usage"
[[ -d "$usage_dir" ]] || { echo 'No usage records yet. Run an agent first.' >&2; exit 1; }
printf 'role\tissue\trun\tmodel\ttokens\texit\tevidence\n'
shopt -s nullglob
for meta in "$usage_dir"/*.meta.json; do
  base="${meta%.meta.json}"
  if [[ -s "$base.hermes.json" ]]; then
    jq -r --slurpfile usage "$base.hermes.json" \
      '[.role, (.issue | if . == "" then "startup" else . end), .run_id, ($usage[0].model // "unknown"), (($usage[0].total_including_auxiliary.total_tokens // $usage[0].total_tokens // "unknown") | tostring), (.exit_code | tostring), ($usage[0].session_id // "local usage JSON")] | @tsv' "$meta"
  else
    jq -r '[.role, (.issue | if . == "" then "startup" else . end), .run_id, "see gateway snapshots", "unavailable", (.exit_code | tostring), "local before/after usage JSON"] | @tsv' "$meta"
  fi
done
