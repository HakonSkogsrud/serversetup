#!/bin/bash

# ==============================================================================
# /usr/local/lib/logging.sh
#
# A centralized logging library with JSON output for structured logging.
# To use in another script, add:
#   LOG_FILE="/var/log/your-script.log"
#   SCRIPT_NAME="your-script"  # Optional, defaults to basename of calling script
#   source /usr/local/lib/logging.sh
# ==============================================================================

# Default log file (scripts should override by setting LOG_FILE before sourcing)
: ${LOG_FILE:="/var/log/automation.log"}

# Script name for identification (defaults to calling script name)
: ${SCRIPT_NAME:="$(basename "${BASH_SOURCE[-1]}")"}

# Function: log
#
# Logs a message with structured JSON output
#
# Usage: log "LEVEL" "Your message"
#   - LEVEL: INFO, WARNING, or ERROR (required)
#   - message: The log message (required)
#
log() {
    local level="${1^^}"  # Uppercase the level
    local message="$2"
    local timestamp="$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')"
    local hostname="$(hostname)"

    # Escape double quotes and backslashes in message for JSON
    local escaped_message="${message//\\/\\\\}"
    escaped_message="${escaped_message//\"/\\\"}"

    # JSON format - single line for easy parsing
    local json_log="{\"timestamp\":\"${timestamp}\",\"level\":\"${level}\",\"script\":\"${SCRIPT_NAME}\",\"host\":\"${hostname}\",\"message\":\"${escaped_message}\"}"

    echo "$json_log" | tee -a "$LOG_FILE"
}
