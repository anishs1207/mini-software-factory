#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -gt 0 ]] || { echo 'Usage: agents/run-product-command.sh COMMAND [ARG...]' >&2; exit 2; }

# Product commands must not inherit the factory's GitHub or model credentials.
clean_home="$(mktemp -d)"
trap 'rm -rf -- "$clean_home"' EXIT
env -i "PATH=$PATH" "HOME=$clean_home" "XDG_CONFIG_HOME=$clean_home/.config" \
  "USER=$(id -un)" "$@"
