#!/usr/bin/env bash
# Return success only when every path read from stdin belongs to the factory.
set -Eeuo pipefail
while IFS= read -r path; do
  path="${path%$'\r'}"
  [[ -n "$path" ]] || continue
  case "$path" in
    .github/*|agents/*|code-review/*|prompts/*|tests/*|infra/*|examples/*|deliverables/*|spec/*|\
    .gitignore|README.md|SETUP.md|SECURITY.md|CONTRIBUTING.md|\
    PRODUCT_BRIEF.md|instructions-to-agent.md|manager.sh|manager.ps1|DELIVERY.md) ;;
    *) exit 1 ;;
  esac
done
