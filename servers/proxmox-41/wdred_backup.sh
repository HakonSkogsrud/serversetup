#!/bin/bash
# Revised script for backing up ZFS snapshots to an external drive

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
POOL_ID="6621353444686555754" # Unique ID of the backup pool
POOL_NAME="wdred"             # Name of the backup pool
LOG_FILE="/var/log/wdred_backup.log" # Path to the log file

# --- Logging Function ---
log() {
    # Logs message to stdout and the log file with a timestamp
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Error Handling Function ---
handle_error() {
    local error_msg="$1"
    local command_name="$2"
    local line_num="$3"
    
    log "ERROR: ${error_msg} (Command: '${command_name:-N/A}' at line ${line_num:-N/A})"
    log "Attempting cleanup..."
    
    log "Attempting to unload keys for $POOL_NAME..."
    zfs unload-key -r "$POOL_NAME" 2>/dev/null || log "Warning: Key unload during cleanup failed (ignoring)."
    
    log "Attempting to export pool $POOL_NAME..."
    zpool export "$POOL_NAME" 2>/dev/null || log "Warning: Pool export during cleanup failed (ignoring)."
    
    log "Cleanup attempt finished. Exiting due to error."
    exit 1
}

# --- Trap ERR signal ---
trap 'handle_error "Script error occurred" "$BASH_COMMAND" "$LINENO"' ERR

# --- Main Script ---
log "Starting backup process for pool $POOL_NAME"

# Check if the pool is already imported
if zpool list "$POOL_NAME" > /dev/null 2>&1; then
    log "Pool $POOL_NAME is already imported. Skipping import."
else
    log "Attempting to import ZFS pool $POOL_NAME ($POOL_ID)"
    zpool import "$POOL_ID" || handle_error "Failed to import pool $POOL_NAME (ID: $POOL_ID). It might be unavailable." "zpool import $POOL_ID" $?
fi

# Load encryption keys (if any datasets are encrypted)
log "Loading encryption keys for $POOL_NAME"
zfs load-key -r "$POOL_NAME" || handle_error "Failed to load encryption keys for $POOL_NAME" "zfs load-key" $?

# Run syncoid backups
log "Starting backup of immich data (storage/immich -> $POOL_NAME/backup/immich)"
syncoid -r storage/immich "$POOL_NAME/backup/immich" || handle_error "Failed to backup immich data" "syncoid immich" $?

log "Starting backup of smb data (storage/smb -> $POOL_NAME/backup/smb)"
syncoid -r storage/smb "$POOL_NAME/backup/smb" || handle_error "Failed to backup smb data" "syncoid smb" $?

log "Unloading encryption keys for $POOL_NAME"
zfs unload-key -r "$POOL_NAME" || handle_error "Failed to unload encryption keys for $POOL_NAME" "zfs unload-key -r" $?

log "Exporting ZFS pool $POOL_NAME"
zpool export "$POOL_NAME" || handle_error "Failed to export pool $POOL_NAME cleanly" "zpool export" $?

log "Backup process completed successfully for pool $POOL_NAME"

exit 0