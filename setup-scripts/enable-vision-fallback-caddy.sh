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

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

set_env_var() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  local tmp_file

  tmp_file="$(mktemp "${env_file}.XXXXXX")"
  chmod 0600 "$tmp_file"
  SET_ENV_KEY="$key" SET_ENV_VAL="$value" awk '
    BEGIN { k = ENVIRON["SET_ENV_KEY"]; v = ENVIRON["SET_ENV_VAL"]; found = 0 }
    index($0, k "=") == 1 {
      if (!found) {
        print k "=" v
        found = 1
      }
      next
    }
    { print }
    END {
      if (!found) {
        print k "=" v
      }
    }
  ' "$env_file" > "$tmp_file"
  chmod 0600 "$tmp_file"
  mv "$tmp_file" "$env_file"
  chmod 0600 "$env_file"
}

ESCAPED_EMAIL="$(escape_sed_replacement "$EMAIL")"
ESCAPED_DOMAIN="$(escape_sed_replacement "$DOMAIN")"

sed \
  -e "s|{{EMAIL}}|$ESCAPED_EMAIL|g" \
  -e "s|{{DOMAIN}}|$ESCAPED_DOMAIN|g" \
  "$TEMPLATE" > "$STACK_DIR/caddy/Caddyfile"

cd "$STACK_DIR"
docker compose up -d fallback-web
docker compose up -d --force-recreate caddy

set_env_var "$STACK_DIR/.env" "VISION_FALLBACK" "1"
set_env_var "$STACK_DIR/.env" "XHTTP_SOCKET_MODE" "0"

echo "Caddy fallback enabled on 127.0.0.1:9443."
echo "Use panel profile: panel-profiles/vless-xtls-vision-tls-selfsteal-fallback.json"
