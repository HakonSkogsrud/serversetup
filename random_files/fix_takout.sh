#!/bin/bash
set -e
while read -r json_file; do
  dirname=$(dirname "$json_file")
  picture_ts=$(jq -r '.photoTakenTime|.timestamp' "$json_file")
  filename=$(jq -r '.title' "$json_file")
  if [[ "$filename" != "null" ]]; then
    filename="$dirname/$filename"
    if [[ -e "$filename" ]]; then
      touch_string=$(date -d "@$picture_ts" +%Y%m%d%H%M)
      touch -m -t "$touch_string" "$filename"
    else
      >&2 echo "Cannot find $filename referenced by $json_file"
    fi
  fi
done < <( find ./ -name '*.json' )
