#!/usr/bin/env bash
# Builds a clean tarball of just what the server needs.
# Run from the project root (works in Git Bash on Windows too):
#
#   ./deploy/package.sh
#   scp matrimony-backend.tgz ubuntu@YOUR_PUBLIC_IP:~/
#
# Deliberately excludes node_modules, uploads, the Flutter app, and every .env
# file — dev secrets must never reach the server.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/matrimony-backend.tgz}"

cd "$ROOT"

tar czf "$OUT" \
  --exclude='backend/node_modules' \
  --exclude='backend/uploads' \
  --exclude='backend/.env' \
  --exclude='backend/.env.local' \
  --exclude='backend/docker-compose.dev.yml' \
  backend deploy docs CLAUDE.md README.md

echo "Wrote $OUT ($(du -h "$OUT" | cut -f1))"
echo
echo "Contents:"
# sed reads the whole listing, so tar never gets SIGPIPE (which pipefail would turn into exit 141).
tar tzf "$OUT" | sed -n "1,20p"
echo "..."
echo
echo "Next:  scp $(basename "$OUT") ubuntu@YOUR_PUBLIC_IP:~/"
