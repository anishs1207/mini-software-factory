#!/usr/bin/env bash
set -Eeuo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export GH_TOKEN=secret OPENROUTER_API_KEY=secret OLLAMA_API_KEY=secret
bash "$repo_dir/agents/run-product-command.sh" bash -c \
  '[[ -z "${GH_TOKEN:-}" && -z "${OPENROUTER_API_KEY:-}" && -z "${OLLAMA_API_KEY:-}" && -n "${HOME:-}" ]]'
echo 'Product command does not inherit agent credentials.'
