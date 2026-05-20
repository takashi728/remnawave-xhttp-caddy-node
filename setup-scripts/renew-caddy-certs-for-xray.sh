#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${1:-/opt/remnanode}"

if [ ! -f "$STACK_DIR/.env" ]; then
  echo "$STACK_DIR/.env not found." >&2
  exit 1
fi

DOMAIN="$(sed -n 's/^DOMAIN=//p' "$STACK_DIR/.env" | tail -n 1)"

if [ -z "$DOMAIN" ]; then
  echo "DOMAIN is missing from $STACK_DIR/.env" >&2
  exit 1
fi

cd "$STACK_DIR"

docker compose stop remnanode >/dev/null 2>&1 || true
docker compose up -d caddy

for _ in $(seq 1 36); do
  if "$STACK_DIR/export-caddy-certs.sh" "$DOMAIN" "$STACK_DIR"; then
    docker compose stop caddy >/dev/null
    docker compose up -d remnanode
    echo "Certificate export complete and remnanode restarted."
    exit 0
  fi
  sleep 5
done

docker compose logs --tail=80 caddy >&2 || true
docker compose stop caddy >/dev/null 2>&1 || true
docker compose up -d remnanode

echo "Certificate export failed; remnanode was restarted." >&2
exit 1
