#!/usr/bin/env bash
set -Eeuo pipefail

unit_dir="${SYSTEMD_UNIT_DIR:-/etc/systemd/system}"
service_unit="factory-briefing.service"
timer_unit="factory-briefing.timer"

if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo SYSTEMD_UNIT_DIR="$unit_dir" bash "$0" "$@"
  fi
  echo "uninstall-scheduler.sh must run as root or via sudo" >&2
  exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now "$timer_unit" 2>/dev/null || true
  systemctl stop "$service_unit" 2>/dev/null || true
fi

rm -f "$unit_dir/$service_unit" "$unit_dir/$timer_unit"

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
  systemctl reset-failed "$service_unit" "$timer_unit" 2>/dev/null || true
fi

echo "Uninstalled $service_unit and $timer_unit from $unit_dir"