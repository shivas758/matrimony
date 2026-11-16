#!/usr/bin/env bash
# Nightly backup: database dump + uploaded photos.
#
# Install on the VM:
#   cp ~/matrimony-agents/deploy/backup.sh ~/backup.sh && chmod +x ~/backup.sh
#   crontab -e     # add:  30 2 * * * /home/ubuntu/backup.sh >> /home/ubuntu/backup.log 2>&1
#
# Restore is documented at the bottom of deploy/ORACLE_SETUP.md.
#
# Photos are mirrored incrementally rather than tarred daily. A daily tarball of
# ~8 GB of photos kept for 14 days would need ~112 GB — more than the whole boot
# volume. The mirror costs one copy. A photo removed in the app is moved out of the
# mirror into uploads-deleted/<date>/ and kept there for DB_KEEP_DAYS, so it stays
# recoverable for two weeks and then really disappears — as the privacy policy
# promises (SPEC §9.21).

set -uo pipefail

APP_DIR="${APP_DIR:-$HOME/matrimony-agents/backend}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
DB_KEEP_DAYS="${DB_KEEP_DAYS:-14}"
MIN_FREE_GB="${MIN_FREE_GB:-5}"
STAMP="$(date +%F)"

# cron runs with a minimal PATH; docker lives in /usr/bin.
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

mkdir -p "$BACKUP_DIR"
cd "$APP_DIR" || { echo "$(date -Is) FATAL: $APP_DIR not found"; exit 1; }

fail=0

# --- disk guard -----------------------------------------------------------
# Refuse to start a backup that could fill the boot volume.
free_gb="$(df -BG --output=avail "$BACKUP_DIR" | tail -1 | tr -dc '0-9')"
if [ "${free_gb:-0}" -lt "$MIN_FREE_GB" ]; then
  echo "$(date -Is) FATAL: only ${free_gb}GB free in $BACKUP_DIR (need ${MIN_FREE_GB}GB)"
  exit 1
fi

# --- database -------------------------------------------------------------
# Read DB_USER / DB_NAME from .env so a customised database still dumps correctly.
DB_USER="$(grep -E '^DB_USER=' .env 2>/dev/null | cut -d= -f2-)"
DB_NAME="$(grep -E '^DB_NAME=' .env 2>/dev/null | cut -d= -f2-)"
DB_USER="${DB_USER:-matrimony}"
DB_NAME="${DB_NAME:-matrimony}"

# Dump to a temp file first: piping straight to gzip hides a pg_dump failure
# behind gzip's exit code and leaves a valid-looking empty archive.
tmp="$(mktemp)"
if docker compose exec -T db pg_dump -U "$DB_USER" "$DB_NAME" > "$tmp" 2>"$tmp.err"; then
  if [ -s "$tmp" ]; then
    gzip -c "$tmp" > "$BACKUP_DIR/db-$STAMP.sql.gz"
    echo "$(date -Is) db ok ($(du -h "$BACKUP_DIR/db-$STAMP.sql.gz" | cut -f1))"
  else
    echo "$(date -Is) ERROR: pg_dump produced an empty file"; fail=1
  fi
else
  echo "$(date -Is) ERROR: pg_dump failed: $(tail -1 "$tmp.err" 2>/dev/null)"; fail=1
fi
rm -f "$tmp" "$tmp.err"

# --- uploaded photos ------------------------------------------------------
# Incremental mirror. --delete --backup-dir: a photo deleted in the app leaves the
# mirror but is parked in uploads-deleted/<date>/ (pruned below). The container
# writes as root, so reading needs sudo.
if sudo rsync -a --quiet --delete --backup --backup-dir="$BACKUP_DIR/uploads-deleted/$STAMP"     "$APP_DIR/uploads/" "$BACKUP_DIR/uploads-mirror/"; then
  sudo chown -R "$(id -u):$(id -g)" "$BACKUP_DIR/uploads-mirror"
  echo "$(date -Is) uploads ok ($(du -sh "$BACKUP_DIR/uploads-mirror" | cut -f1) mirrored)"
else
  echo "$(date -Is) ERROR: uploads rsync failed"; fail=1
fi

# --- prune ----------------------------------------------------------------
# -type f matters: without it, find deletes the backups directory itself.
# Database dumps, photo tarballs and parked deleted photos all expire after
# DB_KEEP_DAYS; the photo mirror itself is a single living copy.
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'db-*.sql.gz' -o -name 'uploads-*.tgz' \) -mtime "+$DB_KEEP_DAYS" -delete
if [ -d "$BACKUP_DIR/uploads-deleted" ]; then
  sudo find "$BACKUP_DIR/uploads-deleted" -mindepth 1 -maxdepth 1 -type d -mtime "+$DB_KEEP_DAYS" -exec rm -rf {} +
fi

echo "$(date -Is) backups now use $(du -sh "$BACKUP_DIR" | cut -f1), ${free_gb}GB was free"
[ "$fail" -eq 0 ] && echo "$(date -Is) backup complete" || echo "$(date -Is) backup FINISHED WITH ERRORS"
exit "$fail"
