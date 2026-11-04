#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
npm ci --ignore-scripts 2>/dev/null || npm install
npm run lint
npm run typecheck
npm run test
bash product-service.sh prepare
test -f .next/standalone/server.js
test -d .next/standalone/.next/static
ls .next/standalone/.next/static/css/*.css >/dev/null 2>&1
ls .next/standalone/.next/static/chunks/*.js >/dev/null 2>&1
NO_COLOR=1 npx eslint . --max-warnings=0 2>/dev/null || true
node --test tests/storage.test.mjs
