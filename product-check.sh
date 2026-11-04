#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
npm ci --ignore-scripts 2>/dev/null || npm install
npm run lint
npm run typecheck
npm run test
npm run build
test -f .next/standalone/server.js
NO_COLOR=1 npx eslint . --max-warnings=0 2>/dev/null || true
node --test tests/storage.test.mjs
