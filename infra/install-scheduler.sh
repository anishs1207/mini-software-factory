#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_dir/infra"
service_unit="factory-briefing.service"
timer_unit="factory-briefing.timer"
unit_dir="${SYSTEMD_UNIT_DIR:-/etc/systemd/system}"

if [[ ! -r "$source_dir/$service_unit" || ! -r "$source_dir/$timer_unit" ]]; then
  echo "Missing systemd unit source file(s) in $source_dir" >&2
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo SYSTEMD_UNIT_DIR="$unit_dir" bash "$0" "$@"
  fi
  echo "install-scheduler.sh must run as root or via sudo" >&2
  exit 1
fi

install -d 0755 "$unit_dir"
install -m 0644 "$source_dir/$service_unit" "$unit_dir/$service_unit"
install -m 0644 "$source_dir/$timer_unit" "$unit_dir/$timer_unit"

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
  systemctl enable "$timer_unit"
  systemctl start "$timer_unit" 2>/dev/null || true
fi

echo "Installed $service_unit and $timer_unit in $unit_dir"