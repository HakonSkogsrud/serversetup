#!/bin/bash

# --- Configuration ---
POOL_WDRED="wdred"
POOL_SGBLACK="sgblack"
LOG_FILE="/var/log/syncoid_backup_cron.log"
DATE_FORMAT="+%Y-%m-%d %H:%M:%S"

# Full paths to commands are recommended in cron jobs
ZPOOL_CMD="/usr/sbin/zpool"
SYNCOID_CMD="/usr/sbin/syncoid"

# Source and Destination Datasets (adjust if needed)
SRC_IMMICH="storage/immich"
SRC_SMB="storage/smb"

# --- Script Logic ---

echo "------------------------------------------------------------" >> "$LOG_FILE"
echo "$(date "$DATE_FORMAT") - Cron job started." >> "$LOG_FILE"

# Determine which pool is available
TARGET_POOL=""
if $ZPOOL_CMD list -H -o name "$POOL_WDRED" &>/dev/null; then
    TARGET_POOL="$POOL_WDRED"
    echo "$(date "$DATE_FORMAT") - Pool '$POOL_WDRED' found and online. Proceeding with Syncoid." >> "$LOG_FILE"
elif $ZPOOL_CMD list -H -o name "$POOL_SGBLACK" &>/dev/null; then
    TARGET_POOL="$POOL_SGBLACK"
    echo "$(date "$DATE_FORMAT") - Pool '$POOL_SGBLACK' found and online. Proceeding with Syncoid." >> "$LOG_FILE"
else
    echo "$(date "$DATE_FORMAT") - No target pool found or online. Skipping Syncoid." >> "$LOG_FILE"
    # Exit cleanly so cron doesn't report an error just because the drives aren't connected
    exit 0
fi

# Set destination datasets based on the target pool
DST_IMMICH="$TARGET_POOL/backup/immich"
DST_SMB="$TARGET_POOL/backup/smb"

# Run Syncoid for immich dataset
echo "$(date "$DATE_FORMAT") - Starting Syncoid for $SRC_IMMICH -> $DST_IMMICH..." >> "$LOG_FILE"
if $SYNCOID_CMD -r "$SRC_IMMICH" "$DST_IMMICH" >> "$LOG_FILE" 2>&1; then
    echo "$(date "$DATE_FORMAT") - Syncoid for immich completed successfully." >> "$LOG_FILE"
else
    echo "$(date "$DATE_FORMAT") - !!! ERROR: Syncoid for immich failed. Exit status: $?. Check log above for details." >> "$LOG_FILE"
fi

# Run Syncoid for smb dataset
echo "$(date "$DATE_FORMAT") - Starting Syncoid for $SRC_SMB -> $DST_SMB..." >> "$LOG_FILE"
if $SYNCOID_CMD -r "$SRC_SMB" "$DST_SMB" >> "$LOG_FILE" 2>&1; then
    echo "$(date "$DATE_FORMAT") - Syncoid for smb completed successfully." >> "$LOG_FILE"
else
    echo "$(date "$DATE_FORMAT") - !!! ERROR: Syncoid for smb failed. Exit status: $?. Check log above for details." >> "$LOG_FILE"
fi

echo "$(date "$DATE_FORMAT") - Cron job finished." >> "$LOG_FILE"
echo "" >> "$LOG_FILE" # Add a blank line for readability

exit 0