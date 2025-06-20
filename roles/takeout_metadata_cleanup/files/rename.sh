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
echo "Starting JSON file renaming process..."
echo "Files will be processed in: $TARGET_DIR"

# Use find to get all .json files, handling filenames with spaces correctly
find "$TARGET_DIR" -type f -name '*.json' -print0 | while IFS= read -r -d $'\0' old_path; do
    old_name=$(basename "$old_path")
    old_dir=$(dirname "$old_path")

    name_without_json_ext="${old_name%.json}"

    # Regex to capture:
    # 1. The initial prefix (anything)
    # 2. The file extension (e.g., jpg, CR3, png - alphanumeric characters only)
    # 3. The number part (1 to 5 digits)
    #
    # Pattern: {ANY_PREFIX}.{EXTENSION}.supplemental-metadata(1-5-digits)
    #          ^^^^^^^^^^^ ^^^^^^^^^^^ This part is new/changed
    if [[ "$name_without_json_ext" =~ ^(.+)\.([a-zA-Z0-9]+)\.supplemental-metadata\(([0-9]{1,5})\)$ ]]; then
        prefix="${BASH_REMATCH[1]}"         # e.g., '2024-03-02', 'my_image'
        file_extension="${BASH_REMATCH[2]}" # e.g., 'jpg', 'CR3', 'png', 'heic'
        num_part="${BASH_REMATCH[3]}"       # e.g., 1542 (1 to 5 digits)

        # Construct the new filename based on the desired pattern
        new_name="${prefix}(${num_part}).${file_extension}.supplemental-metadata.json"
        
        # Construct the full new path
        new_path="${old_dir}/${new_name}"
        echo mv "$old_path" "$new_path"
        mv "$old_path" "$new_path"
    else
        echo "Skipping '$old_name': Does not match the expected '{prefix}.{extension}.supplemental-metadata(1-5-digits).json' pattern."
    fi
done

echo "--------------------------------------------------------------------"
