#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${1:-/opt/remnanode}"

if [ ! -f "$STACK_DIR/docker-compose.yml" ]; then
  echo "$STACK_DIR/docker-compose.yml not found." >&2
  exit 1
fi

cd "$STACK_DIR"
docker compose --profile warp up -d warp-socks

if [ -f "$STACK_DIR/.env" ]; then
  if grep -q '^WARP_SOCKS_MODE=' "$STACK_DIR/.env"; then
    sed -i 's/^WARP_SOCKS_MODE=.*/WARP_SOCKS_MODE=1/' "$STACK_DIR/.env"
  else
    printf '\nWARP_SOCKS_MODE=1\n' >> "$STACK_DIR/.env"
  fi
fi

echo "WARP SOCKS service enabled on 127.0.0.1:40000."
echo "Use outboundTag WARP in Remnawave routing rules to send selected traffic through it."
