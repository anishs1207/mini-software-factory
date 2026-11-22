#!/usr/bin/env bash
set -Eeuo pipefail

default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
default_branch="${default_branch#origin/}"
if [[ -z "$default_branch" ]]; then
  default_branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || true)"
fi
[[ -n "$default_branch" ]] || { echo 'Cannot determine the default branch; push blocked.' >&2; exit 1; }
generated_paths=(node_modules .next dist build target .venv __pycache__)
if [[ -n "${FACTORY_GENERATED_PATHS:-}" ]]; then
  read -r -a generated_paths <<< "$FACTORY_GENERATED_PATHS"
fi
[[ ${#generated_paths[@]} -gt 0 ]] || { echo 'Generated path list is empty; push blocked.' >&2; exit 1; }
while read -r local_ref local_oid remote_ref remote_oid; do
  if [[ "$remote_ref" == "refs/heads/$default_branch" ]]; then
    echo "Push blocked: direct push to refs/heads/$default_branch is not allowed." >&2
    echo "All changes must reach $default_branch through a PR and human merge." >&2
    exit 1
  fi
  case "$local_ref" in
    refs/heads/agent/builder1/issue-*|refs/heads/agent/builder2/issue-*) ;;
    *) continue ;;
  esac
  base="$(git merge-base "$local_oid" "origin/$default_branch")"
  if git rev-list --objects "$base..$local_oid" -- "${generated_paths[@]}" \
    | awk 'NR == 1 { found = 1 } END { exit !found }'; then
    echo "Push blocked: $local_ref contains generated files in its commit history." >&2
    echo 'Clean unpublished generated files from branch history before pushing.' >&2
    exit 1
  fi
done
