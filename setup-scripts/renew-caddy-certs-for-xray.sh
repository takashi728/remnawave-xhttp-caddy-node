#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${1:-/opt/remnanode}"

if [ ! -f "$STACK_DIR/.env" ]; then
  echo "$STACK_DIR/.env not found." >&2
  exit 1
fi

DOMAIN="$(sed -n 's/^DOMAIN=//p' "$STACK_DIR/.env" | tail -n 1)"
EMAIL="$(sed -n 's/^EMAIL=//p' "$STACK_DIR/.env" | tail -n 1)"
VISION_FALLBACK="$(sed -n 's/^VISION_FALLBACK=//p' "$STACK_DIR/.env" | tail -n 1)"

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "DOMAIN or EMAIL is missing from $STACK_DIR/.env" >&2
  exit 1
fi

cd "$STACK_DIR"

if [ ! -f "$STACK_DIR/caddy/Caddyfile.acme.template" ]; then
  echo "$STACK_DIR/caddy/Caddyfile.acme.template not found." >&2
  exit 1
fi

sed \
  -e "s/{{EMAIL}}/$EMAIL/g" \
  -e "s/{{DOMAIN}}/$DOMAIN/g" \
  "$STACK_DIR/caddy/Caddyfile.acme.template" > "$STACK_DIR/caddy/Caddyfile"

docker compose stop remnanode >/dev/null 2>&1 || true
docker compose stop caddy >/dev/null 2>&1 || true
docker compose up -d --force-recreate caddy

for _ in $(seq 1 36); do
  if CERT_EXPORT_QUIET=1 "$STACK_DIR/export-caddy-certs.sh" "$DOMAIN" "$STACK_DIR"; then
    docker compose stop caddy >/dev/null
    docker compose up -d remnanode
    if [ "$VISION_FALLBACK" = "1" ]; then
      "$STACK_DIR/enable-vision-fallback-caddy.sh" "$STACK_DIR"
    fi
    echo "Certificate export complete and remnanode restarted."
    exit 0
  fi
  sleep 5
done

docker compose logs --tail=80 caddy >&2 || true
docker compose stop caddy >/dev/null 2>&1 || true
docker compose up -d remnanode
if [ "$VISION_FALLBACK" = "1" ]; then
  "$STACK_DIR/enable-vision-fallback-caddy.sh" "$STACK_DIR" || true
fi

echo "Certificate export failed; remnanode was restarted." >&2
exit 1
