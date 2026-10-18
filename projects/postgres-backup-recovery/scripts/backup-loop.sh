#!/bin/sh
set -u

: "${BACKUP_INTERVAL_SECONDS:?BACKUP_INTERVAL_SECONDS is required}"

echo "[scheduler] starting, interval ${BACKUP_INTERVAL_SECONDS}s"
while true; do
    if /scripts/backup.sh; then
        echo "[scheduler] backup completed at $(date -Is)"
    else
        echo "[scheduler] backup FAILED at $(date -Is)" >&2
    fi
    sleep "${BACKUP_INTERVAL_SECONDS}"
done
