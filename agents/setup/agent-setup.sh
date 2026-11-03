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
[[ -n "${OPENROUTER_API_KEY:-}" && "$OPENROUTER_API_KEY" != *replace* ]] || { echo 'Set OPENROUTER_API_KEY for manager and reviewer.' >&2; exit 1; }
: "${OLLAMA_BASE_URL:=https://ollama.com/v1}"
: "${OLLAMA_MODEL:=beam:cloud}"
: "${OPENROUTER_REASONING_MODEL:=nvidia/nemotron-3-ultra-550b-a55b:free}"
: "${OPENCLAW_FALLBACK_MODEL:=openrouter/$OPENROUTER_REASONING_MODEL}"
: "${HERMES_FALLBACK_MODEL:=$OPENROUTER_REASONING_MODEL}"
[[ "$OLLAMA_BASE_URL" == https://ollama.com/v1 ]] || { echo 'Use https://ollama.com/v1 for the Hermes Ollama Cloud endpoint.' >&2; exit 1; }
[[ "$OLLAMA_MODEL" == beam:cloud ]] || { echo 'This one-key setup uses OLLAMA_MODEL=beam:cloud.' >&2; exit 1; }
[[ "$OPENROUTER_REASONING_MODEL" == *:free && "$OPENROUTER_REASONING_MODEL" != *REPLACE* ]] || { echo 'Use an OpenRouter :free reasoning model.' >&2; exit 1; }
[[ "$OPENCLAW_FALLBACK_MODEL" == openrouter/*:free && "$OPENCLAW_FALLBACK_MODEL" != *REPLACE* ]] || { echo 'Use an openrouter/*:free OpenClaw fallback.' >&2; exit 1; }
[[ "$HERMES_FALLBACK_MODEL" == *:free && "$HERMES_FALLBACK_MODEL" != *REPLACE* ]] || { echo 'Use an OpenRouter :free Hermes fallback.' >&2; exit 1; }
export OLLAMA_BASE_URL OLLAMA_MODEL
OPENCLAW_BUILDER_MODEL="ollama-cloud/$OLLAMA_MODEL"

sudo apt-get update
sudo apt-get install -y curl git jq gh ca-certificates openssl util-linux python3

# Official installers; OpenClaw's installer provisions a supported Node runtime if needed.
curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install.sh | bash -s -- --no-prompt --no-onboard
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
if ! command -v node >/dev/null || ! node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit((major === 24 && minor >= 16) || (major === 26 && minor >= 1) ? 0 : 1)'; then
  echo 'OpenClaw requires Node 24.16+ or 26.1+; check the installed Node version.' >&2
  exit 1
fi
command -v openclaw >/dev/null || { echo 'OpenClaw CLI missing after install.' >&2; exit 1; }
command -v hermes >/dev/null || { echo 'Hermes CLI missing after install.' >&2; exit 1; }

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
openclaw models set "$OPENCLAW_BUILDER_MODEL"
openclaw models fallbacks add "$OPENCLAW_FALLBACK_MODEL"
# The shared Ollama key has one request slot. Also constrain Gateway sessions
# started outside the issue poller (for example, through the local dashboard).
openclaw config set agents.defaults.maxConcurrent 1 --strict-json
openclaw config set agents.defaults.subagents.maxConcurrent 1 --strict-json

openclaw_bin="$(command -v openclaw)"
cat > "$HOME/.config/systemd/user/briefing-openclaw.service" <<UNIT
[Unit]
Description=Daily Briefing OpenClaw Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=%h/.config/briefing-agents/credentials.env
ExecStart=$openclaw_bin gateway run --bind loopback --port 18789
Restart=on-failure
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

for role in ingest page; do
  workspace="$HOME/briefing-agents/$role"
  mkdir -p "$workspace"
  install -m 644 "$repo_dir/agents/openclaw/$role/AGENTS.md" "$workspace/AGENTS.md"
  if ! openclaw agents list --json | jq -e --arg role "$role" '.. | objects | select(.id? == $role)' >/dev/null; then
    openclaw agents add "$role" --workspace "$workspace" --model "$OPENCLAW_BUILDER_MODEL" --non-interactive
  fi
  # Update existing named agents too; their explicit primary can outlive onboarding.
  openclaw config set "agents.entries.$role.model.primary" "$OPENCLAW_BUILDER_MODEL"
  openclaw config set "agents.entries.$role.model.fallbacks" "[\"$OPENCLAW_FALLBACK_MODEL\"]" --strict-json
done
openclaw config validate

for role in manager reviewer tester; do
  if [[ ! -d "$HOME/.hermes/profiles/$role" ]]; then
    hermes profile create "$role" --description "Daily Briefing $role role"
  fi
  install -m 644 "$repo_dir/agents/hermes/$role/SOUL.md" "$HOME/.hermes/profiles/$role/SOUL.md"
  if [[ "$role" == manager || "$role" == reviewer ]]; then
    hermes -p "$role" config set model.provider openrouter
    hermes -p "$role" config set model.default "$OPENROUTER_REASONING_MODEL"
    fallback_provider=ollama-cloud
    fallback_model="$OLLAMA_MODEL"
  else
    hermes -p "$role" config set model.provider ollama-cloud
    hermes -p "$role" config set model.default "$OLLAMA_MODEL"
    fallback_provider=openrouter
    fallback_model="$HERMES_FALLBACK_MODEL"
  fi
  hermes -p "$role" config set terminal.cwd "$repo_dir"
  install -m 600 "$secrets" "$HOME/.hermes/profiles/$role/.env"
  hermes -p "$role" config set fallback_providers "[{\"provider\":\"$fallback_provider\",\"model\":\"$fallback_model\"}]"
  if [[ "$role" == manager ]]; then
    hermes -p manager config set delegation.max_concurrent_children 1
    hermes -p manager config set delegation.max_spawn_depth 1
  fi
  hermes -p "$role" config check
done

# Hermes' optional web extra powers its localhost-only analytics dashboard.
if [[ -d "$HOME/.hermes/hermes-agent" ]] && command -v uv >/dev/null \
  && (cd "$HOME/.hermes/hermes-agent" && uv pip install -e '.[web]'); then
  hermes_bin="$(command -v hermes)"
  cat > "$HOME/.config/systemd/user/briefing-hermes-dashboard.service" <<UNIT
[Unit]
Description=Daily Briefing Hermes Dashboard
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
else
  echo 'Hermes web extra was not installed; the CLI profiles remain ready.' >&2
fi

openclaw agents list
hermes profile list
echo 'Runtime setup complete. The Terraform bootstrap now enables the queue and dispatches the manager; manual setup must do those steps separately.'
