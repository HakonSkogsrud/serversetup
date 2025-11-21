#!/bin/bash

source /usr/local/lib/send_pushover.sh

LOG_FILE="/var/log/syncoid-backup.log"
LOCK_FILE="/var/run/syncoid-backup.lock"
REMOTE_USER="root"
REMOTE_HOST="100.104.43.26"
POSSIBLE_POOLS=("wdred" "sgblack")
PROXMOX_DATASET="storage"
BACKUP_DATASET="backup"
DATASETS_TO_BACKUP=("smb")

ZFS="/usr/sbin/zfs"
ZPOOL="/usr/sbin/zpool"

pushover_token_backup="${pushover_token_backup:-}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to acquire lock
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE")
        if kill -0 "$lock_pid" 2>/dev/null; then
            log "Another instance of syncoid-backup is already running (PID: $lock_pid). Exiting."
            # Send high-priority failure notification before exiting
            send_pushover "$pushover_token_backup" "Syncoid backup FAILED on $(hostname). Another instance is running (PID: $lock_pid)." "Syncoid Backup FAILURE (Lock)" 0 "siren"
            exit 1
        else
            log "Found stale lock file. Removing it."
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    log "Lock acquired (PID: $$)."
}

# Function to release lock
release_lock() {
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
        log "Lock released."
    fi
}

# NEW: Cleanup and Notification function to be called on EXIT
cleanup_and_notify() {
    local exit_code=$?
    local script_hostname=$(hostname)

    # 1. Handle Notification
    if [ "$exit_code" -eq 0 ]; then
        log "Script finished successfully."
        send_pushover "$pushover_token_backup" "Syncoid backup script completed successfully on $script_hostname." "Syncoid Backup SUCCESS" 0 "bike"
    else
        log "Script finished with FAILURE exit code $exit_code."
        # The specific failure notifications are now sent where they occur.
        # This final one is a catch-all in case of an unexpected exit.
        send_pushover "$pushover_token_backup" "Syncoid backup script FAILED on $script_hostname with exit code $exit_code. Check log file $LOG_FILE for details." "Syncoid Backup FAILURE" 0 "siren"
    fi

    # 2. Release Lock
    release_lock
}


# Acquire lock at the start
acquire_lock

# Trap to ensure lock is released AND notification is sent on any exit
trap cleanup_and_notify EXIT


# Check if remote host is available
log "Checking if remote host $REMOTE_HOST is available..."
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" "echo 'Host is reachable'" >> "$LOG_FILE" 2>&1; then
    log "Remote host $REMOTE_HOST is not available or SSH connection failed. Exiting."
    send_pushover "$pushover_token_backup" "Syncoid backup FAILED on $(hostname). Could not connect to remote host $REMOTE_HOST." "Syncoid Backup FAILURE (Host)" 0 "siren"
    exit 1
fi
log "Remote host $REMOTE_HOST is available."

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
            send_pushover "$pushover_token_backup" "Syncoid backup WARNING on $(hostname). Failed to import pool '$current_pool' on $REMOTE_HOST. Skipping." "Syncoid Backup WARNING (Import)" 0
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

                if /usr/sbin/syncoid --no-sync-snap -r "$PROXMOX_DATASET/$current_dataset" "$REMOTE_USER@$REMOTE_HOST:$current_pool/$BACKUP_DATASET/$current_dataset" >> "$LOG_FILE" 2>&1; then
                    log "Backup for dataset '$current_dataset' to '$current_pool' completed successfully."
                else
                    log "Backup for dataset '$current_dataset' to '$current_pool' failed. Check syncoid output in log file on Proxmox."
                    send_pushover "$pushover_token_backup" "Syncoid backup FAILED on $(hostname). Backup of '$current_dataset' to '$current_pool' failed." "Syncoid Backup FAILURE (Sync)" 0 "siren"
                    exit 1
                fi
            done

            log "Finished all dataset backups for pool '$current_pool'."

            if ssh "$REMOTE_USER@$REMOTE_HOST" "$ZPOOL export $current_pool" >> "$LOG_FILE" 2>&1; then
                log "Pool '$current_pool' exported successfully."
            else
                log "Failed to export pool '$current_pool'. It might be busy. Check on $REMOTE_HOST."
                send_pushover "$pushover_token_backup" "Syncoid backup WARNING on $(hostname). Failed to export pool '$current_pool' on $REMOTE_HOST." "Syncoid Backup WARNING (Export)" 0
            fi

            log "Successfully processed pool '$current_pool'."

        else
            log "Failed to load ZFS key for '$current_pool'. Skipping backups for this pool."
            send_pushover "$pushover_token_backup" "Syncoid backup FAILED on $(hostname). Failed to load ZFS key for pool '$current_pool'. Backups for this pool are skipped." "Syncoid Backup FAILURE (Key)" 0 "siren"
            exit 1
        fi
    else
        log "Pool '$current_pool' is found but not in ONLINE state. Skipping."
        send_pushover "$pushover_token_backup" "Syncoid backup WARNING on $(hostname). Pool '$current_pool' is not ONLINE on $REMOTE_HOST. Skipping." "Syncoid Backup WARNING (State)" 0
    fi
done

log "All backup operations completed successfully."
# Script exits (code 0), which triggers the success message in cleanup_and_notify.