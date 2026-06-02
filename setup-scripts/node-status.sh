#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${1:-/opt/remnanode}"

if [ ! -d "$STACK_DIR" ]; then
  echo "Stack directory not found: $STACK_DIR" >&2
  exit 1
fi

if [ ! -f "$STACK_DIR/.env" ]; then
  echo "Environment file not found: $STACK_DIR/.env" >&2
  exit 1
fi

get_env() {
  sed -n "s/^$1=//p" "$STACK_DIR/.env" | tail -n 1
}

DOMAIN="$(get_env DOMAIN)"
EMAIL="$(get_env EMAIL)"
XHTTP_PATH="$(get_env XHTTP_PATH)"
EXTRA_PORTS="$(get_env EXTRA_PORTS)"
VISION_FALLBACK="$(get_env VISION_FALLBACK)"
XHTTP_SOCKET_MODE="$(get_env XHTTP_SOCKET_MODE)"
WEB_FRONTEND="$(get_env WEB_FRONTEND)"

echo "Remnawave node status"
echo
echo "Domain: ${DOMAIN:-missing}"
echo "Email: ${EMAIL:-missing}"
echo "XHTTP host path: ${XHTTP_PATH:-missing}"
echo "Additional inbound TCP ports: ${EXTRA_PORTS:-none}"
echo "Vision fallback mode: ${VISION_FALLBACK:-0}"
echo "XHTTP socket mode: ${XHTTP_SOCKET_MODE:-0}"
echo "Web frontend: ${WEB_FRONTEND:-caddy}"
echo

if [ "${XHTTP_SOCKET_MODE:-0}" = "1" ]; then
  echo "Recommended panel profile:"
  echo "  panel-profiles/vless-xhttp-caddy-socket-selfsteal.json"
  echo "Host path field:"
  echo "  ${XHTTP_PATH:-missing}"
else
  echo "Recommended panel profile:"
  echo "  panel-profiles/vless-xhttp-caddy-socket-selfsteal.json"
  echo "Enable it with:"
  echo "  $STACK_DIR/enable-xhttp-socket-caddy.sh"
  echo "Experimental Angie frontend:"
  echo "  $STACK_DIR/enable-xhttp-socket-angie.sh"
fi

echo
echo "Certificate files:"
for file in "$STACK_DIR/certs/fullchain.pem" "$STACK_DIR/certs/privkey.key"; do
  if [ -s "$file" ]; then
    echo "  ok      $file"
  else
    echo "  missing $file"
  fi
done

echo
echo "Containers:"
if command -v docker >/dev/null 2>&1; then
  docker ps --format '  {{.Names}}\t{{.Status}}\t{{.Ports}}' |
    grep -E 'remnanode|remnawave-caddy|remnawave-angie|remnawave-fallback-element' ||
    echo "  no matching containers running"
else
  echo "  docker command not found"
fi

echo
echo "Listeners:"
if command -v ss >/dev/null 2>&1; then
  ss -tulpn | grep -E ':(80|443|2222|8088|9443)\b' || echo "  no matching listeners found"
else
  echo "  ss command not found"
fi

echo
echo "Socket:"
if [ -S /dev/shm/remnawave-xhttp.socket ]; then
  ls -l /dev/shm/remnawave-xhttp.socket
else
  echo "  /dev/shm/remnawave-xhttp.socket not present"
fi

echo "Firewall:"
if command -v ufw >/dev/null 2>&1; then
  ufw status verbose | sed 's/^/  /'
else
  echo "  ufw command not found"
fi

echo
echo "Generated files:"
for file in \
  "$STACK_DIR/generated-profiles/vless-xhttp-caddy-socket-selfsteal.json" \
  "$STACK_DIR/caddy/Caddyfile" \
  "$STACK_DIR/angie/angie.conf"; do
  if [ -f "$file" ]; then
    echo "  $file"
  fi
done
