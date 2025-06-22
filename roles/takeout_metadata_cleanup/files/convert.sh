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

# Use find to get all .cr3 and .png files (case-insensitive), handling filenames with spaces correctly
find "$TARGET_DIR" -type f \( -iname '*.CR3' -o -iname '*.PNG' \) -print0 | while IFS= read -r -d $'\0' original_path; do
    original_name=$(basename "$original_path")
    file_dir=$(dirname "$original_path")

    echo "Checking: '$original_name'"

    # Parse the filename to extract the prefix and the actual case of the extension.
    if [[ "$original_name" =~ ^(.*?)\.([cC][rR]3|[pP][nN][gG])$ ]]; then
        prefix="${BASH_REMATCH[1]}"
        captured_ext_case="${BASH_REMATCH[2]}"

        # Check the internal MIME type
        mime_type=$(exiftool -MIMEType -s3 "$original_path" 2>/dev/null)

        if [ "$mime_type" == "image/jpeg" ] && [[ "$captured_ext_case" =~ [cC][rR]3 ]]; then
            echo "  - Identified as internal JPEG (CR3)."
            new_name="${prefix}.jpg"
            new_path="${file_dir}/${new_name}"
            echo "  - Proposing CR3 rename: '$original_name' -> '$new_name'"
            mv "$original_path" "$new_path"

            old_json_name="${prefix}.${captured_ext_case}.supplemental-metadata.json"
            old_json_path="${file_dir}/${old_json_name}"
            new_json_name="${prefix}.jpg.supplemental-metadata.json"
            new_json_path="${file_dir}/${new_json_name}"

            if [ -f "$old_json_path" ]; then
                if [ "$old_json_name" != "$new_json_name" ]; then
                    echo "  - Proposing JSON rename: '$old_json_name' -> '$new_json_name'"
                    mv "$old_json_path" "$new_json_path"
                else
                    echo "  - JSON filename already correct. No rename needed."
                fi
            else
                echo "  - Warning: No matching JSON file found for '$original_name' (expected: '$old_json_name'). Skipping JSON rename."
            fi

        elif [[ "$captured_ext_case" =~ [pP][nN][gG] ]]; then
            echo "  - PNG file detected. No conversion needed."
            # Optionally, handle JSON renaming for PNGs
            old_json_name="${prefix}.${captured_ext_case}.supplemental-metadata.json"
            old_json_path="${file_dir}/${old_json_name}"
            new_json_name="${prefix}.png.supplemental-metadata.json"
            new_json_path="${file_dir}/${new_json_name}"

            if [ -f "$old_json_path" ]; then
                if [ "$old_json_name" != "$new_json_name" ]; then
                    echo "  - Proposing JSON rename: '$old_json_name' -> '$new_json_name'"
                    mv "$old_json_path" "$new_json_path"
                else
                    echo "  - JSON filename already correct. No rename needed."
                fi
            else
                echo "  - Warning: No matching JSON file found for '$original_name' (expected: '$old_json_name'). Skipping JSON rename."
            fi

        else
            echo "  - Not an internal JPEG (MIME type: '$mime_type'). Skipping."
        fi
    else
        echo "  - Warning: Filename '$original_name' does not match expected pattern. Skipping."
    fi
    echo "--------------------------------------------------------------------"
done
