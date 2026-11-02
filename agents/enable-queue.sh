#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
gh auth status >/dev/null
gh repo view >/dev/null
for label in briefing:ready briefing:in-progress briefing:review briefing:test briefing:needs-manager briefing:merge-ready briefing:blocked briefing:done agent:ingest agent:page; do
  gh label create "$label" --force >/dev/null
done
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/briefing-issue-poller.service" <<UNIT
[Unit]
Description=Dispatch one Daily Briefing GitHub issue
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$repo_dir
ExecStart=/usr/bin/bash "$repo_dir/agents/poll-issues.sh"
UNIT
cat > "$HOME/.config/systemd/user/briefing-issue-poller.timer" <<'UNIT'
[Unit]
Description=Poll Daily Briefing GitHub issues

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=30s
Unit=briefing-issue-poller.service

[Install]
WantedBy=timers.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now briefing-issue-poller.timer
echo 'Queue enabled. Check: systemctl --user list-timers briefing-issue-poller.timer'
