#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
secrets="$repo_dir/agents/secrets.env"
[[ "$(id -u)" -ne 0 ]] || { echo 'Run this as ubuntu, not root.' >&2; exit 1; }
[[ -f "$secrets" ]] || { echo 'Copy agents/.env.sample to agents/secrets.env and fill it in.' >&2; exit 1; }
chmod 600 "$secrets"
set -a
source "$secrets"
set +a
[[ -n "${OLLAMA_API_KEY:-}" && "$OLLAMA_API_KEY" != replace-me ]] || { echo 'Set a fresh OLLAMA_API_KEY.' >&2; exit 1; }
: "${OLLAMA_BASE_URL:=https://ollama.com/v1}"
: "${OLLAMA_MODEL:=beam}"
[[ "$OLLAMA_BASE_URL" == https://ollama.com/v1 ]] || { echo 'Use https://ollama.com/v1 for the Hermes Ollama Cloud endpoint.' >&2; exit 1; }
[[ "$OLLAMA_MODEL" == beam ]] || { echo 'This one-key setup uses OLLAMA_MODEL=beam.' >&2; exit 1; }
export OLLAMA_BASE_URL OLLAMA_MODEL
OPENCLAW_BUILDER_MODEL="ollama-cloud/$OLLAMA_MODEL"

sudo apt-get update
sudo apt-get install -y \
  ca-certificates curl git gh jq openssl util-linux coreutils tar \
  python3 python3-venv python3-pip \
  build-essential pkg-config libatomic1 unzip ripgrep

export PATH="$HOME/.npm-global/bin:$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
# Official installers; OpenClaw's installer provisions a supported Node runtime if needed.
if ! command -v openclaw >/dev/null; then
  curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install.sh | bash -s -- --no-prompt --no-onboard
fi
if ! command -v hermes >/dev/null; then
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive
fi
if ! command -v node >/dev/null || ! node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit((major === 24 && minor >= 16) || (major === 26 && minor >= 1) ? 0 : 1)'; then
  echo 'OpenClaw requires Node 24.16+ or 26.1+; check the installed Node version.' >&2
  exit 1
fi
command -v openclaw >/dev/null || { echo 'OpenClaw CLI missing after install.' >&2; exit 1; }
command -v hermes >/dev/null || { echo 'Hermes CLI missing after install.' >&2; exit 1; }
for required in bash git gh jq curl openssl python3 node npm flock timeout tar sha256sum realpath rg make gcc systemctl loginctl; do
  command -v "$required" >/dev/null || { echo "Required VM command missing: $required" >&2; exit 1; }
done

# Keep the Ollama key outside both checked-in configs and Terraform state.
mkdir -p "$HOME/.config/briefing-agents" "$HOME/.config/systemd/user"
if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" && -f "$HOME/.config/briefing-agents/credentials.env" ]]; then
  OPENCLAW_GATEWAY_TOKEN="$(sed -n 's/^OPENCLAW_GATEWAY_TOKEN=//p' "$HOME/.config/briefing-agents/credentials.env" | head -n 1)"
fi
install -m 600 "$secrets" "$HOME/.config/briefing-agents/credentials.env"
if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)"
fi
printf '\nOPENCLAW_GATEWAY_TOKEN=%s\n' "$OPENCLAW_GATEWAY_TOKEN" >> "$HOME/.config/briefing-agents/credentials.env"
export OPENCLAW_GATEWAY_TOKEN

openclaw onboard --non-interactive --accept-risk --skip-health --skip-daemon \
  --auth-choice ollama-cloud --secret-input-mode ref --gateway-bind loopback \
  --gateway-auth token --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN \
  --skip-ui --skip-channels --skip-hooks
openclaw config set models.providers.ollama-cloud \
  '{"baseUrl":"https://ollama.com","apiKey":"OLLAMA_API_KEY","api":"ollama","models":[{"id":"beam","name":"beam","input":["text"],"contextWindow":1048576,"maxTokens":8192}]}' \
  --strict-json --merge
openclaw models set "$OPENCLAW_BUILDER_MODEL"
# The shared Ollama key has one request slot. Also constrain Gateway sessions
# started outside the issue poller (for example, through the local dashboard).
openclaw config set agents.defaults.maxConcurrent 1 --strict-json
openclaw config set agents.defaults.subagents.maxConcurrent 1 --strict-json

openclaw_bin="$(command -v openclaw)"
cat > "$HOME/.config/systemd/user/briefing-openclaw.service" <<UNIT
[Unit]
Description=Software Factory OpenClaw Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=%h/.config/briefing-agents/credentials.env
ExecStart=$openclaw_bin gateway run --bind loopback --port 18789
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
UNIT
sudo loginctl enable-linger "$(id -un)"
systemctl --user daemon-reload
systemctl --user enable briefing-openclaw.service
systemctl --user restart briefing-openclaw.service
for attempt in {1..30}; do
  if openclaw gateway health --port 18789 >/dev/null 2>&1; then break; fi
  if [[ "$attempt" -eq 30 ]]; then
    echo 'OpenClaw Gateway did not become healthy; inspect journalctl --user -u briefing-openclaw.service.' >&2
    exit 1
  fi
  sleep 2
done

for role in builder1 builder2; do
  workspace="$HOME/briefing-agents/$role"
  mkdir -p "$workspace"
  install -m 644 "$repo_dir/agents/openclaw/$role/AGENTS.md" "$workspace/AGENTS.md"
  if ! openclaw agents list --json | jq -e --arg role "$role" '.. | objects | select(.id? == $role)' >/dev/null; then
    openclaw agents add "$role" --workspace "$workspace" --model "$OPENCLAW_BUILDER_MODEL" --non-interactive
  fi
  # Update existing named agents too; their explicit primary can outlive onboarding.
  openclaw config set "agents.entries.$role.model.primary" "$OPENCLAW_BUILDER_MODEL"
  openclaw config set "agents.entries.$role.model.fallbacks" '[]' --strict-json
done
openclaw config validate

for role in manager reviewer tester; do
  if [[ ! -d "$HOME/.hermes/profiles/$role" ]]; then
    hermes profile create "$role" --description "Software Factory $role role"
  fi
  install -m 644 "$repo_dir/agents/hermes/$role/SOUL.md" "$HOME/.hermes/profiles/$role/SOUL.md"
  hermes -p "$role" config set model.provider ollama-cloud
  hermes -p "$role" config set model.default "$OLLAMA_MODEL"
  hermes -p "$role" config set terminal.cwd "$repo_dir"
  install -m 600 "$secrets" "$HOME/.hermes/profiles/$role/.env"
  hermes -p "$role" config set fallback_providers '[]'
  if [[ "$role" == manager ]]; then
    hermes -p manager config set delegation.max_concurrent_children 1
    hermes -p manager config set delegation.max_spawn_depth 1
  fi
  hermes -p "$role" config check
done

# The installed Hermes CLI includes its dashboard. Verify the advertised
# localhost tunnel has a live service instead of silently skipping it.
hermes dashboard --help >/dev/null
hermes_bin="$(command -v hermes)"
cat > "$HOME/.config/systemd/user/briefing-hermes-dashboard.service" <<UNIT
[Unit]
Description=Software Factory Hermes Dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$hermes_bin dashboard --host 127.0.0.1 --port 9119 --no-open
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable briefing-hermes-dashboard.service
systemctl --user restart briefing-hermes-dashboard.service
for attempt in {1..30}; do
  if curl --silent --fail --max-time 3 http://127.0.0.1:9119/ >/dev/null; then break; fi
  if [[ "$attempt" -eq 30 ]]; then
    echo 'Hermes dashboard did not become healthy; inspect journalctl --user -u briefing-hermes-dashboard.service.' >&2
    exit 1
  fi
  sleep 2
done

openclaw agents list
hermes profile list
install -m 644 "$repo_dir/agents/systemd/factory-autodeploy.service" "$HOME/.config/systemd/user/factory-autodeploy.service"
install -m 644 "$repo_dir/agents/systemd/factory-autodeploy.timer" "$HOME/.config/systemd/user/factory-autodeploy.timer"
systemctl --user daemon-reload
systemctl --user enable --now factory-autodeploy.timer
echo 'Runtime setup complete. Write a spec on the VM and tell the manager to implement it.'
