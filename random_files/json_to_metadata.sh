#!/bin/bash

# Script to embed Google Takeout JSON metadata into photo files using exiftool.

# Check if exiftool is installed
if ! command -v exiftool &> /dev/null
then
    echo "Error: exiftool is not installed."
    echo "Please install it using: sudo apt update && sudo apt install libimage-exiftool-perl"
    exit 1
fi

# Check if a directory argument is provided
if [ -z "$1" ]
then
    echo "Usage: $0 /path/to/your/google/takeout/photos/folder"
    exit 1
fi

# Set the root directory for processing
TAKEOUT_DIR="$1"

# Check if the provided directory exists
if [ ! -d "$TAKEOUT_DIR" ]
then
    echo "Error: Directory '$TAKEOUT_DIR' not found."
    exit 1
fi

echo "Starting metadata embedding process in: $TAKEOUT_DIR"

# Find all image files (case-insensitive)
find "$TAKEOUT_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.tif" -o -iname "*.tiff" \) | while read -r IMAGE_FILE
do
    # Get the base filename without extension and path
    BASENAME=$(basename "$IMAGE_FILE")
    DIRNAME=$(dirname "$IMAGE_FILE")
    FILENAME_NO_EXT="${BASENAME%.*}"
    IMAGE_EXT="${BASENAME##*.}"

    # Construct potential JSON filenames based on Google Takeout patterns
    JSON_FILE_1="$DIRNAME/$BASENAME.json"         # e.g., photo.jpg.json
    JSON_FILE_2="$DIRNAME/$FILENAME_NO_EXT.json" # e.g., photo.json

    # Check for the corresponding JSON file
    JSON_FILE=""
    if [ -f "$JSON_FILE_1" ]; then
        JSON_FILE="$JSON_FILE_1"
    elif [ -f "$JSON_FILE_2" ]; then
        JSON_FILE="$JSON_FILE_2"
    fi

    # If a JSON file is found, attempt to embed metadata
    if [ -f "$JSON_FILE" ]; then
        echo "Processing: $IMAGE_FILE with metadata from $JSON_FILE"
        # Use exiftool to apply metadata from the JSON file
        # -json= : Reads metadata from the specified JSON file
        # -overwrite_original : Overwrite the original image file
        # -progress : Display progress indicator
        exiftool -json="$JSON_FILE" -overwrite_original -progress "$IMAGE_FILE"

        # Optional: Remove the JSON file after embedding
        # Uncomment the line below if you want to delete the JSON files
        # rm "$JSON_FILE"
    else
        echo "No corresponding JSON file found for: $IMAGE_FILE. Skipping."
    fi

done

echo "Metadata embedding process finished."
