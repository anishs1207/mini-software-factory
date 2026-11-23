#!/usr/bin/env bash
set -Eeuo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
printf 'agents/dispatch.sh\ncode-review/src/cli.ts\nprompts/1-code-review.md\ninfra/main.tf\nREADME.md\n' \
  | bash "$repo_dir/agents/product-paths.sh"
if printf 'agents/dispatch.sh\napp/main.py\n' \
  | bash "$repo_dir/agents/product-paths.sh"; then
  echo 'A product change was classified as factory-only.' >&2
  exit 1
fi
echo 'Factory and product path classification passed.'
