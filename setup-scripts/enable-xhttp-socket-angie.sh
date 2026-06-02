#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${1:-/opt/remnanode}"
TEMPLATE="$STACK_DIR/angie/angie.xhttp-socket.conf.template"

if [ ! -f "$STACK_DIR/.env" ]; then
  echo "$STACK_DIR/.env not found." >&2
  exit 1
fi

DOMAIN="$(sed -n 's/^DOMAIN=//p' "$STACK_DIR/.env" | tail -n 1)"
XHTTP_PATH="$(sed -n 's/^XHTTP_PATH=//p' "$STACK_DIR/.env" | tail -n 1)"

if [ -z "$DOMAIN" ] || [ -z "$XHTTP_PATH" ]; then
  echo "DOMAIN or XHTTP_PATH is missing from $STACK_DIR/.env" >&2
  exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "$TEMPLATE not found. Re-run the latest installer from this branch first." >&2
  exit 1
fi

if [ ! -s "$STACK_DIR/certs/fullchain.pem" ] || [ ! -s "$STACK_DIR/certs/privkey.key" ]; then
  echo "Exported certificates are missing under $STACK_DIR/certs." >&2
  echo "Run the normal Caddy installer/bootstrap first." >&2
  exit 1
fi

sed \
  -e "s/{{DOMAIN}}/$DOMAIN/g" \
  -e "s|{{XHTTP_PATH}}|$XHTTP_PATH|g" \
  "$TEMPLATE" > "$STACK_DIR/angie/angie.conf"

cd "$STACK_DIR"
docker compose up -d fallback-web
docker compose stop caddy >/dev/null 2>&1 || true
docker compose up -d --force-recreate angie

if grep -q '^XHTTP_SOCKET_MODE=' "$STACK_DIR/.env"; then
  sed -i 's/^XHTTP_SOCKET_MODE=.*/XHTTP_SOCKET_MODE=1/' "$STACK_DIR/.env"
else
  printf '\nXHTTP_SOCKET_MODE=1\n' >> "$STACK_DIR/.env"
fi

if grep -q '^WEB_FRONTEND=' "$STACK_DIR/.env"; then
  sed -i 's/^WEB_FRONTEND=.*/WEB_FRONTEND=angie/' "$STACK_DIR/.env"
else
  printf '\nWEB_FRONTEND=angie\n' >> "$STACK_DIR/.env"
fi

echo "Experimental Angie XHTTP socket web mode enabled."
echo "Use panel profile: panel-profiles/vless-xhttp-caddy-socket-selfsteal.json"
echo "In Remnawave Host settings, set Security Layer to TLS and Path to: $XHTTP_PATH"
echo "Note: Angie currently proxies this Unix socket with HTTP/1.1 upstream, not Caddy-style h2c."
