#!/bin/bash

# Weekly nopCommerce MySQL backup with Google Drive upload via rclone
set -euo pipefail

DB_NAME="nopcommerce_prod"
DB_USER="nopcommerce_user"
DB_PASSWORD="nopCommerce_secure_2024"
DB_HOST="localhost"

BACKUP_ROOT="/home/ubuntu/nopcommerce-db-backups"
# Remote Google Drive path (folder must exist or rclone will create it)
REMOTE_PATH="gdrive_nopcommerce:nopcommerce/db"

RETAIN_COUNT=3

TIMESTAMP="$(date -u +"%Y%m%d-%H%M%S")"
TMP_SQL="/tmp/${DB_NAME}-${TIMESTAMP}.sql"
ARCHIVE_PATH="${BACKUP_ROOT}/${DB_NAME}-${TIMESTAMP}.sql.gz"
LOCK_FILE="/tmp/nopcommerce-db-backup.lock"

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1"
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command '$1' not found" >&2
        exit 1
    fi
}

require_cmd mysqldump
require_cmd gzip
require_cmd rclone

mkdir -p "$BACKUP_ROOT"

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log "Another backup process is running. Exiting."
    exit 0
fi

trap 'rm -f "$TMP_SQL"' EXIT

log "Starting database dump for ${DB_NAME}."
MYSQL_PWD="$DB_PASSWORD" mysqldump \
    --single-transaction \
    --routines \
    --events \
    --triggers \
    --no-tablespaces \
    -h "$DB_HOST" \
    -u "$DB_USER" \
    "$DB_NAME" > "$TMP_SQL"

log "Compressing dump to ${ARCHIVE_PATH}."
gzip -c "$TMP_SQL" > "$ARCHIVE_PATH"
rm -f "$TMP_SQL"

if [[ "$REMOTE_PATH" == "gdrive_nopcommerce:nopcommerce/db" ]]; then
    log "Remote destination set to default gdrive path. Ensure gdrive_nopcommerce remote exists before running."
fi

log "Uploading archive to ${REMOTE_PATH}."
rclone copy "$ARCHIVE_PATH" "$REMOTE_PATH"

log "Pruning local backups to retain last ${RETAIN_COUNT}."
mapfile -t local_backups < <(ls -1t ${BACKUP_ROOT}/${DB_NAME}-*.sql.gz 2>/dev/null || true)
if (( ${#local_backups[@]} > RETAIN_COUNT )); then
    for backup in "${local_backups[@]:RETAIN_COUNT}"; do
        log "Deleting local backup ${backup}."
        rm -f "$backup"
    done
fi

log "Pruning remote backups to retain last ${RETAIN_COUNT}."
mapfile -t remote_backups < <(rclone lsf "$REMOTE_PATH" --files-only | sort -r || true)
if (( ${#remote_backups[@]} > RETAIN_COUNT )); then
    for file in "${remote_backups[@]:RETAIN_COUNT}"; do
        log "Deleting remote backup ${file}."
        rclone delete "$REMOTE_PATH/$file"
    done
fi

log "Backup completed successfully."
