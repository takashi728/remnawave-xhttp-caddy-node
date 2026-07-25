#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CANONICAL_PROFILE="$ROOT_DIR/panel-profiles/vless-xhttp-caddy-socket-obfs.json"
HOST_OVERRIDE="$ROOT_DIR/host-overrides/xhttp-obfs-xmux.json"
FAILED=0

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  FAILED=1
}

expect_file() {
  local file="$1"
  local description="$2"

  if [ -f "$file" ]; then
    pass "$description"
  else
    fail "$description"
  fi
}

expect_text() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if [ -f "$file" ] && grep -Eq "$pattern" "$file"; then
    pass "$description"
  else
    fail "$description"
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if [ -f "$file" ] && ! grep -Eq "$pattern" "$file"; then
    pass "$description"
  else
    fail "$description"
  fi
}

expect_jq() {
  local file="$1"
  local expression="$2"
  local description="$3"

  if [ -f "$file" ] && jq -e "$expression" "$file" >/dev/null; then
    pass "$description"
  else
    fail "$description"
  fi
}

while IFS= read -r file; do
  if jq -e . "$file" >/dev/null; then
    pass "${file#"$ROOT_DIR/"} is valid JSON"
  else
    fail "${file#"$ROOT_DIR/"} is valid JSON"
  fi
done < <(find "$ROOT_DIR/panel-profiles" "$ROOT_DIR/host-overrides" -type f -name '*.json' 2>/dev/null | sort)

expect_file "$CANONICAL_PROFILE" "canonical XHTTP Node profile exists"
expect_jq "$CANONICAL_PROFILE" \
  '.inbounds[0] as $inbound
    | $inbound.listen == "/dev/shm/remnawave-xhttp.socket,0666"
      and $inbound.protocol == "vless"
      and $inbound.streamSettings.network == "xhttp"
      and $inbound.streamSettings.security == "none"
      and $inbound.streamSettings.xhttpSettings.path == "/_rw_xhttp_internal"
      and $inbound.streamSettings.xhttpSettings.mode == "packet-up"
      and $inbound.streamSettings.xhttpSettings.scMaxEachPostBytes == 2000000
      and $inbound.streamSettings.xhttpSettings.scMinPostsIntervalMs == 10
      and ($inbound.streamSettings.xhttpSettings
        | .xPaddingObfsMode == true
      and .xPaddingBytes == "16-96"
      and .xPaddingMethod == "tokenish"
      and .xPaddingPlacement == "queryInHeader"
      and .xPaddingHeader == "Referer"
      and .xPaddingKey == "v"
      and .uplinkHTTPMethod == "POST"
      and .uplinkDataPlacement == "body")' \
  "canonical Node profile preserves the tested XHTTP obfuscation preset"
expect_jq "$CANONICAL_PROFILE" \
  '[.. | objects | has("xmux")] | any | not' \
  "canonical Node profile does not contain client XMUX policy"

expect_file "$HOST_OVERRIDE" "canonical Remnawave Host override exists"
expect_jq "$HOST_OVERRIDE" \
  '.xmux.maxConnections == "6" and (.xmux | has("maxConcurrency") | not)' \
  "Host XMUX explicitly uses six connections without maxConcurrency"
expect_jq "$HOST_OVERRIDE" \
  '.mode == "packet-up"
    and .xPaddingObfsMode == true
    and .xPaddingBytes == "16-96"
    and .xPaddingMethod == "tokenish"
    and .xPaddingPlacement == "queryInHeader"
    and .xPaddingHeader == "Referer"
    and .xPaddingKey == "v"
    and .uplinkHTTPMethod == "POST"
    and .uplinkDataPlacement == "body"
    and .scMaxEachPostBytes == 2000000
    and .scMinPostsIntervalMs == 10' \
  "Host override preserves the tested XHTTP obfuscation preset"

expect_file "$ROOT_DIR/panel-profiles/legacy/vless-xhttp-caddy-socket-selfsteal.json" \
  "plain XHTTP profile is retained under legacy"
expect_file "$ROOT_DIR/panel-profiles/legacy/vless-xtls-vision-tls-selfsteal-fallback.json" \
  "Vision fallback profile is retained under legacy"
expect_file "$ROOT_DIR/panel-profiles/legacy/vless-xtls-vision-tls-selfsteal-no-fallback.json" \
  "Vision no-fallback profile is retained under legacy"

for active_legacy_profile in \
  "$ROOT_DIR/panel-profiles/vless-xhttp-caddy-socket-selfsteal.json" \
  "$ROOT_DIR/panel-profiles/vless-xtls-vision-tls-selfsteal-fallback.json" \
  "$ROOT_DIR/panel-profiles/vless-xtls-vision-tls-selfsteal-no-fallback.json"; do
  if [ ! -e "$active_legacy_profile" ]; then
    pass "${active_legacy_profile#"$ROOT_DIR/"} is absent from the active profile area"
  else
    fail "${active_legacy_profile#"$ROOT_DIR/"} is absent from the active profile area"
  fi
done

for bridge in \
  "$ROOT_DIR/panel-profiles/bridge-a-transit-xhttp-obfs-to-b-vision.json" \
  "$ROOT_DIR/panel-profiles/bridge-b-dest-xtls-vision.json"; do
  if [ ! -e "$bridge" ]; then
    pass "${bridge#"$ROOT_DIR/"} is removed"
  else
    fail "${bridge#"$ROOT_DIR/"} is removed"
  fi
done

if cmp -s "$ROOT_DIR/docker/docker-compose.yml" "$ROOT_DIR/docker/docker.yaml"; then
  pass "compose entry points are equivalent"
else
  fail "compose entry points are equivalent"
fi

while IFS= read -r image; do
  if [[ "$image" =~ ^[^@]+:[^@]+@sha256:[0-9a-f]{64}$ ]]; then
    pass "$image is pinned by version and digest"
  else
    fail "$image is pinned by version and digest"
  fi
done < <(sed -n 's/^[[:space:]]*image:[[:space:]]*//p' "$ROOT_DIR/docker/docker-compose.yml")

for image in \
  'caddy:2.11.3@sha256:ec18ee54aab3315c22e25f3b2babda73ff8007d39b13b3bd1bfffa2f0444c7d9' \
  'vectorim/element-web:v1.12.18@sha256:c21772a1eabeededa19be591343f548995e458ec34ba8f27425ae923c10af82e' \
  'remnawave/node:2.8.0@sha256:03f14935751b4ab565181e2b1766ccd1a9ac349d6839acd3ee49014e543fa232'; do
  if grep -Fq "image: $image" "$ROOT_DIR/docker/docker-compose.yml"; then
    pass "$image matches the reviewed release"
  else
    fail "$image matches the reviewed release"
  fi
done

expect_text "$ROOT_DIR/docker/docker-compose.yml" \
  '127\.0\.0\.1:8088:80' \
  "cover service is published only on the local boundary"
expect_text "$ROOT_DIR/docker/docker-compose.yml" \
  'container_name: remnawave-cover-element' \
  "canonical runtime uses cover-service terminology"
reject_text "$ROOT_DIR/docker/docker-compose.yml" \
  'fallback-web|remnawave-fallback-element' \
  "canonical compose does not call the cover service a fallback"
expect_text "$ROOT_DIR/docker/docker-compose.yml" \
  'CUSTOM_CORE_URL: "\$\{CUSTOM_CORE_URL:-\}"' \
  "custom core remains an explicit experimental override"

expect_text "$ROOT_DIR/caddy/Caddyfile.xhttp-socket.template" \
  'reverse_proxy unix//dev/shm/remnawave-xhttp\.socket' \
  "Caddy routes the private XHTTP namespace to the Unix socket"
expect_text "$ROOT_DIR/caddy/Caddyfile.xhttp-socket.template" \
  '@xhttp path \{\{XHTTP_PATH\}\}\*' \
  "Caddy matcher uses only the generated XHTTP namespace"
expect_text "$ROOT_DIR/caddy/Caddyfile.xhttp-socket.template" \
  'uri replace \{\{XHTTP_PATH\}\} /_rw_xhttp_internal' \
  "Caddy rewrites the generated route to the private Node path"
expect_text "$ROOT_DIR/caddy/Caddyfile.xhttp-socket.template" \
  'versions h2c' \
  "Caddy uses h2c on the private Unix-socket hop"
expect_text "$ROOT_DIR/caddy/Caddyfile.xhttp-socket.template" \
  'reverse_proxy 127\.0\.0\.1:8088' \
  "Caddy routes unmatched requests to the cover service"

for script in "$ROOT_DIR"/setup-scripts/*.sh "$ROOT_DIR"/tests/*.sh; do
  if bash -n "$script"; then
    pass "${script#"$ROOT_DIR/"} has valid shell syntax"
  else
    fail "${script#"$ROOT_DIR/"} has valid shell syntax"
  fi
done

for script in \
  "$ROOT_DIR/setup-scripts/install-node-caddy.sh" \
  "$ROOT_DIR/setup-scripts/install-node-caddy-arch.sh" \
  "$ROOT_DIR/setup-scripts/enable-xhttp-socket-caddy.sh" \
  "$ROOT_DIR/setup-scripts/node-status.sh"; do
  expect_text "$script" 'vless-xhttp-caddy-socket-obfs\.json' \
    "${script#"$ROOT_DIR/"} references the canonical profile"
  reject_text "$script" 'enable-vision-fallback|Recommended.*Vision' \
    "${script#"$ROOT_DIR/"} does not recommend Vision"
done

expect_text "$ROOT_DIR/setup-scripts/node-status.sh" \
  'v26\.6\.27' \
  "node status enforces the minimum Xray core version"
expect_text "$ROOT_DIR/setup-scripts/node-status.sh" \
  'remnawave/node:2\.8\.0@sha256:' \
  "node status enforces the reviewed Remnawave Node image"
expect_text "$ROOT_DIR/setup-scripts/node-status.sh" \
  'CUSTOM_CORE_URL' \
  "node status reports custom core usage"
expect_text "$ROOT_DIR/setup-scripts/node-status.sh" \
  'Caddyfile\.xhttp-socket\.template' \
  "node status compares rendered Caddy policy"

expect_text "$ROOT_DIR/README.md" \
  'host-overrides/xhttp-obfs-xmux\.json' \
  "README points operators to the reviewed Host override"
expect_text "$ROOT_DIR/README.md" \
  'v26\.6\.27' \
  "README documents the supported client baseline"
reject_text "$ROOT_DIR/README.md" \
  'enable-vision-fallback-caddy\.sh' \
  "README does not present Vision fallback as a supported workflow"
expect_text "$ROOT_DIR/README.md" \
  'MUX.*unset' \
  "README keeps general Host MUX unset"
expect_file "$ROOT_DIR/docs/adr/0001-xhttp-anti-censorship-baseline.md" \
  "anti-censorship baseline ADR exists"
expect_text "$ROOT_DIR/docs/fresh-vps-smoke-test.md" \
  'node-status\.sh' \
  "fresh-VPS smoke test covers the node policy check"
expect_text "$ROOT_DIR/docs/fresh-vps-smoke-test.md" \
  'MIN_XRAY_VERSION="99\.0\.0"' \
  "fresh-VPS smoke test covers unsupported-core failure"
expect_text "$ROOT_DIR/docs/fresh-vps-smoke-test.md" \
  '/opt/remnanode/certs/fullchain\.pem' \
  "fresh-VPS smoke test checks the host certificate export"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
