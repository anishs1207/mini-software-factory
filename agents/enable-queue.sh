#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
gh auth status >/dev/null
gh auth setup-git >/dev/null
gh repo view >/dev/null
for label in factory:waiting factory:ready factory:in-progress factory:review factory:test factory:needs-manager factory:merge-ready factory:blocked factory:done agent:builder1 agent:builder2; do
  gh label create "$label" --force >/dev/null
done
if [[ -f "$HOME/.config/briefing-agents/campaign-label" ]]; then
  campaign_label="$(cat "$HOME/.config/briefing-agents/campaign-label")"
  [[ "$campaign_label" =~ ^product:[0-9a-f]{12}$ ]] || { echo 'Invalid active campaign label.' >&2; exit 1; }
  gh label create "$campaign_label" --force >/dev/null
fi
mkdir -p "$HOME/.config/systemd/user"
for provider in ollama openrouter; do
cat > "$HOME/.config/systemd/user/briefing-issue-poller-$provider.service" <<UNIT
[Unit]
Description=Dispatch one $provider software factory GitHub issue
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$repo_dir
EnvironmentFile=%h/.config/briefing-agents/credentials.env
Environment=FACTORY_PROVIDER=$provider
ExecStart=/usr/bin/bash "$repo_dir/agents/poll-issues.sh"
UNIT
cat > "$HOME/.config/systemd/user/briefing-issue-poller-$provider.timer" <<UNIT
[Unit]
Description=Poll $provider software factory GitHub issues

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=30s
Unit=briefing-issue-poller-$provider.service

[Install]
WantedBy=timers.target
UNIT
done
systemctl --user daemon-reload
systemctl --user disable --now briefing-issue-poller.timer 2>/dev/null || true
systemctl --user enable --now briefing-issue-poller-ollama.timer briefing-issue-poller-openrouter.timer
for provider in ollama openrouter; do
  systemctl --user is-active --quiet "briefing-issue-poller-$provider.timer" || {
    echo "The $provider issue queue timer is not active." >&2
    exit 1
  }
done
echo 'Queue enabled. Check: systemctl --user list-timers briefing-issue-poller-*'
