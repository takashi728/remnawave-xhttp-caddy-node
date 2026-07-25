#!/usr/bin/env bash
set -uo pipefail

STACK_DIR="${1:-/opt/remnanode}"
MIN_XRAY_VERSION="26.6.27"
EXPECTED_CADDY_IMAGE="caddy:2.11.3@sha256:ec18ee54aab3315c22e25f3b2babda73ff8007d39b13b3bd1bfffa2f0444c7d9"
EXPECTED_ELEMENT_IMAGE="vectorim/element-web:v1.12.18@sha256:c21772a1eabeededa19be591343f548995e458ec34ba8f27425ae923c10af82e"
EXPECTED_NODE_IMAGE="remnawave/node:2.8.0@sha256:03f14935751b4ab565181e2b1766ccd1a9ac349d6839acd3ee49014e543fa232"
FAILED=0

ok() {
  printf '  ok    %s\n' "$1"
}

warn() {
  printf '  warn  %s\n' "$1"
}

fail() {
  printf '  fail  %s\n' "$1" >&2
  FAILED=1
}

get_env() {
  sed -n "s/^$1=//p" "$STACK_DIR/.env" | tail -n 1
}

version_at_least() {
  local current="$1"
  local minimum="$2"
  local current_major current_minor current_patch
  local minimum_major minimum_minor minimum_patch

  IFS=. read -r current_major current_minor current_patch <<< "$current"
  IFS=. read -r minimum_major minimum_minor minimum_patch <<< "$minimum"

  ((current_major > minimum_major)) ||
    ((current_major == minimum_major && current_minor > minimum_minor)) ||
    ((current_major == minimum_major && current_minor == minimum_minor && current_patch >= minimum_patch))
}

check_container() {
  local container="$1"
  local expected_image="$2"
  local actual_image running

  if ! actual_image="$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null)"; then
    fail "$container does not exist"
    return
  fi

  if [ "$actual_image" = "$expected_image" ]; then
    ok "$container uses reviewed image: $actual_image"
  else
    fail "$container image drift: $actual_image"
  fi

  running="$(docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null || true)"
  if [ "$running" = "true" ]; then
    ok "$container is running"
  else
    fail "$container is not running"
  fi
}

if [ ! -d "$STACK_DIR" ]; then
  echo "Stack directory not found: $STACK_DIR" >&2
  exit 1
fi

if [ ! -f "$STACK_DIR/.env" ]; then
  echo "Environment file not found: $STACK_DIR/.env" >&2
  exit 1
fi

DOMAIN="$(get_env DOMAIN)"
EMAIL="$(get_env EMAIL)"
XHTTP_PATH="$(get_env XHTTP_PATH)"
EXTRA_PORTS="$(get_env EXTRA_PORTS)"
XHTTP_SOCKET_MODE="$(get_env XHTTP_SOCKET_MODE)"

echo "Remnawave node policy status"
echo
echo "Configuration:"
echo "  Domain: ${DOMAIN:-missing}"
echo "  Email: ${EMAIL:-missing}"
echo "  XHTTP Host path: ${XHTTP_PATH:-missing}"
echo "  Additional inbound TCP ports: ${EXTRA_PORTS:-none}"
echo "  Canonical Node profile: panel-profiles/vless-xhttp-caddy-socket-obfs.json"
echo "  Canonical Host override: host-overrides/xhttp-obfs-xmux.json"

if [ -n "$DOMAIN" ] && [ -n "$EMAIL" ] && [ -n "$XHTTP_PATH" ]; then
  ok "required deployment values are present"
else
  fail "DOMAIN, EMAIL, or XHTTP_PATH is missing"
fi

if [ "${XHTTP_SOCKET_MODE:-0}" = "1" ]; then
  ok "XHTTP socket mode is active"
else
  fail "XHTTP socket mode is inactive; run $STACK_DIR/enable-xhttp-socket-caddy.sh"
fi

echo
echo "Certificates:"
for file in "$STACK_DIR/certs/fullchain.pem" "$STACK_DIR/certs/privkey.key"; do
  if [ -s "$file" ]; then
    ok "$file"
  else
    fail "$file is missing or empty"
  fi
done

echo
echo "Runtime policy:"
if ! command -v docker >/dev/null 2>&1; then
  fail "docker command is unavailable"
else
  check_container remnanode "$EXPECTED_NODE_IMAGE"

  if [ "${XHTTP_SOCKET_MODE:-0}" = "1" ]; then
    check_container remnawave-caddy "$EXPECTED_CADDY_IMAGE"
    check_container remnawave-cover-element "$EXPECTED_ELEMENT_IMAGE"
  fi

  XRAY_VERSION_OUTPUT="$(docker exec remnanode rw-core version 2>/dev/null | head -n 1 || true)"
  XRAY_VERSION="$(printf '%s' "$XRAY_VERSION_OUTPUT" | grep -Eo 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 | sed 's/^v//' || true)"
  if [ -z "$XRAY_VERSION" ]; then
    fail "cannot determine Xray-core version"
  elif version_at_least "$XRAY_VERSION" "$MIN_XRAY_VERSION"; then
    ok "Xray-core v$XRAY_VERSION meets minimum v26.6.27"
  else
    fail "Xray-core v$XRAY_VERSION is below minimum v26.6.27"
  fi

  CUSTOM_CORE_URL="$(
    docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' remnanode 2>/dev/null |
      sed -n 's/^CUSTOM_CORE_URL=//p' |
      tail -n 1
  )"
  if [ -n "$CUSTOM_CORE_URL" ]; then
    warn "experimental CUSTOM_CORE_URL is active; verify provenance and compatibility: $CUSTOM_CORE_URL"
  else
    ok "CUSTOM_CORE_URL is not set"
  fi
fi

if command -v docker >/dev/null 2>&1 && [ "${XHTTP_SOCKET_MODE:-0}" = "1" ]; then
  ELEMENT_BINDING="$(docker port remnawave-cover-element 80/tcp 2>/dev/null || true)"
  if [ "$ELEMENT_BINDING" = "127.0.0.1:8088" ]; then
    ok "cover service is bound only to 127.0.0.1:8088"
  else
    fail "unexpected cover-service binding: ${ELEMENT_BINDING:-none}"
  fi
fi

echo
echo "Files and routing:"
for file in \
  "$STACK_DIR/generated-profiles/vless-xhttp-caddy-socket-obfs.json" \
  "$STACK_DIR/generated-profiles/xhttp-obfs-xmux-host-override.json" \
  "$STACK_DIR/caddy/Caddyfile"; do
  if [ -s "$file" ]; then
    ok "$file"
  else
    fail "$file is missing or empty"
  fi
done

if [ -s "$STACK_DIR/caddy/Caddyfile.xhttp-socket.template" ]; then
  EXPECTED_CADDYFILE="$(
    sed \
      -e "s/{{EMAIL}}/$EMAIL/g" \
      -e "s/{{DOMAIN}}/$DOMAIN/g" \
      -e "s|{{XHTTP_PATH}}|$XHTTP_PATH|g" \
      "$STACK_DIR/caddy/Caddyfile.xhttp-socket.template"
  )"
else
  EXPECTED_CADDYFILE=""
fi

if [ -n "$EXPECTED_CADDYFILE" ] &&
  [ "$(cat "$STACK_DIR/caddy/Caddyfile" 2>/dev/null || true)" = "$EXPECTED_CADDYFILE" ]; then
  ok "Caddyfile matches the rendered XHTTP socket policy"
else
  fail "Caddyfile differs from the rendered XHTTP socket policy"
fi

if [ -S /dev/shm/remnawave-xhttp.socket ]; then
  ok "/dev/shm/remnawave-xhttp.socket is present"
else
  fail "/dev/shm/remnawave-xhttp.socket is absent"
fi

if [ -f "$STACK_DIR/docker-compose.yml" ]; then
  for image in "$EXPECTED_CADDY_IMAGE" "$EXPECTED_ELEMENT_IMAGE" "$EXPECTED_NODE_IMAGE"; do
    if grep -Fq "image: $image" "$STACK_DIR/docker-compose.yml"; then
      ok "compose pins $image"
    else
      fail "compose does not pin $image"
    fi
  done
else
  fail "$STACK_DIR/docker-compose.yml is missing"
fi

echo
echo "Network:"
if command -v ss >/dev/null 2>&1; then
  LISTENERS="$(ss -tulpn 2>/dev/null | grep -E ':(80|443|2222|8088|9443)\b' || true)"
  if [ -n "$LISTENERS" ]; then
    printf '%s\n' "$LISTENERS" | sed 's/^/  /'
  else
    warn "no expected listeners found"
  fi
else
  warn "ss command is unavailable"
fi

if command -v ufw >/dev/null 2>&1; then
  ufw status verbose 2>/dev/null | sed 's/^/  /' || warn "cannot read UFW status"
else
  warn "UFW is unavailable; inspect the active firewall separately"
fi

echo
if [ "$FAILED" -ne 0 ]; then
  echo "Policy check failed." >&2
  exit 1
fi

echo "Policy check passed."
