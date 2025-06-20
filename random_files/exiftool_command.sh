exiftool -r -d %s -tagsfromfile "%d/%F.json" "-GPSAltitude<GeoDataAltitude" "-GPSLatitude<GeoDataLatitude" "-GPSLatitudeRef<GeoDataLatitude" "-GPSLongitude<GeoDataLongitude" "-GPSLongitudeRef<GeoDataLongitude" "-Keywords<Tags" "-Subject<Tags" "-Caption-Abstract<Description" "-ImageDescription<Description" "-DateTimeOriginal<PhotoTakenTimeTimestamp" -ext "*" -overwrite_original -progress --ext json <DirToProcess>


find . -name '*\(1\)*.json' -print0 |
while IFS= read -r -d '' file; do
if [[ "${file}" =~ ^(.*)\.(.*)\(1\)\.json$ ]]; then
mv "${BASH_REMATCH[0]}" "${BASH_REMATCH[1]}(1).${BASH_REMATCH[2]}.json";
else
exit 1
fi
done