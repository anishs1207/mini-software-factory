#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
[[ -n "${BASE_REF:-}" ]] || { echo 'BASE_REF is required.' >&2; exit 2; }
git fetch --no-tags origin "$BASE_REF"
base_commit="$(git merge-base HEAD "origin/$BASE_REF")"
git diff --check "$base_commit" HEAD
bash -n agent-setup.sh agents/*.sh
[[ -f product-check.sh ]] || { echo 'Product verification is missing: add product-check.sh in the builder PR.' >&2; exit 1; }
bash product-check.sh
if [[ -f product-acceptance.sh ]]; then
  acceptance_test="$(mktemp --suffix=.py)"
  trap 'rm -f "$acceptance_test"' EXIT
  git show "origin/$BASE_REF:factory-tests/acceptance.py" > "$acceptance_test"
  python3 "$acceptance_test" "$repo_dir/product-acceptance.sh"
fi
