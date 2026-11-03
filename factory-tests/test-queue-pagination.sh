#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/home/.config/briefing-agents" "$scratch/bin"
printf 'product:123456789abc\n' > "$scratch/home/.config/briefing-agents/campaign-label"
cat > "$scratch/bin/gh" <<'GH'
#!/usr/bin/env bash
[[ "$1" == api && "$2" == --paginate ]] || exit 2
[[ "$3" == 'repos/example/repo/issues?state=open&labels=product:123456789abc,factory:ready&per_page=100' ]] || exit 2
python3 - <<'PY'
import json
for start, end in ((1, 101), (101, 151)):
    rows = [{"number": number, "labels": []} for number in range(start, end)]
    if start == 101:
        rows.append({"number": 999, "pull_request": {"url": "https://example.invalid/pr"}})
    print(json.dumps(rows))
PY
GH
chmod +x "$scratch/bin/gh"
export HOME="$scratch/home" PATH="$scratch/bin:$PATH"
repo_slug=example/repo
source "$repo_dir/agents/queue-guards.sh"
rows="$(stage_issues open factory:ready)"
[[ "$(jq 'length' <<< "$rows")" == 150 ]]
[[ "$(jq -r '.[-1].number' <<< "$rows")" == 150 ]]
echo 'Queue stage scan includes later pages and excludes pull requests.'
