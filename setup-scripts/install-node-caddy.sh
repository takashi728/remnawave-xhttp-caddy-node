#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root or with sudo." >&2
  exit 1
fi

read -r -p "Email for Let's Encrypt: " EMAIL
read -r -p "Node domain, for example node.example.com: " DOMAIN
read -r -s -p "Remnawave SECRET_KEY: " SECRET_KEY
echo

if [ -z "$EMAIL" ] || [ -z "$DOMAIN" ] || [ -z "$SECRET_KEY" ]; then
  echo "Email, domain, and SECRET_KEY are required." >&2
  exit 1
fi

STACK_DIR="/opt/remnanode"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

echo "[1/7] Installing Docker prerequisites"
apt-get update
apt-get install -y ca-certificates curl openssl ufw

DEFAULT_XHTTP_PATH="/api/$(openssl rand -hex 16)"
read -r -p "XHTTP path [$DEFAULT_XHTTP_PATH]: " XHTTP_PATH
XHTTP_PATH="${XHTTP_PATH:-$DEFAULT_XHTTP_PATH}"

if ! printf '%s' "$XHTTP_PATH" | grep -Eq '^/[A-Za-z0-9._~/-]+$'; then
  echo "XHTTP path must start with / and only contain letters, numbers, dots, dashes, underscores, tildes, and slashes." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin is unavailable after Docker install." >&2
  exit 1
fi

echo "[2/7] Preparing $STACK_DIR"
mkdir -p "$STACK_DIR/caddy" "$STACK_DIR/selfsteal" "$STACK_DIR/certs" "$STACK_DIR/element-web" "$STACK_DIR/generated-profiles"

cp "$PROJECT_DIR/docker/docker-compose.yml" "$STACK_DIR/docker-compose.yml"
cp "$PROJECT_DIR/selfsteal/index.html" "$STACK_DIR/selfsteal/index.html"
cp "$PROJECT_DIR/element-web/config.json" "$STACK_DIR/element-web/config.json"
cp "$PROJECT_DIR/caddy/Caddyfile.template" "$STACK_DIR/caddy/Caddyfile.acme.template"
cp "$PROJECT_DIR/caddy/Caddyfile.fallback.template" "$STACK_DIR/caddy/Caddyfile.fallback.template"
cp "$PROJECT_DIR/caddy/Caddyfile.xhttp-socket.template" "$STACK_DIR/caddy/Caddyfile.xhttp-socket.template"
cp "$PROJECT_DIR/panel-profiles/vless-xhttp-tls-selfsteal-no-fallback.template.json" "$STACK_DIR/generated-profiles/vless-xhttp-tls-selfsteal-no-fallback.template.json"
cp "$PROJECT_DIR/panel-profiles/vless-xhttp-caddy-socket-selfsteal.template.json" "$STACK_DIR/generated-profiles/vless-xhttp-caddy-socket-selfsteal.template.json"
cp "$PROJECT_DIR/setup-scripts/export-caddy-certs.sh" "$STACK_DIR/export-caddy-certs.sh"
cp "$PROJECT_DIR/setup-scripts/renew-caddy-certs-for-xray.sh" "$STACK_DIR/renew-caddy-certs-for-xray.sh"
cp "$PROJECT_DIR/setup-scripts/enable-vision-fallback-caddy.sh" "$STACK_DIR/enable-vision-fallback-caddy.sh"
cp "$PROJECT_DIR/setup-scripts/enable-xhttp-socket-caddy.sh" "$STACK_DIR/enable-xhttp-socket-caddy.sh"
chmod +x "$STACK_DIR/export-caddy-certs.sh" "$STACK_DIR/renew-caddy-certs-for-xray.sh" "$STACK_DIR/enable-vision-fallback-caddy.sh" "$STACK_DIR/enable-xhttp-socket-caddy.sh"

sed \
  -e "s/{{EMAIL}}/$EMAIL/g" \
  -e "s/{{DOMAIN}}/$DOMAIN/g" \
  "$PROJECT_DIR/caddy/Caddyfile.template" > "$STACK_DIR/caddy/Caddyfile"

cat > "$STACK_DIR/.env" <<EOF
SECRET_KEY=$SECRET_KEY
DOMAIN=$DOMAIN
EMAIL=$EMAIL
XHTTP_PATH=$XHTTP_PATH
VISION_FALLBACK=0
XHTTP_SOCKET_MODE=0
EOF

sed \
  -e "s|{{XHTTP_PATH}}|$XHTTP_PATH|g" \
  "$PROJECT_DIR/panel-profiles/vless-xhttp-tls-selfsteal-no-fallback.template.json" > "$STACK_DIR/generated-profiles/vless-xhttp-tls-selfsteal-no-fallback.generated.json"

sed \
  -e "s|{{XHTTP_PATH}}|$XHTTP_PATH|g" \
  "$PROJECT_DIR/panel-profiles/vless-xhttp-caddy-socket-selfsteal.template.json" > "$STACK_DIR/generated-profiles/vless-xhttp-caddy-socket-selfsteal.generated.json"

touch "$STACK_DIR/certs/fullchain.pem" "$STACK_DIR/certs/privkey.key"
chmod 0600 "$STACK_DIR/certs/privkey.key"

echo "[3/7] Opening firewall"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 2222/tcp
ufw --force enable

echo "[4/7] Starting Caddy for ACME bootstrap"
cd "$STACK_DIR"
docker compose stop caddy >/dev/null 2>&1 || true
docker compose up -d --force-recreate caddy

echo "[5/7] Waiting for Caddy certificate"
for attempt in $(seq 1 36); do
  if CERT_EXPORT_QUIET=1 "$STACK_DIR/export-caddy-certs.sh" "$DOMAIN" "$STACK_DIR"; then
    break
  fi
  echo "Waiting for certificate for $DOMAIN ($attempt/36). Verify this domain resolves to this VPS if it does not complete."
  sleep 5
done

if [ ! -s "$STACK_DIR/certs/fullchain.pem" ] || [ ! -s "$STACK_DIR/certs/privkey.key" ]; then
  echo "Certificate export failed for $DOMAIN." >&2
  echo "Make sure you entered the intended DNS name and its A/AAAA record points to this VPS." >&2
  echo "Then rerun this installer; it will recreate Caddy with the new domain." >&2
  echo "Recent Caddy logs:" >&2
  docker compose logs --tail=80 caddy >&2 || true
  exit 1
fi

echo "[6/7] Starting Remnawave node"
docker compose stop caddy >/dev/null
docker compose up -d remnanode

echo "[7/7] Installing weekly cert renewal cron"
cat > /etc/cron.d/remnawave-caddy-cert-export <<EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
17 3 * * 2 root $STACK_DIR/renew-caddy-certs-for-xray.sh $STACK_DIR >/var/log/remnawave-caddy-cert-export.log 2>&1
EOF

echo
echo "Done."
echo "Domain: $DOMAIN"
echo "Caddy: ACME bootstrap/renewal only; stopped during normal Xray service"
echo "Remnawave node: 2222"
echo "XHTTP path for panel/client: $XHTTP_PATH"
echo "Generated XHTTP panel profile: $STACK_DIR/generated-profiles/vless-xhttp-tls-selfsteal-no-fallback.generated.json"
echo "Generated XHTTP socket panel profile: $STACK_DIR/generated-profiles/vless-xhttp-caddy-socket-selfsteal.generated.json"
echo "Select the generated profile that matches the host mode you want to use."
