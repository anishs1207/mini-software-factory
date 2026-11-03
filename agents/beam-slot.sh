#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -gt 0 ]] || { echo 'Usage: beam-slot.sh COMMAND [ARG...]' >&2; exit 2; }
cooldown="${FACTORY_BEAM_COOLDOWN_SECONDS:-60}"
[[ "$cooldown" =~ ^[0-9]+$ ]] && (( cooldown <= 3600 )) || {
  echo 'FACTORY_BEAM_COOLDOWN_SECONDS must be between 0 and 3600.' >&2
  exit 2
}
mkdir -p "$HOME/.cache"
umask 077
exec 9>"$HOME/.cache/briefing-beam.lock"
flock 9
last_file="$HOME/.cache/briefing-beam-last-finish"
if [[ -f "$last_file" ]]; then
  read -r last_finish < "$last_file" || last_finish=0
  [[ "$last_finish" =~ ^[0-9]+$ ]] || last_finish=0
  now="$(date -u +%s%3N)"
  remaining=$((cooldown * 1000 - now + last_finish))
  if (( remaining > 0 )); then
    printf -v delay '%d.%03d' "$((remaining / 1000))" "$((remaining % 1000))"
    echo "Waiting ${delay}s before the next Beam agent run." >&2
    sleep "$delay"
  fi
fi
trap 'date -u +%s%3N > "$last_file"' EXIT
"$@" 9>&-
