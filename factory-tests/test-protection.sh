#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/briefing-protection-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT
cat > "$test_root/gh" <<'GH'
#!/usr/bin/env bash
set -Eeuo pipefail
case "$1" in
  auth) [[ "$2" == status ]] ;;
  repo) [[ "$2" == view ]] && printf '{"nameWithOwner":"example/briefing","isPrivate":false,"defaultBranchRef":{"name":"main"}}\n' ;;
  api)
    if [[ "${2:-}" == --method ]]; then
      [[ "$3" == PUT && "$4" == repos/example/briefing/branches/main/protection && "$5" == --input ]]
      jq -e '.required_status_checks.strict and (.required_status_checks.contexts | index("verify") != null and index("factory-gates") != null) and .enforce_admins and (.required_pull_request_reviews.required_approving_review_count == 1) and (.allow_force_pushes == false)' "$6" >/dev/null
    else
      printf '{"required_status_checks":{"contexts":["verify","factory-gates"]},"required_pull_request_reviews":{"required_approving_review_count":1},"enforce_admins":{"enabled":true},"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false}}\n'
    fi ;;
  *) exit 2 ;;
esac
GH
chmod +x "$test_root/gh"
PATH="$test_root:$PATH" bash "$repo_dir/agents/protect-repo.sh"
