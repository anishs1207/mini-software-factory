#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
[[ -n "${BASE_REF:-}" ]] || { echo 'BASE_REF is required.' >&2; exit 2; }
git fetch --no-tags origin "$BASE_REF"
base_commit="$(git merge-base HEAD "origin/$BASE_REF")"
git diff --check "$base_commit" HEAD
bash -n agents/setup/agent-setup.sh agents/*.sh
python3 -m py_compile agents/setup/bootstrap-vm.py agents/setup/apply.py
python3 factory-tests/test-bootstrap.py
python3 factory-tests/test-activity.py
python3 factory-tests/test-trace-report.py
bash factory-tests/test-protection.sh
bash factory-tests/test-rejection.sh
bash factory-tests/test-release.sh
if [[ -f product-check.sh ]]; then
  bash product-check.sh
elif git diff --name-only "$base_commit" HEAD | grep -Ev '^(\.github/|agents/|factory-tests/|infra/|spec/|deliverables/|\.gitignore$|README\.md$|PRODUCT_BRIEF\.md$|instructions-to-agent\.md$|DELIVERY\.md$)' | grep -q .; then
  echo 'Product verification is missing: add product-check.sh in the builder PR.' >&2
  exit 1
else
  echo 'Factory-only PR: no product-check.sh exists yet.'
fi
if [[ -f product-acceptance.sh ]] || git cat-file -e "origin/$BASE_REF:product-acceptance.sh" 2>/dev/null; then
  [[ -f product-acceptance.sh ]] || { echo 'Product acceptance adapter was removed.' >&2; exit 1; }
  acceptance_test="$(mktemp --suffix=.py)"
  trap 'rm -f "$acceptance_test"' EXIT
  git show "origin/$BASE_REF:factory-tests/acceptance.py" > "$acceptance_test"
  python3 "$acceptance_test" "$repo_dir/product-acceptance.sh"
fi
