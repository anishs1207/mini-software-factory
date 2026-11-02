#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
slug="${1:-}"
visibility="${2:-private}"
[[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo 'Usage: agents/publish-repo.sh OWNER/REPO [private|public]' >&2; exit 2; }
[[ "$visibility" == private || "$visibility" == public ]] || { echo 'Visibility must be private or public.' >&2; exit 2; }
command -v gh >/dev/null
gh auth status >/dev/null
git rev-parse --verify HEAD >/dev/null
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit your intended files before publishing.' >&2; exit 1; }
[[ -z "$(git remote)" ]] || { echo 'A remote already exists; inspect it before publishing.' >&2; exit 1; }
if git ls-files | grep -Eq '(^|/)(secrets\.env|terraform\.tfvars|terraform\.tfstate.*|todo\.md)$|(^|/)\.local-evidence/'; then
  echo 'A local secret, state, or evidence file is tracked. Remove it from the index first.' >&2
  exit 1
fi
gh repo create "$slug" "--$visibility" --source=. --remote=origin --push
