#!/bin/bash

# Define log file
LOG_FILE="/var/log/syncoid-backup.log"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if the remote zpool is online
if ssh root@10.0.0.36 "zpool status wdred | grep -q 'state: ONLINE'"; then
    log "Remote zpool wdred is ONLINE. Starting backup..."
    if syncoid -r storage/immich root@10.0.0.36:wdred/backup/immich >> "$LOG_FILE" 2>&1; then
        log "Backup for 'storage/immich' completed successfully for wdred."
    else
        log "Backup for 'storage/immich' failed for wdred."
    fi

    if syncoid -r storage/smb root@10.0.0.36:wdred/backup/smb >> "$LOG_FILE" 2>&1; then
        log "Backup for 'storage/smb' completed successfully for wdred."
    else
        log "Backup for 'storage/smb' failed for wdred."
    fi
else
    log "Remote zpool wdred is not ONLINE. Backup aborted."
fi


# Check if the remote zpool is online
if ssh root@10.0.0.36 "zpool status sgblack | grep -q 'state: ONLINE'"; then
    log "Remote zpool sgblack is ONLINE. Starting backup..."
    if syncoid -r storage/immich root@10.0.0.36:sgblack/backup/immich >> "$LOG_FILE" 2>&1; then
        log "Backup for 'storage/immich' completed successfully for sgblack."
    else
        log "Backup for 'storage/immich' failed for sgblack."
    fi

    if syncoid -r storage/smb root@10.0.0.36:sgblack/backup/smb >> "$LOG_FILE" 2>&1; then
        log "Backup for 'storage/smb' completed successfully for sgblack."
    else
        log "Backup for 'storage/smb' failed for sgblack."
    fi
else
    log "Remote zpool sgblack is not ONLINE. Backup aborted."
fi