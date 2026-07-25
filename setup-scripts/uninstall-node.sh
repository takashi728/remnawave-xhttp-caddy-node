#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${1:-/opt/remnanode}"
PURGE_DATA="${PURGE_DATA:-0}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root or with sudo." >&2
  exit 1
fi

echo "This will remove the Remnawave node stack from: $STACK_DIR"
echo "It will not uninstall Docker and will not change UFW rules."

if [ "$PURGE_DATA" = "1" ]; then
  echo "PURGE_DATA=1: runtime data, certs, and Caddy storage will be deleted."
else
  echo "Runtime data will be preserved under $STACK_DIR."
fi

read -r -p "Continue? [y/N]: " CONFIRM
case "$CONFIRM" in
  y|Y|yes|YES) ;;
  *)
    echo "Aborted."
    exit 0
    ;;
esac

if [ -d "$STACK_DIR" ] && [ -f "$STACK_DIR/docker-compose.yml" ]; then
  cd "$STACK_DIR"
  docker compose down --remove-orphans || true
fi

for container in \
  remnanode \
  remnawave-caddy \
  remnawave-cover-element \
  remnawave-fallback-element \
  remnawave-tor-proxy \
  remnawave-warp-socks; do
  docker rm -f "$container" >/dev/null 2>&1 || true
done

rm -f /etc/cron.d/remnawave-caddy-cert-export

if [ -d "$STACK_DIR" ]; then
  rm -f "$STACK_DIR/docker-compose.yml"
  rm -f "$STACK_DIR/export-caddy-certs.sh"
  rm -f "$STACK_DIR/renew-caddy-certs-for-xray.sh"
  rm -f "$STACK_DIR/enable-vision-fallback-caddy.sh"
  rm -f "$STACK_DIR/enable-xhttp-socket-caddy.sh"
  rm -f "$STACK_DIR/enable-latest-kernel-debian-ubuntu.sh"
  rm -f "$STACK_DIR/enable-network-tuning.sh"
  rm -f "$STACK_DIR/enable-warp-socks.sh"
  rm -f "$STACK_DIR/node-status.sh"
  rm -rf "$STACK_DIR/tor"
  rm -rf "$STACK_DIR/routing-examples"
  rm -rf "$STACK_DIR/generated-profiles"
  rm -rf "$STACK_DIR/caddy"
  rm -rf "$STACK_DIR/selfsteal"
  rm -rf "$STACK_DIR/element-web"

  if [ "$PURGE_DATA" = "1" ]; then
    rm -rf "$STACK_DIR/certs"
    rm -rf "$STACK_DIR/caddy_data"
    rm -rf "$STACK_DIR/caddy_config"
    rm -rf "$STACK_DIR/fallback-web-data"
    rm -f "$STACK_DIR/.env"
    rmdir "$STACK_DIR" >/dev/null 2>&1 || true
  fi
fi

rm -f /dev/shm/remnawave-xhttp.socket

echo "Uninstall complete."
if [ "$PURGE_DATA" != "1" ]; then
  echo "Preserved data may remain under: $STACK_DIR"
  echo "To delete everything, rerun with: sudo PURGE_DATA=1 $0 $STACK_DIR"
fi
