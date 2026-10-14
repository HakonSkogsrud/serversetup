#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
image_ref="${IMAGE_REF:-10.0.0.139:5000/my-kinoite:44-candidate}"
image_version="${IMAGE_VERSION:-44-$(date -u +%Y%m%dT%H%M%SZ)}"
sudo podman build --pull=always --no-cache --build-arg IMAGE_VERSION="$image_version" \
    -t "$image_ref" . 2>&1 | tee build.log
sudo podman image inspect "$image_ref" > build-image.json

# The temporary LAN registry uses HTTP. Publishing is deliberately explicit.
if [[ "${PUBLISH:-0}" == 1 ]]; then
    sudo podman push --tls-verify=false "$image_ref"
fi
