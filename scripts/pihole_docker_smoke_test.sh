#!/usr/bin/env bash
set -euo pipefail

HOST_IP="${1:-10.0.0.86}"
SSH_TARGET="${2:-haaksk@${HOST_IP}}"
GOOD_DOMAIN="${GOOD_DOMAIN:-google.com}"
BLOCK_DOMAIN="${BLOCK_DOMAIN:-flurry.com}"
BASE_DIR="${BASE_DIR:-/home/haaksk/pihole}"
DATA_DIR="${DATA_DIR:-${BASE_DIR}/etc-pihole}"
CONFIG_FILE="${CONFIG_FILE:-${DATA_DIR}/pihole.toml}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

section() {
  printf '\n== %s ==\n' "$1"
}

remote() {
  ssh -o StrictHostKeyChecking=no "$SSH_TARGET" bash -s -- "$BASE_DIR" "$DATA_DIR" "$CONFIG_FILE" <<'EOF'
set -euo pipefail

BASE_DIR="$1"
DATA_DIR="$2"
CONFIG_FILE="$3"

if command -v docker >/dev/null 2>&1; then
  DOCKER_BIN=docker
else
  DOCKER_BIN='sudo docker'
fi

echo '[docker ps]'
$DOCKER_BIN ps --filter name=pihole

echo
echo '[recent logs]'
$DOCKER_BIN logs --tail 40 pihole

echo
echo '[files]'
ls -ld "$BASE_DIR" "$DATA_DIR"
test -f "$CONFIG_FILE"
ls -l "$CONFIG_FILE"

echo
echo '[ports]'
ss -lntup | grep -E ':(53|80)\b' || true

echo
echo '[firewalld]'
if command -v firewall-cmd >/dev/null 2>&1; then
  sudo firewall-cmd --list-ports
fi
EOF
}

need_cmd ssh
need_cmd dig
need_cmd curl

section "Remote container checks"
remote

section "DNS resolution"
GOOD_RESULT="$(dig +short @"$HOST_IP" "$GOOD_DOMAIN" A | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
if [ -z "$GOOD_RESULT" ]; then
  echo "Failed: no A record returned for $GOOD_DOMAIN"
  exit 1
fi
printf 'Resolved %s via %s: %s\n' "$GOOD_DOMAIN" "$HOST_IP" "$GOOD_RESULT"

section "DNS blocking"
BLOCK_A="$(dig +short @"$HOST_IP" "$BLOCK_DOMAIN" A | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
BLOCK_AAAA="$(dig +short @"$HOST_IP" "$BLOCK_DOMAIN" AAAA | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
printf 'A answer for %s: %s\n' "$BLOCK_DOMAIN" "${BLOCK_A:-<empty>}"
printf 'AAAA answer for %s: %s\n' "$BLOCK_DOMAIN" "${BLOCK_AAAA:-<empty>}"

if [ "$BLOCK_A" = "0.0.0.0" ] || [ "$BLOCK_AAAA" = "::" ] || { [ -z "$BLOCK_A" ] && [ -z "$BLOCK_AAAA" ]; }; then
  echo "Blocking looks correct"
else
  echo "Blocking may not be working for $BLOCK_DOMAIN"
  exit 1
fi

section "Admin UI"
HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' "http://${HOST_IP}/admin/")"
printf 'GET http://%s/admin/ -> %s\n' "$HOST_IP" "$HTTP_CODE"
if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "302" ]; then
  echo "Unexpected admin UI response"
  exit 1
fi

section "Summary"
echo "Smoke test passed for ${HOST_IP}"
echo "Next manual step: log into http://${HOST_IP}/admin/ and create a visible test change before force_recreate testing."