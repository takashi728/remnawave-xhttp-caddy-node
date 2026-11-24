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
ESCAPED_XHTTP_PATH="$(escape_sed_replacement "$XHTTP_PATH")"

sed \
  -e "s|{{EMAIL}}|$ESCAPED_EMAIL|g" \
  -e "s|{{DOMAIN}}|$ESCAPED_DOMAIN|g" \
  -e "s|{{XHTTP_PATH}}|$ESCAPED_XHTTP_PATH|g" \
  "$TEMPLATE" > "$STACK_DIR/caddy/Caddyfile"

cd "$STACK_DIR"
docker compose up -d fallback-web
docker compose up -d --force-recreate caddy

set_env_var "$STACK_DIR/.env" "XHTTP_SOCKET_MODE" "1"
set_env_var "$STACK_DIR/.env" "VISION_FALLBACK" "0"

echo "XHTTP socket web mode enabled."
echo "Use panel profile: panel-profiles/vless-xhttp-caddy-socket-selfsteal.json"
echo "In Remnawave Host settings, set Security Layer to TLS and Path to: $XHTTP_PATH"
