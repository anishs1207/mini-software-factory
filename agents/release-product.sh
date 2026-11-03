#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
action="${1:-}"
release_root="${FACTORY_RELEASE_ROOT:-$HOME/factory-product}"
mkdir -p "$release_root/releases" "$release_root/data"
chmod 700 "$release_root" "$release_root/data"
mkdir -p "$release_root/runtime-home"
chmod 700 "$release_root/runtime-home"
exec 9>"$release_root/release.lock"
flock -n 9 || { echo 'Another product release operation is running.' >&2; exit 1; }
export FACTORY_RELEASE_ROOT="$release_root"
export FACTORY_DATA_DIR="$release_root/data"
export FACTORY_CURRENT_DIR="$release_root/current"

current_target() {
  if [[ -L "$release_root/current" ]]; then readlink -f "$release_root/current"; fi
}

previous_target() {
  if [[ -L "$release_root/previous" ]]; then readlink -f "$release_root/previous"; fi
}

switch_link() {
  local name="$1" target="$2"
  ln -sfn "$target" "$release_root/.$name-next"
  mv -Tf "$release_root/.$name-next" "$release_root/$name"
}

run_service() {
  local target="$1" command="$2"
  [[ -f "$target/product-service.sh" ]] || { echo "Missing product-service.sh in $target" >&2; return 1; }
  # Product code needs its own runtime configuration, never agent credentials.
  local -a product_env=(
    "PATH=$PATH" "HOME=$release_root/runtime-home" "USER=$(id -un)"
    "FACTORY_RELEASE_ROOT=$release_root" "FACTORY_DATA_DIR=$release_root/data"
    "FACTORY_CURRENT_DIR=$release_root/current"
  )
  [[ -z "${XDG_RUNTIME_DIR:-}" ]] || product_env+=("XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR")
  env -i "${product_env[@]}" bash "$target/product-service.sh" "$command"
}

restore_after_failure() {
  local prior="$1"
  if [[ -n "$prior" ]]; then
    switch_link current "$prior"
    run_service "$prior" restart
    run_service "$prior" smoke
    echo "Restored previous release: $prior" >&2
  else
    # A failed first deploy must not advertise the broken revision as current.
    run_service "$release_root/current" stop || echo 'Product stop failed after initial deploy failure.' >&2
    rm -f -- "$release_root/current"
    echo 'Initial release failed and there is no prior revision to restore.' >&2
  fi
}

case "$action" in
  deploy)
    revision="${2:-}"
    [[ -n "$revision" ]] || { echo 'Usage: agents/release-product.sh deploy MERGED_REVISION' >&2; exit 2; }
    branch="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name')"
    git fetch --no-tags origin "$branch"
    revision="$(git rev-parse --verify "$revision^{commit}")"
    git merge-base --is-ancestor "$revision" "origin/$branch" || {
      echo 'Deploy only a commit merged into the default branch.' >&2; exit 1;
    }
    target="$release_root/releases/$revision"
    if [[ ! -d "$target" ]]; then
      mkdir "$target"
      git archive "$revision" | tar -x -C "$target"
      touch "$target/.complete"
    fi
    [[ -f "$target/.complete" ]] || { echo 'Release extraction is incomplete.' >&2; exit 1; }
    prior="$(current_target)"
    run_service "$target" prepare
    switch_link current "$target"
    if ! run_service "$target" restart || ! run_service "$target" smoke; then
      restore_after_failure "$prior"
      exit 1
    fi
    if [[ -n "$prior" && "$prior" != "$target" ]]; then switch_link previous "$prior"; fi
    printf 'Deployed %s; previous: %s\n' "$revision" "${prior:-none}"
    ;;
  rollback)
    prior="$(previous_target)"
    [[ -n "$prior" ]] || { echo 'No previous successful release is recorded.' >&2; exit 1; }
    current="$(current_target)"
    [[ -n "$current" ]] || { echo 'No current release is recorded.' >&2; exit 1; }
    switch_link current "$prior"
    if ! run_service "$prior" restart || ! run_service "$prior" smoke; then
      restore_after_failure "$current"
      exit 1
    fi
    switch_link previous "$current"
    printf 'Rolled back to %s\n' "$prior"
    ;;
  status)
    printf 'current: %s\nprevious: %s\n' "$(current_target)" "$(previous_target)"
    ;;
  *)
    echo 'Usage: agents/release-product.sh {deploy MERGED_REVISION|rollback|status}' >&2
    exit 2 ;;
esac
