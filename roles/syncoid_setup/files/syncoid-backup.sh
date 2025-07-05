#!/bin/bash

LOG_FILE="/var/log/syncoid-backup.log"
REMOTE_USER="root"
REMOTE_HOST="10.0.0.36"
POSSIBLE_POOLS=("wdred" "sgblack")
PROXMOX_DATASET="storage"
BACKUP_DATASET="backup"
DATASETS_TO_BACKUP=("smb")

ZFS="/usr/sbin/zfs"
ZPOOL="/usr/sbin/zpool"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "Starting Syncoid backup script."
log "Checking for ZFS pools on $REMOTE_HOST from list: ${POSSIBLE_POOLS[*]}..."

for current_pool in "${POSSIBLE_POOLS[@]}"; do
    log "Checking status of pool '$current_pool'..."

    if ! ssh "$REMOTE_USER@$REMOTE_HOST" "$ZPOOL list -H $current_pool" &> /dev/null; then
        log "Pool '$current_pool' is not imported. Attempting to import..."

        if ssh "$REMOTE_USER@$REMOTE_HOST" "$ZPOOL import -d /dev/disk/by-uuid/ $current_pool" >> "$LOG_FILE" 2>&1; then
            log "Successfully imported pool '$current_pool'."
        else
            log "Failed to import pool '$current_pool'. It may not be available. Skipping."
            continue
        fi
    fi

    # Now check if the pool is online
    if ssh "$REMOTE_USER@$REMOTE_HOST" "$ZPOOL status $current_pool | grep -q 'state: ONLINE'"; then
        log "Pool '$current_pool' is ONLINE. Proceeding with backup steps for this pool."

        log "Attempting to load key for pool '$current_pool'..."
        if ssh "$REMOTE_USER@$REMOTE_HOST" "$ZFS load-key -r $current_pool" >> "$LOG_FILE" 2>&1; then
            log "ZFS key loaded successfully for '$current_pool'."

            for current_dataset in "${DATASETS_TO_BACKUP[@]}"; do
                log "Backing up dataset '$current_dataset'..."

                if /usr/sbin/syncoid -r "$PROXMOX_DATASET/$current_dataset" "$REMOTE_USER@$REMOTE_HOST:$current_pool/$BACKUP_DATASET/$current_dataset" >> "$LOG_FILE" 2>&1; then
                    log "Backup for dataset '$current_dataset' to '$current_pool' completed successfully."
                else
                    log "Backup for dataset '$current_dataset' to '$current_pool' failed. Check syncoid output in log file on Proxmox."
                    exit 1
                fi
            done

            log "Finished all dataset backups for pool '$current_pool'."

            if ssh "$REMOTE_USER@$REMOTE_HOST" "$ZPOOL export $current_pool" >> "$LOG_FILE" 2>&1; then
                log "Pool '$current_pool' exported successfully."
            else
                log "Failed to export pool '$current_pool'. It might be busy. Check on $REMOTE_HOST."
            fi

            log "Successfully processed pool '$current_pool'. Exiting."
            #exit 0

        else
            log "Failed to load ZFS key for '$current_pool'. Skipping backups for this pool."
            log "Could not process pool '$current_pool' due to key load failure. Exiting."
            exit 1
        fi
    else
        log "Pool '$current_pool' is found but not in ONLINE state. Skipping."
    fi
done

log "No suitable ZFS pools (${POSSIBLE_POOLS[*]}) found to process."
exit 1
