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
apt-get install -y ca-certificates curl ufw

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin is unavailable after Docker install." >&2
  exit 1
fi

echo "[2/7] Preparing $STACK_DIR"
mkdir -p "$STACK_DIR/caddy" "$STACK_DIR/selfsteal" "$STACK_DIR/certs"

cp "$PROJECT_DIR/docker/docker-compose.yml" "$STACK_DIR/docker-compose.yml"
cp "$PROJECT_DIR/selfsteal/index.html" "$STACK_DIR/selfsteal/index.html"
cp "$PROJECT_DIR/setup-scripts/export-caddy-certs.sh" "$STACK_DIR/export-caddy-certs.sh"
chmod +x "$STACK_DIR/export-caddy-certs.sh"

sed \
  -e "s/{{EMAIL}}/$EMAIL/g" \
  -e "s/{{DOMAIN}}/$DOMAIN/g" \
  "$PROJECT_DIR/caddy/Caddyfile.template" > "$STACK_DIR/caddy/Caddyfile"

cat > "$STACK_DIR/.env" <<EOF
SECRET_KEY=$SECRET_KEY
DOMAIN=$DOMAIN
EMAIL=$EMAIL
EOF

touch "$STACK_DIR/certs/fullchain.pem" "$STACK_DIR/certs/privkey.key"
chmod 0600 "$STACK_DIR/certs/privkey.key"

echo "[3/7] Opening firewall"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 2222/tcp
ufw --force enable

echo "[4/7] Starting Caddy for ACME"
cd "$STACK_DIR"
docker compose up -d caddy

echo "[5/7] Waiting for Caddy certificate"
for _ in $(seq 1 36); do
  if "$STACK_DIR/export-caddy-certs.sh" "$DOMAIN" "$STACK_DIR"; then
    break
  fi
  sleep 5
done

if [ ! -s "$STACK_DIR/certs/fullchain.pem" ] || [ ! -s "$STACK_DIR/certs/privkey.key" ]; then
  echo "Certificate export failed. Check: docker logs remnawave-caddy" >&2
  exit 1
fi

echo "[6/7] Starting Remnawave node"
docker compose up -d remnanode

echo "[7/7] Installing daily cert export cron"
cat > /etc/cron.d/remnawave-caddy-cert-export <<EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
17 3 * * * root $STACK_DIR/export-caddy-certs.sh $DOMAIN $STACK_DIR >/var/log/remnawave-caddy-cert-export.log 2>&1 && docker restart remnanode >/dev/null 2>&1
EOF

echo
echo "Done."
echo "Domain: $DOMAIN"
echo "Caddy: 80/443"
echo "Remnawave node: 2222"
echo "XHTTP path for panel/client: /api/v1/data"
echo "Xray local inbound expected by panel profile: 127.0.0.1:10001"
