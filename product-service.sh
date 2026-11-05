#!/usr/bin/env bash
set -Eeuo pipefail

CMD="${1:-}"
FACTORY_CURRENT_DIR="${FACTORY_CURRENT_DIR:-$(pwd)}"
FACTORY_DATA_DIR="${FACTORY_DATA_DIR:-$FACTORY_CURRENT_DIR/data}"
# FACTORY_DATA_DIR must point at persistent VM storage across releases so run
# history and comparison state survive restart/release. Do not reset it per deploy.
PID_FILE="$FACTORY_DATA_DIR/server.pid"
LOG_FILE="$FACTORY_DATA_DIR/server.log"

mkdir -p "$FACTORY_DATA_DIR"

stop_server() {
  if [[ -f "$PID_FILE" ]]; then
    local pid; pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      local i=0
      while kill -0 "$pid" 2>/dev/null && [[ $i -lt 100 ]]; do
        sleep 0.1; i=$((i+1))
      done
      if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
        sleep 0.2
      fi
    fi
    rm -f "$PID_FILE"
  fi
}

case "$CMD" in
  prepare)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$SCRIPT_DIR"
    npm ci
    npm run build
    [[ -f .next/standalone/server.js ]] || { echo "standalone server missing" >&2; exit 1; }
    # Next.js standalone output excludes static assets and public/.
    rm -rf .next/standalone/.next/static
    mkdir -p .next/standalone/.next
    cp -R .next/static .next/standalone/.next/static
    if [[ -d public ]]; then
      rm -rf .next/standalone/public
      cp -R public .next/standalone/public
    fi
    [[ -d .next/standalone/.next/static ]] || { echo "standalone static missing" >&2; exit 1; }
    ;;
  restart)
    stop_server
    cd "$FACTORY_CURRENT_DIR"
    export PORT=3000 NODE_ENV=production FACTORY_DATA_DIR
    HOSTNAME=0.0.0.0 nohup node .next/standalone/server.js >"$LOG_FILE" 2>&1 &
    echo $! >"$PID_FILE"
    sleep 1
    ;;
  smoke)
    curl -fsS http://127.0.0.1:3000 >/dev/null
    curl -fsS http://127.0.0.1:3000/api/runs/latest >/dev/null
    ;;
  stop)
    stop_server
    ;;
  run)
    cd "$FACTORY_CURRENT_DIR"
    export FACTORY_DATA_DIR
    node -e '
      const { pathToFileURL } = require("node:url");
      (async () => {
        const m = await import(pathToFileURL(process.cwd()+"/lib/runner.ts").href).catch(()=>null);
      })();
    ' 2>/dev/null || true
    # Use ts stripping via node experimental? Instead build uses tsc no. Use npx tsx.
    FACTORY_DATA_DIR="$FACTORY_DATA_DIR" npx --yes tsx "$FACTORY_CURRENT_DIR/lib/run-cli.ts" 2>/dev/null || {
      # fallback: create temp runner js by transpiling with tsc? Provide direct node fallback using require of compiled? Not available.
      echo "run not implemented" >&2; exit 1;
    }
    ;;
  *)
    echo "Usage: product-service.sh {prepare|restart|smoke|stop|run}" >&2; exit 2 ;;
esac