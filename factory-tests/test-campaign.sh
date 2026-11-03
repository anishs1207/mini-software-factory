#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/home"
cat > "$scratch/bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1 $2" == 'issue list' ]]; then printf '0\n'; fi
MOCK
chmod +x "$scratch/bin/gh"
export HOME="$scratch/home" PATH="$scratch/bin:$PATH"
cd "$repo_dir"
bash agents/start-campaign.sh spec/README.md
expected="product:$(sha256sum spec/README.md | cut -c1-12)"
[[ "$(cat "$HOME/.config/briefing-agents/campaign-label")" == "$expected" ]]
[[ "$(cat "$HOME/.config/briefing-agents/queue-armed")" == "$expected" ]]
[[ "$(cat "$HOME/.config/briefing-agents/spec-path")" == 'spec/README.md' ]]
printf '# Outside\n' > "$scratch/outside.md"
if bash agents/start-campaign.sh "$scratch/outside.md" 2>/dev/null; then
  echo 'Campaign accepted a spec outside the repository.' >&2
  exit 1
fi
echo 'Campaign activation and path guard passed.'
