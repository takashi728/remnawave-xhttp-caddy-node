#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${1:-/opt/remnanode}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$STACK_DIR/caddy/Caddyfile.fallback.template"

if [ ! -f "$STACK_DIR/.env" ]; then
  echo "$STACK_DIR/.env not found." >&2
  exit 1
fi

DOMAIN="$(sed -n 's/^DOMAIN=//p' "$STACK_DIR/.env" | tail -n 1)"
EMAIL="$(sed -n 's/^EMAIL=//p' "$STACK_DIR/.env" | tail -n 1)"

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "DOMAIN or EMAIL is missing from $STACK_DIR/.env" >&2
  exit 1
fi

if [ ! -s "$STACK_DIR/certs/fullchain.pem" ] || [ ! -s "$STACK_DIR/certs/privkey.key" ]; then
  echo "Certificate files are missing under $STACK_DIR/certs." >&2
  echo "Run install-node-caddy.sh or renew-caddy-certs-for-xray.sh first." >&2
  exit 1
fi

mkdir -p "$STACK_DIR/caddy"

if [ ! -f "$TEMPLATE" ] && [ -f "$PROJECT_DIR/caddy/Caddyfile.fallback.template" ]; then
  cp "$PROJECT_DIR/caddy/Caddyfile.fallback.template" "$TEMPLATE"
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "Fallback Caddyfile template not found." >&2
  echo "Expected $TEMPLATE or $PROJECT_DIR/caddy/Caddyfile.fallback.template" >&2
  exit 1
fi

sed \
  -e "s/{{EMAIL}}/$EMAIL/g" \
  -e "s/{{DOMAIN}}/$DOMAIN/g" \
  "$TEMPLATE" > "$STACK_DIR/caddy/Caddyfile"

cd "$STACK_DIR"
docker compose up -d --remove-orphans cover-web
docker compose up -d --force-recreate caddy

if grep -q '^VISION_FALLBACK=' "$STACK_DIR/.env"; then
  sed -i 's/^VISION_FALLBACK=.*/VISION_FALLBACK=1/' "$STACK_DIR/.env"
else
  printf '\nVISION_FALLBACK=1\n' >> "$STACK_DIR/.env"
fi

echo "Caddy fallback enabled on 127.0.0.1:9443."
echo "Use legacy panel profile: panel-profiles/legacy/vless-xtls-vision-tls-selfsteal-fallback.json"
