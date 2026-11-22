#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/briefing-autodeploy-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/releases"

git init --bare "$test_root/origin.git" >/dev/null
git init -b main "$test_root/source" >/dev/null
git -C "$test_root/source" config user.name 'Factory Test'
git -C "$test_root/source" config user.email 'factory-test@example.invalid'
git -C "$test_root/source" remote add origin "$test_root/origin.git"
printf 'baseline\n' > "$test_root/source/product.txt"
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/source/product-service.sh"
git -C "$test_root/source" add product.txt product-service.sh
git -C "$test_root/source" commit -m baseline >/dev/null
baseline="$(git -C "$test_root/source" rev-parse HEAD)"
git -C "$test_root/source" push -u origin main >/dev/null
mkdir "$test_root/releases/$baseline"
ln -s "$test_root/releases/$baseline" "$test_root/current"

git -C "$test_root/source" switch -c feature >/dev/null
printf 'feature\n' >> "$test_root/source/product.txt"
git -C "$test_root/source" commit -am feature >/dev/null
head_sha="$(git -C "$test_root/source" rev-parse HEAD)"
git -C "$test_root/source" switch main >/dev/null
git -C "$test_root/source" merge --no-ff feature -m 'Merge reviewed PR' >/dev/null
merge_sha="$(git -C "$test_root/source" rev-parse HEAD)"
git -C "$test_root/source" push origin main >/dev/null

cat > "$test_root/bin/gh" <<'GH'
#!/usr/bin/env bash
set -Eeuo pipefail
case "$*" in
  'repo view --json nameWithOwner --jq .nameWithOwner') echo example/repo ;;
  'repo view --json defaultBranchRef --jq .defaultBranchRef.name') echo main ;;
  "api repos/example/repo/commits/$TEST_MERGE_SHA/pulls?per_page=100")
    printf '[{"number":1,"merged_at":"2026-01-01T00:00:00Z","merge_commit_sha":"%s","head":{"sha":"%s"}}]\n' "$TEST_MERGE_SHA" "$TEST_HEAD_SHA" ;;
  "api repos/example/repo/commits/$TEST_HEAD_SHA/status")
    printf '{"statuses":[{"context":"factory-gates","state":"%s"}]}\n' "${TEST_GATE_STATE:-success}" ;;
  "api repos/example/repo/commits/$TEST_HEAD_SHA/check-runs?per_page=100")
    printf '{"check_runs":[{"name":"verify","status":"completed","conclusion":"%s","app":{"slug":"github-actions"}}]}\n' "${TEST_VERIFY_STATE:-success}" ;;
  "api repos/example/repo/commits/$TEST_FACTORY_MERGE_SHA/pulls?per_page=100")
    printf '[{"number":2,"merged_at":"2026-01-02T00:00:00Z","merge_commit_sha":"%s","head":{"sha":"%s"}}]\n' "$TEST_FACTORY_MERGE_SHA" "$TEST_FACTORY_HEAD_SHA" ;;
  "api repos/example/repo/commits/$TEST_FACTORY_HEAD_SHA/status")
    printf '{"statuses":[{"context":"factory-gates","state":"%s"}]}\n' "${TEST_FACTORY_GATE_STATE:-pending}" ;;
  "api repos/example/repo/commits/$TEST_FACTORY_HEAD_SHA/check-runs?per_page=100")
    printf '{"check_runs":[{"name":"verify","status":"completed","conclusion":"%s","app":{"slug":"github-actions"}}]}\n' "${TEST_FACTORY_VERIFY_STATE:-success}" ;;
  api\ repos/example/repo/commits/*/pulls?per_page=100) echo '[]' ;;
  *) echo "Unexpected gh command: $*" >&2; exit 1 ;;
esac
GH
chmod +x "$test_root/bin/gh"

export TEST_MERGE_SHA="$merge_sha" TEST_HEAD_SHA="$head_sha"
export TEST_FACTORY_MERGE_SHA=not-created TEST_FACTORY_HEAD_SHA=not-created
export FACTORY_AUTODEPLOY_REPO_DIR="$test_root/source"
export FACTORY_AUTODEPLOY_CURRENT_OVERRIDE="$baseline"
export FACTORY_RELEASE_ROOT="$test_root"
export FACTORY_AUTODEPLOY_STATE_DIR="$test_root/state"
export FACTORY_AUTODEPLOY_LOCK_FILE="$test_root/autodeploy.lock"
export FACTORY_AUTODEPLOY_BIN_DIR="$test_root/bin"
export FACTORY_AUTODEPLOY_DRY_RUN=1

output="$(bash "$repo_dir/agents/auto-deploy.sh")"
[[ "$output" == *"Eligible for deployment: $merge_sha"* ]]

export TEST_GATE_STATE=pending
output="$(bash "$repo_dir/agents/auto-deploy.sh")"
[[ "$output" == *'lacks a successful factory-gates status'* ]]
export TEST_GATE_STATE=success

export TEST_VERIFY_STATE=failure
output="$(bash "$repo_dir/agents/auto-deploy.sh")"
[[ "$output" == *'lacks a successful verify check'* ]]
export TEST_VERIFY_STATE=success

git -C "$test_root/source" switch -c factory >/dev/null
mkdir -p "$test_root/source/agents"
printf 'guard\n' > "$test_root/source/agents/guard.sh"
git -C "$test_root/source" add agents/guard.sh
git -C "$test_root/source" commit -m 'Factory guard' >/dev/null
factory_head_sha="$(git -C "$test_root/source" rev-parse HEAD)"
git -C "$test_root/source" switch main >/dev/null
git -C "$test_root/source" merge --no-ff factory -m 'Merge factory PR' >/dev/null
factory_merge_sha="$(git -C "$test_root/source" rev-parse HEAD)"
git -C "$test_root/source" push origin main >/dev/null
export TEST_FACTORY_HEAD_SHA="$factory_head_sha" TEST_FACTORY_MERGE_SHA="$factory_merge_sha"
output="$(bash "$repo_dir/agents/auto-deploy.sh")"
[[ "$output" == *'lacks a successful factory-gates status'* ]]
export TEST_FACTORY_GATE_STATE=success
output="$(bash "$repo_dir/agents/auto-deploy.sh")"
[[ "$output" == *"Eligible for deployment: $factory_merge_sha"* ]]
export TEST_FACTORY_VERIFY_STATE=failure
output="$(bash "$repo_dir/agents/auto-deploy.sh")"
[[ "$output" == *'lacks a successful verify check'* ]]
export TEST_FACTORY_VERIFY_STATE=success

printf 'direct\n' >> "$test_root/source/product.txt"
git -C "$test_root/source" commit -am 'Direct main commit' >/dev/null
git -C "$test_root/source" push origin main >/dev/null
if output="$(bash "$repo_dir/agents/auto-deploy.sh" 2>&1)"; then
  echo 'Direct main commit was accepted for deployment.' >&2
  exit 1
fi
[[ "$output" == *'Unreviewed direct main commit'* ]]
echo 'Auto-deploy gate passed: merged PR accepted, missing gates held, direct main commit rejected.'
