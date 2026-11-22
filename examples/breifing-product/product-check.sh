#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
npm ci
npm run lint
npm run typecheck
npm run test
npm run build
test -f .next/standalone/server.js
test -d .next/static
ls .next/static/css/*.css >/dev/null 2>&1
ls .next/static/chunks/*.js >/dev/null 2>&1
