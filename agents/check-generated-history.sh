#!/usr/bin/env bash
# Exit 0 when generated files appear between BASE and HEAD in a repository.
set -Eeuo pipefail
[[ $# -eq 3 ]] || { echo 'Usage: check-generated-history.sh REPO BASE HEAD' >&2; exit 2; }
repo="$1" base="$2" head="$3"
paths=(node_modules .next dist build target .venv __pycache__)
if [[ -n "${FACTORY_GENERATED_PATHS:-}" ]]; then
  read -r -a paths <<< "$FACTORY_GENERATED_PATHS"
fi
[[ ${#paths[@]} -gt 0 ]] || { echo 'Generated path list is empty.' >&2; exit 2; }
git -C "$repo" rev-list --objects "$base..$head" -- "${paths[@]}" \
  | awk 'NR == 1 { found = 1 } END { exit !found }'
