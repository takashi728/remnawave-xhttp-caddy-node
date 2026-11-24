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
NODE_PORT="$(get_env NODE_PORT)"
SNI_VERIFICATION="$(get_env SNI_VERIFICATION)"
SECRET_KEY="$(get_env SECRET_KEY)"
XHTTP_PATH="$(get_env XHTTP_PATH)"
EXTRA_PORTS="$(get_env EXTRA_PORTS)"
VISION_FALLBACK="$(get_env VISION_FALLBACK)"
XHTTP_SOCKET_MODE="$(get_env XHTTP_SOCKET_MODE)"

echo "Remnawave node status"
echo
echo "Domain: ${DOMAIN:-missing}"
echo "Email: ${EMAIL:-missing}"
echo "Node API port: ${NODE_PORT:-2222}"
echo "SNI verification: ${SNI_VERIFICATION:-not set}"
ENV_PERMS="$(stat -c '%a' "$STACK_DIR/.env" 2>/dev/null || echo unknown)"
if [ "$ENV_PERMS" = "600" ]; then
  echo "Env permissions: $ENV_PERMS (ok)"
else
  echo "Env permissions: $ENV_PERMS (WARNING: expected 600; run chmod 600 $STACK_DIR/.env)"
fi
if [ -z "$SECRET_KEY" ]; then
  echo "SECRET_KEY: missing (WARNING: set SECRET_KEY in $STACK_DIR/.env)"
elif [ "$SECRET_KEY" = "replace-with-remnawave-node-secret-key" ]; then
  echo "SECRET_KEY: placeholder (WARNING: replace default SECRET_KEY in $STACK_DIR/.env)"
else
  echo "SECRET_KEY: configured"
fi
echo "Running kernel: $(uname -r)"
if [ -r /proc/sys/net/mptcp/enabled ]; then
  MPTCP_ENABLED="$(tr -d '[:space:]' < /proc/sys/net/mptcp/enabled 2>/dev/null || echo unknown)"
  if [ "$MPTCP_ENABLED" = "1" ]; then
    echo "Host MPTCP: 1 (WARNING: enabled; run $STACK_DIR/enable-network-tuning.sh and ensure kernel is patched for CVE-2026-98432)"
  else
    echo "Host MPTCP: $MPTCP_ENABLED"
  fi
else
  echo "Host MPTCP: not supported / disabled"
fi
echo "XHTTP host path: ${XHTTP_PATH:-missing}"
echo "Additional inbound TCP ports: ${EXTRA_PORTS:-none}"
echo "Vision fallback mode: ${VISION_FALLBACK:-0}"
echo "XHTTP socket mode: ${XHTTP_SOCKET_MODE:-0}"
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
if [ -s "$STACK_DIR/certs/fullchain.pem" ] && command -v openssl >/dev/null 2>&1; then
  CERT_EXPIRY="$(openssl x509 -in "$STACK_DIR/certs/fullchain.pem" -noout -enddate 2>/dev/null || true)"
  if [ -n "$CERT_EXPIRY" ]; then
    echo "  expiry  $CERT_EXPIRY"
  fi
fi

echo
echo "Containers:"
if command -v docker >/dev/null 2>&1; then
  docker ps --format '  {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' |
    grep -E 'remnanode|remnawave-caddy|remnawave-fallback-element' ||
    echo "  no matching containers running"
  if docker ps --format '{{.Names}}' | grep -qx 'remnanode'; then
    XRAY_VERSION="$(docker exec remnanode rw-core version 2>/dev/null | head -n 1 || true)"
    if [ -n "$XRAY_VERSION" ]; then
      echo "  remnanode core: $XRAY_VERSION"
    fi
  fi
else
  echo "  docker command not found"
fi

echo
echo "Listeners:"
if command -v ss >/dev/null 2>&1; then
  LISTEN_PORTS="80|443|2222|8088|9443"
  if [[ "${NODE_PORT:-}" =~ ^[0-9]+$ ]] && [ "$NODE_PORT" != "2222" ]; then
    LISTEN_PORTS="80|443|2222|${NODE_PORT}|8088|9443"
  fi
  ss -tulpn | grep -E ":($LISTEN_PORTS)\b" || echo "  no matching listeners found"
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
  "$STACK_DIR/generated-profiles/vless-xhttp-caddy-socket-obfs.json" \
  "$STACK_DIR/generated-profiles/xhttp-obfs-xmux.json" \
  "$STACK_DIR/caddy/Caddyfile"; do
  if [ -f "$file" ]; then
    echo "  $file"
  fi
done
