#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: $0 <target_directory>"
  exit 1
fi

# Assign the first argument to a variable
TARGET_DIR="$1"

# Exit if the target directory is not valid
if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: $TARGET_DIR is not a valid directory."
  exit 1
fi

# --- Script Logic ---
echo "Starting CR3 to JPG conversion and metadata renaming process (without num_part)..."
echo "Files will be processed in: $TARGET_DIR"

# Use find to get all .cr3 files (case-insensitive), handling filenames with spaces correctly
find "$TARGET_DIR" -type f -iname '*.CR3' -print0 | while IFS= read -r -d $'\0' original_cr3_path; do
    original_cr3_name=$(basename "$original_cr3_path")
    cr3_dir=$(dirname "$original_cr3_path")

    echo "Checking: '$original_cr3_name'"

    # 1. Parse the CR3 filename to extract the prefix and the actual case of the CR3 extension.
    # Regex: {ANY_PREFIX}.{CR3_extension_case}
    # (.*?) : non-greedy capture of the prefix (to stop before the last dot)
    # \.    : literal dot
    # ([cC][rR]3) : captures "CR3" or "cr3" or "Cr3" etc., maintaining its case.
    if [[ "$original_cr3_name" =~ ^(.*?)\.([cC][rR]3)$ ]]; then
        prefix="${BASH_REMATCH[1]}"         # e.g., 'IMG_9638'
        captured_cr3_ext_case="${BASH_REMATCH[2]}" # e.g., 'CR3' or 'cr3'

        # 2. Check the internal MIME type of the CR3 file
        mime_type=$(exiftool -MIMEType -s3 "$original_cr3_path" 2>/dev/null) # Redirect stderr to /dev/null

        if [ "$mime_type" == "image/jpeg" ]; then
            echo "  - Identified as internal JPEG."

            # --- Rename the CR3 file to JPG ---
            new_jpg_name="${prefix}.jpg" # Target JPG is always lowercase
            new_jpg_path="${cr3_dir}/${new_jpg_name}"

            echo "  - Proposing CR3 rename: '$original_cr3_name' -> '$new_jpg_name'"
            # Dry run: Print the command
            echo "mv \"$original_cr3_path\" \"$new_jpg_path\""
            # To perform the actual rename, remove 'echo':
            mv "$original_cr3_path" "$new_jpg_path"

            # --- Rename the corresponding JSON file ---
            # Construct the expected ORIGINAL JSON filename using the EXACT CASE of the CR3 extension found.
            old_json_name="${prefix}.${captured_cr3_ext_case}.supplemental-metadata.json"
            old_json_path="${cr3_dir}/${old_json_name}"

            # Construct the NEW JSON filename using .JPG (uppercase as per your example)
            new_json_name="${prefix}.jpg.supplemental-metadata.json"
            new_json_path="${cr3_dir}/${new_json_name}"

            if [ -f "$old_json_path" ]; then
                echo "  - Proposing JSON rename: '$old_json_name' -> '$new_json_name'"
                # Dry run: Print the command
                echo "mv \"$old_json_path\" \"$new_json_path\""
                # To perform the actual rename, remove 'echo':
                mv "$old_json_path" "$new_json_path"
            else
                echo "  - Warning: No matching JSON file found for '$original_cr3_name' (expected: '$old_json_name'). Skipping JSON rename."
            fi
        else
            echo "  - Not an internal JPEG (MIME type: '$mime_type'). Skipping."
        fi
    else
        echo "  - Warning: CR3 filename '$original_cr3_name' does not match expected '{prefix}.CR3' pattern. Skipping."
    fi
    echo "--------------------------------------------------------------------"
done
