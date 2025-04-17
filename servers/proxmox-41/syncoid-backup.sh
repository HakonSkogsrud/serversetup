#!/bin/bash

# --- Configuration ---
POOL_NAME="wdred"
LOG_FILE="/var/log/syncoid_wdred_cron.log"
DATE_FORMAT="+%Y-%m-%d %H:%M:%S"

# Full paths to commands are recommended in cron jobs
ZPOOL_CMD="/usr/sbin/zpool"
SYNCOID_CMD="/usr/sbin/syncoid"

# Source and Destination Datasets (adjust if needed)
SRC_IMMICH="storage/immich"
DST_IMMICH="wdred/backup/immich"
SRC_SMB="storage/smb"
DST_SMB="wdred/backup/smb"

# --- Script Logic ---

echo "------------------------------------------------------------" >> "$LOG_FILE"
echo "$(date "$DATE_FORMAT") - Cron job started." >> "$LOG_FILE"

# Check if the target ZFS pool is imported and online
# -H suppresses header, -o name outputs only the name if found
if $ZPOOL_CMD list -H -o name "$POOL_NAME" &>/dev/null; then
    echo "$(date "$DATE_FORMAT") - Pool '$POOL_NAME' found and online. Proceeding with Syncoid." >> "$LOG_FILE"

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

else
    # Pool not found or not online
    echo "$(date "$DATE_FORMAT") - Pool '$POOL_NAME' not found or not online. Skipping Syncoid." >> "$LOG_FILE"
    # Exit cleanly so cron doesn't report an error just because the drive isn't connected
    exit 0
fi

echo "$(date "$DATE_FORMAT") - Cron job finished." >> "$LOG_FILE"
echo "" >> "$LOG_FILE" # Add a blank line for readability

exit 0