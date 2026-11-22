#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/home/.config/briefing-agents" "$scratch/bin"
cat > "$scratch/bin/gh" <<'MOCK'
#!/usr/bin/env bash
echo 'The idle queue contacted GitHub.' >&2
exit 99
MOCK
chmod +x "$scratch/bin/gh"
export HOME="$scratch/home" PATH="$scratch/bin:$PATH"
bash "$repo_dir/agents/poll-issues.sh"
printf 'product:123456789abc\n' > "$HOME/.config/briefing-agents/campaign-label"
printf 'spec/PRODUCT_SPEC.md\n' > "$HOME/.config/briefing-agents/spec-path"
bash "$repo_dir/agents/poll-issues.sh"
echo 'Unarmed queue exited without contacting GitHub or a model.'
