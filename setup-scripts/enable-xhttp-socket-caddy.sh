#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${1:-/opt/remnanode}"
TEMPLATE="$STACK_DIR/caddy/Caddyfile.xhttp-socket.template"

if [ ! -f "$STACK_DIR/.env" ]; then
  echo "$STACK_DIR/.env not found." >&2
  exit 1
fi

DOMAIN="$(sed -n 's/^DOMAIN=//p' "$STACK_DIR/.env" | tail -n 1)"
EMAIL="$(sed -n 's/^EMAIL=//p' "$STACK_DIR/.env" | tail -n 1)"
XHTTP_PATH="$(sed -n 's/^XHTTP_PATH=//p' "$STACK_DIR/.env" | tail -n 1)"

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ] || [ -z "$XHTTP_PATH" ]; then
  echo "DOMAIN, EMAIL, or XHTTP_PATH is missing from $STACK_DIR/.env" >&2
  exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "$TEMPLATE not found. Re-run the latest installer first." >&2
  exit 1
fi

sed \
  -e "s/{{EMAIL}}/$EMAIL/g" \
  -e "s/{{DOMAIN}}/$DOMAIN/g" \
  -e "s|{{XHTTP_PATH}}|$XHTTP_PATH|g" \
  "$TEMPLATE" > "$STACK_DIR/caddy/Caddyfile"

cd "$STACK_DIR"
docker compose up -d fallback-web
docker compose stop angie >/dev/null 2>&1 || true
docker compose up -d --force-recreate caddy

if grep -q '^XHTTP_SOCKET_MODE=' "$STACK_DIR/.env"; then
  sed -i 's/^XHTTP_SOCKET_MODE=.*/XHTTP_SOCKET_MODE=1/' "$STACK_DIR/.env"
else
  printf '\nXHTTP_SOCKET_MODE=1\n' >> "$STACK_DIR/.env"
fi

if grep -q '^WEB_FRONTEND=' "$STACK_DIR/.env"; then
  sed -i 's/^WEB_FRONTEND=.*/WEB_FRONTEND=caddy/' "$STACK_DIR/.env"
else
  printf '\nWEB_FRONTEND=caddy\n' >> "$STACK_DIR/.env"
fi

echo "XHTTP socket web mode enabled."
echo "Use panel profile: panel-profiles/vless-xhttp-caddy-socket-selfsteal.json"
echo "In Remnawave Host settings, set Security Layer to TLS and Path to: $XHTTP_PATH"
