#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/briefing-release-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/source/agents" "$test_root/bin"
git init --bare "$test_root/origin.git" >/dev/null
git init -b main "$test_root/source" >/dev/null
git -C "$test_root/source" config user.name 'Factory Test'
git -C "$test_root/source" config user.email 'factory-test@example.invalid'
git -C "$test_root/source" remote add origin "$test_root/origin.git"
cp "$repo_dir/agents/release-product.sh" "$test_root/source/agents/release-product.sh"
cat > "$test_root/source/product-service.sh" <<'SERVICE'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ -z "${GH_TOKEN:-}" && -z "${OPENROUTER_API_KEY:-}" ]]
case "$1" in
  prepare) : ;;
  restart) printf '%s\n' "$(readlink -f "$FACTORY_CURRENT_DIR")" > "$FACTORY_RELEASE_ROOT/last-restart" ;;
  smoke) [[ ! -f "$FACTORY_CURRENT_DIR/FAIL_SMOKE" ]] ;;
  stop) : ;;
  *) exit 2 ;;
esac
SERVICE
cat > "$test_root/bin/gh" <<'GH'
#!/usr/bin/env bash
[[ "$*" == 'repo view --json defaultBranchRef -q .defaultBranchRef.name' ]] || exit 2
printf 'main\n'
GH
chmod +x "$test_root/bin/gh"
export PATH="$test_root/bin:$PATH"
export FACTORY_RELEASE_ROOT="$test_root/release"
export GH_TOKEN=must-not-reach-product
export OPENROUTER_API_KEY=must-not-reach-product

touch "$test_root/source/FAIL_SMOKE"
git -C "$test_root/source" add .
git -C "$test_root/source" commit -m 'initial broken release' >/dev/null
initial_bad="$(git -C "$test_root/source" rev-parse HEAD)"
git -C "$test_root/source" push -u origin main >/dev/null
if bash "$test_root/source/agents/release-product.sh" deploy "$initial_bad"; then
  echo 'Broken first release was accepted.' >&2; exit 1
fi
[[ ! -e "$FACTORY_RELEASE_ROOT/current" && ! -L "$FACTORY_RELEASE_ROOT/current" ]]

git -C "$test_root/source" rm FAIL_SMOKE >/dev/null
git -C "$test_root/source" commit -m 'good release' >/dev/null
good="$(git -C "$test_root/source" rev-parse HEAD)"
git -C "$test_root/source" push origin main >/dev/null
bash "$test_root/source/agents/release-product.sh" deploy "$good"
printf 'preserved\n' > "$FACTORY_RELEASE_ROOT/data/run-history"

touch "$test_root/source/FAIL_SMOKE"
git -C "$test_root/source" add FAIL_SMOKE
git -C "$test_root/source" commit -m 'broken release' >/dev/null
bad="$(git -C "$test_root/source" rev-parse HEAD)"
git -C "$test_root/source" push origin main >/dev/null
if bash "$test_root/source/agents/release-product.sh" deploy "$bad"; then
  echo 'Broken release was accepted.' >&2; exit 1
fi
[[ "$(readlink -f "$FACTORY_RELEASE_ROOT/current")" == "$FACTORY_RELEASE_ROOT/releases/$good" ]]
[[ "$(cat "$FACTORY_RELEASE_ROOT/data/run-history")" == preserved ]]

git -C "$test_root/source" rm FAIL_SMOKE >/dev/null
git -C "$test_root/source" commit -m 'repaired release' >/dev/null
repaired="$(git -C "$test_root/source" rev-parse HEAD)"
git -C "$test_root/source" push origin main >/dev/null
bash "$test_root/source/agents/release-product.sh" deploy "$repaired"
[[ "$(readlink -f "$FACTORY_RELEASE_ROOT/previous")" == "$FACTORY_RELEASE_ROOT/releases/$good" ]]
bash "$test_root/source/agents/release-product.sh" rollback
[[ "$(readlink -f "$FACTORY_RELEASE_ROOT/current")" == "$FACTORY_RELEASE_ROOT/releases/$good" ]]
[[ "$(cat "$FACTORY_RELEASE_ROOT/data/run-history")" == preserved ]]
echo 'Release recovery passed: failed deploy restored, explicit rollback worked, data persisted.'
