#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$repo_dir/.local-evidence"
scratch="$(mktemp -d "$repo_dir/.local-evidence/test-campaign.XXXXXX")"
if command -v cygpath >/dev/null 2>&1; then scratch="$(cygpath -u "$scratch")"; fi
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/home"
real_git="$(command -v git)"
export REAL_GIT="$real_git"
cat > "$scratch/bin/gh" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  'repo view example/product --json nameWithOwner --jq .nameWithOwner') printf 'example/product\n' ;;
  'repo view example/product --json defaultBranchRef --jq .defaultBranchRef.name') printf 'main\n' ;;
  'issue list --state open --label '* ) printf '0\n' ;;
  'repo set-default example/product'|'label create product:'*) ;;
  *) echo "Unexpected gh command: $*" >&2; exit 1 ;;
esac
MOCK
cat > "$scratch/bin/git" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == -C && "$3" == fetch ]]; then exit 0; fi
exec "$REAL_GIT" "$@"
MOCK
chmod +x "$scratch/bin/gh"
chmod +x "$scratch/bin/git"
export HOME="$scratch/home" PATH="$scratch/bin:$PATH"
product_dir="$HOME/factory-products/example/product"
mkdir -p "$product_dir"
"$real_git" init -b main "$product_dir" >/dev/null
"$real_git" -C "$product_dir" remote add origin https://github.com/example/product
printf '# Product\nRepository: https://github.com/example/product\n' > "$scratch/spec.md"
cd "$repo_dir"
bash agents/start-campaign.sh ".local-evidence/$(basename "$scratch")/spec.md"
expected="product:$(sha256sum "$scratch/spec.md" | cut -c1-12)"
[[ "$(cat "$HOME/.config/briefing-agents/campaign-label")" == "$expected" ]]
[[ "$(cat "$HOME/.config/briefing-agents/queue-armed")" == "$expected" ]]
[[ "$(cat "$HOME/.config/briefing-agents/spec-path")" == ".local-evidence/$(basename "$scratch")/spec.md" ]]
[[ "$(cat "$HOME/.config/briefing-agents/repo-slug")" == example/product ]]
source agents/product-repository.sh
factory_product_context "$repo_dir"
[[ "$product_dir" == "$HOME/factory-products/example/product" && "$GH_REPO" == example/product ]]
printf '# Outside\n' > "$scratch/outside.md"
if bash agents/start-campaign.sh "$scratch/outside.md" 2>/dev/null; then
  echo 'Campaign accepted a spec outside the repository.' >&2
  exit 1
fi
echo 'Campaign activation and path guard passed.'
