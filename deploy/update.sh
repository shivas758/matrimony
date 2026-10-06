#!/usr/bin/env bash
# Non-interactive update of the backend on the VM — the sequence from
# ORACLE_SETUP.md §11 in one command. Run from the project root on your PC
# (Git Bash on Windows works):
#
#   VM_HOST=ubuntu@YOUR_PUBLIC_IP SSH_KEY=~/.ssh/matrimony_oracle ./deploy/update.sh
#
# What it does, in order:
#   1. builds matrimony-backend.tgz (deploy/package.sh) and copies it over
#   2. on the VM: takes a pg_dump into ~/backups BEFORE touching anything,
#      unpacks the tarball, applies every migration (all idempotent),
#      rebuilds and restarts the API, and checks /api/health
#   3. from your PC: checks https://<domain>/api/health when PUBLIC_URL is set
#
# Your .env, the database volume and uploads/ are never touched.
# The API is down for the minute or two the image rebuilds.

set -euo pipefail

VM_HOST="${VM_HOST:?set VM_HOST=ubuntu@YOUR_PUBLIC_IP}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/matrimony_oracle}"
PUBLIC_URL="${PUBLIC_URL:-}"
REMOTE_DIR="${REMOTE_DIR:-matrimony-agents}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> packaging"
./deploy/package.sh >/dev/null
echo "==> copying to $VM_HOST"
scp -q -i "$SSH_KEY" matrimony-backend.tgz "$VM_HOST:~/"

echo "==> updating on the VM"
ssh -i "$SSH_KEY" "$VM_HOST" 'set -e
  STAMP=$(date +%Y%m%d-%H%M%S)
  mkdir -p ~/backups
  cd ~/'"$REMOTE_DIR"'/backend
  echo "-- pre-update database dump -> ~/backups/db-pre-update-$STAMP.sql.gz"
  docker compose exec -T db pg_dump -U matrimony matrimony | gzip > ~/backups/db-pre-update-$STAMP.sql.gz
  echo "-- unpacking"
  cd ~/'"$REMOTE_DIR"' && tar xzf ~/matrimony-backend.tgz
  cd backend
  echo "-- migrations"
  for f in db/migrations/*.sql; do
    echo "   $f"
    docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 -q < "$f"
  done
  echo "-- rebuilding the API image"
  docker compose up -d --build
  for i in $(seq 1 30); do
    if curl -sf http://localhost:3000/api/health >/dev/null; then echo "-- API healthy"; exit 0; fi
    sleep 2
  done
  echo "!! API did not become healthy — last log lines:"
  docker compose logs --tail=40 api
  exit 1'

if [ -n "$PUBLIC_URL" ]; then
  echo "==> public health check"
  curl -sf "$PUBLIC_URL/api/health" && echo
fi
echo "==> done"
