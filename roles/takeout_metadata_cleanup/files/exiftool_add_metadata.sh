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

exiftool -r -d %s -tagsfromfile "%d/%F.supplemental-metadata.json" "-GPSAltitude<GeoDataAltitude" "-GPSLatitude<GeoDataLatitude" "-GPSLatitudeRef<GeoDataLatitude" "-GPSLongitude<GeoDataLongitude" "-GPSLongitudeRef<GeoDataLongitude" "-Keywords<Tags" "-Subject<Tags" "-Caption-Abstract<Description" "-ImageDescription<Description" "-DateTimeOriginal<PhotoTakenTimeTimestamp" -ext "*" -overwrite_original -progress --ext json "$TARGET_DIR"