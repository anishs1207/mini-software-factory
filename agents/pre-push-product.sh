#!/usr/bin/env bash
set -Eeuo pipefail

while read -r local_ref local_oid remote_ref remote_oid; do
  if [[ "$remote_ref" == "refs/heads/main" ]]; then
    echo "Push blocked: direct push to refs/heads/main is not allowed." >&2
    echo "All changes must reach main through a PR and human merge." >&2
    exit 1
  fi
  case "$local_ref" in
    refs/heads/agent/builder1/issue-*|refs/heads/agent/builder2/issue-*) ;;
    *) continue ;;
  esac
  base="$(git merge-base "$local_oid" origin/main)"
  generated="$(git rev-list --objects "$base..$local_oid" -- node_modules .next | wc -l)"
  if (( generated > 0 )); then
    echo "Push blocked: $local_ref contains node_modules/ or .next/ in its commit history." >&2
    echo 'Clean unpublished generated files from branch history before pushing.' >&2
    exit 1
  fi
done
