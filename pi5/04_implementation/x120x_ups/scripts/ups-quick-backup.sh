#!/usr/bin/env bash
set -euo pipefail

CONFIG=/etc/x120x/ups-shutdown.conf
if [ -r "$CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi

BACKUP_DIR="${BACKUP_DIR:-/mnt/backup/UPS_shutdown_backusp}"
BACKUP_PATHS="${UPS_BACKUP_PATHS:-/etc /home /srv /var/lib /var/www /root}"
EXCLUDES_FILE="${UPS_EXCLUDES_FILE:-/etc/restic/excludes.txt}"
LOG_FILE="${UPS_BACKUP_LOG:-/var/log/ups-quick-backup.log}"

if ! mountpoint -q /mnt/backup; then
  printf '%s %s\n' "$(date -Is)" "Backup mount not present: /mnt/backup" | tee -a "$LOG_FILE" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"

STAMP=$(date -u +%Y%m%d-%H%M%S)
DEST="$BACKUP_DIR/$STAMP"
LATEST="$BACKUP_DIR/latest"

mkdir -p "$DEST"

LINK_DEST=()
if [ -d "$LATEST" ]; then
  LINK_DEST=("--link-dest=$LATEST")
fi

RSYNC_ARGS=(
  -a
  --numeric-ids
  --delete
  --relative
  --info=stats2
)

if [ -n "$EXCLUDES_FILE" ] && [ -r "$EXCLUDES_FILE" ]; then
  RSYNC_ARGS+=("--exclude-from=$EXCLUDES_FILE")
fi

RSYNC_ARGS+=("--exclude=$BACKUP_DIR")

read -r -a PATHS <<< "$BACKUP_PATHS"

{
  printf '%s %s\n' "$(date -Is)" "UPS quick backup started"
  printf '%s %s\n' "$(date -Is)" "Destination: $DEST"
  printf '%s %s\n' "$(date -Is)" "Paths: $BACKUP_PATHS"
} | tee -a "$LOG_FILE"

rsync "${RSYNC_ARGS[@]}" "${LINK_DEST[@]}" "${PATHS[@]}" "$DEST" | tee -a "$LOG_FILE"

ln -sfn "$DEST" "$LATEST"

printf '%s %s\n' "$(date -Is)" "UPS quick backup completed" | tee -a "$LOG_FILE"
