#!/bin/bash

# ==============================================================================
# /usr/local/lib/pushover_functions.sh
#
# A library of reusable shell functions. To use in another script, add:
# source /usr/local/lib/pushover_functions.sh
# ==============================================================================

# Function: send_pushover
#
# Sends a notification via the Pushover API.
# It now accepts the API token as the first argument.
# It still expects the 'pushover_user' key to be an environment variable.
#
# Usage: send_pushover "API_TOKEN" "Your message" "Your Title" [priority] [sound]
#
#   - API_TOKEN: The Pushover application token (required).
#   - message: The main body of the notification (required).
#   - title: The title of the notification (optional, defaults to script name).
#   - priority: -2, -1, 0, 1, or 2 (optional, defaults to 0).
#   - sound: Notification sound (optional, defaults to "pushover").
#            Common values: "bike" (success), "siren" (failure), "pushover" (default).
#
send_pushover() {
    # --- Argument Handling ---
    local pushover_token="${1:?Pushover API token (argument 1) is required}"
    local message="${2:?Message (argument 2) is required}"
    local title="${3:-$(basename "$0")}" # Default title to the name of the script calling it
    local priority="${4:-0}"
    local sound="${5:-pushover}"

    # --- Validation (for environment variable) ---
    # Check if the required 'pushover_user' environment variable is set.
    if [[ -z "$pushover_user" ]]; then
        echo "Pushover Error: 'pushover_user' is not set in the environment." >&2
        echo "Ensure it is defined (e.g., in /etc/environment) and the session has loaded it." >&2
        return 1
    fi

    # --- Dependency Check ---
    if ! command -v curl &> /dev/null; then
        echo "Pushover Error: 'curl' command is not found. Please install it." >&2
        return 1
    fi

    # --- API Call ---
    # Use the token from the argument and the user from the environment.
    curl -s \
         --form-string "token=$pushover_token" \
         --form-string "user=$pushover_user" \
         --form-string "message=$message" \
         --form-string "title=$title" \
         --form-string "priority=$priority" \
         --form-string "sound=$sound" \
         "https://api.pushover.net/1/messages.json" > /dev/null
}
