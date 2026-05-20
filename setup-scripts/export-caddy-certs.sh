#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-${DOMAIN:-}}"
STACK_DIR="${2:-/opt/remnanode}"

if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <domain> [stack_dir]" >&2
  exit 1
fi

CERT_DIR="$STACK_DIR/certs"
CADDY_CERT_ROOT="$STACK_DIR/caddy_data/caddy/certificates/acme-v02.api.letsencrypt.org-directory"
SRC_DIR="$CADDY_CERT_ROOT/$DOMAIN"

mkdir -p "$CERT_DIR"

if [ ! -f "$SRC_DIR/$DOMAIN.crt" ] || [ ! -f "$SRC_DIR/$DOMAIN.key" ]; then
  echo "Caddy certificate not found for $DOMAIN under $SRC_DIR" >&2
  echo "Start Caddy first and make sure DNS points to this node." >&2
  exit 1
fi

install -m 0644 "$SRC_DIR/$DOMAIN.crt" "$CERT_DIR/fullchain.pem"
install -m 0600 "$SRC_DIR/$DOMAIN.key" "$CERT_DIR/privkey.key"

echo "Exported:"
echo "  $CERT_DIR/fullchain.pem -> /etc/nginx/certs/fullchain.pem"
echo "  $CERT_DIR/privkey.key   -> /etc/nginx/certs/privkey.key"
