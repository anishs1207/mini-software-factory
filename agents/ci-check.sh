#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
if [[ -n "${BASE_REF:-}" ]]; then
  git fetch --no-tags origin "$BASE_REF"
  base_commit="$(git merge-base HEAD "origin/$BASE_REF")"
else
  base_commit="$(git rev-parse HEAD^ 2>/dev/null || git rev-parse HEAD)"
fi
git diff --check "$base_commit" HEAD
mapfile -d '' shell_scripts < <(find agents infra examples/briefing-product -type f -name '*.sh' -print0)
bash -n "${shell_scripts[@]}"
python3 -m compileall -q agents tests
python3 tests/test-bootstrap.py
python3 tests/test-beam-slot.py
python3 tests/test-local-prereqs.py
python3 tests/test-pr-authors.py
python3 tests/test-pre-push-product.py
python3 tests/test-dispatch-identity.py
python3 tests/test-activity.py
python3 tests/test-watchdog.py
python3 tests/test-trace-report.py
bash tests/test-campaign.sh
bash tests/test-campaign-arm.sh
bash tests/test-auto-deploy.sh
bash tests/test-queue-idle.sh
bash tests/test-queue-pagination.sh
bash tests/test-product-env.sh
bash tests/test-release.sh
if [[ -f product-check.sh ]]; then
  bash product-check.sh
elif git diff --name-only "$base_commit" HEAD | grep -Ev '^(\.github/|agents/|tests/|infra/|spec/|examples/|deliverables/|\.gitignore$|README\.md$|SETUP\.md$|PRODUCT_BRIEF\.md$|instructions-to-agent\.md$|manager\.(sh|ps1)$|DELIVERY\.md$)' | grep -q .; then
  echo 'Product verification is missing: add product-check.sh in the builder PR.' >&2
  exit 1
else
  echo 'Factory-only PR: no product-check.sh exists yet.'
fi
