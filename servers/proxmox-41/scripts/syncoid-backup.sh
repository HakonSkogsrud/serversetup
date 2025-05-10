#!/bin/bash

# Define log file
LOG_FILE="/var/log/syncoid-backup.log"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if the remote zpool is online
if ssh root@10.0.0.36 "zpool status wdred | grep -q 'state: ONLINE'"; then
    log "Remote zpool is ONLINE. Starting backup..."
    if syncoid -r storage/immich root@10.0.0.36:wdred/backup/immich >> "$LOG_FILE" 2>&1; then
        log "Backup for 'storage/immich' completed successfully."
    else
        log "Backup for 'storage/immich' failed."
    fi

    if syncoid -r storage/smb root@10.0.0.36:wdred/backup/smb >> "$LOG_FILE" 2>&1; then
        log "Backup for 'storage/smb' completed successfully."
    else
        log "Backup for 'storage/smb' failed."
    fi
else
    log "Remote zpool is not ONLINE. Backup aborted."
    exit 1
fi