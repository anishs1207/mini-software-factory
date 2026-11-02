#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
adapter="$(mktemp /tmp/briefing-bad-adapter.XXXXXX)"
trap 'rm -f -- "$adapter"' EXIT
cat > "$adapter" <<'ADAPTER'
#!/usr/bin/env bash
printf '{"success":true,"new_count":0}\n'
ADAPTER
if python3 "$repo_dir/factory-tests/acceptance.py" "$adapter" >/dev/null 2>&1; then
  echo 'Acceptance test incorrectly passed an adapter that reports zero on the first run.' >&2
  exit 1
fi
echo 'Acceptance test correctly rejected a false zero-new first run.'
