#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1" >&2
  errors=$((errors + 1))
}

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required to run validate.sh" >&2
  exit 1
fi

# 1. All setup-scripts/*.sh pass bash -n
for f in "${ROOT_DIR}"/setup-scripts/*.sh; do
  if bash -n "$f"; then
    pass "bash -n $(basename "$f")"
  else
    fail "bash -n $(basename "$f")"
  fi
done

# 2. All JSON files under panel-profiles/, host-overrides/, and element-web/ parse cleanly with jq empty
for dir in panel-profiles host-overrides element-web; do
  shopt -s nullglob
  files=("${ROOT_DIR}/${dir}"/*.json)
  shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    fail "no JSON files found in ${dir}/"
    continue
  fi
  for f in "${files[@]}"; do
    if jq empty "$f" >/dev/null 2>&1; then
      pass "jq empty ${dir}/$(basename "$f")"
    else
      fail "jq empty ${dir}/$(basename "$f")"
    fi
  done
done

# 3. No panel-profiles/*.json contains "xmux" inside inbounds[].streamSettings.xhttpSettings
for f in "${ROOT_DIR}"/panel-profiles/*.json; do
  if jq -e '([.inbounds[]?.streamSettings?.xhttpSettings? | select(type == "object") | has("xmux")] | any) | not' "$f" >/dev/null 2>&1; then
    pass "no server-side xmux in panel-profiles/$(basename "$f")"
  else
    fail "server-side xmux found in panel-profiles/$(basename "$f")"
  fi
done

# 4. host-overrides/xhttp-obfs-xmux.json sets xmux.maxConnections and does NOT set xmux.maxConcurrency
XMUX_FILE="${ROOT_DIR}/host-overrides/xhttp-obfs-xmux.json"
if [[ -f "$XMUX_FILE" ]] && jq -e '.xmux | (type == "object" and has("maxConnections") and (.maxConnections != null) and (has("maxConcurrency") | not))' "$XMUX_FILE" >/dev/null 2>&1; then
  pass "host-overrides/xhttp-obfs-xmux.json sets xmux.maxConnections without maxConcurrency"
else
  fail "host-overrides/xhttp-obfs-xmux.json must set xmux.maxConnections and omit xmux.maxConcurrency"
fi

# 5. docker/docker-compose.yml and docker/docker.yaml are identical
COMPOSE_FILE="${ROOT_DIR}/docker/docker-compose.yml"
DOCKER_YAML="${ROOT_DIR}/docker/docker.yaml"
if cmp -s "$COMPOSE_FILE" "$DOCKER_YAML"; then
  pass "docker/docker-compose.yml and docker/docker.yaml are identical"
else
  fail "docker/docker-compose.yml and docker/docker.yaml differ"
fi

# 6. docker/docker-compose.yml pins versions, sets GODEBUG, and passes SNI_VERIFICATION
for pattern_desc in \
  'image:[[:space:]]*caddy:2\.11\.9|caddy:2.11.9' \
  'image:[[:space:]]*vectorim/element-web:v1\.12\.36|vectorim/element-web:v1.12.36' \
  'image:[[:space:]]*remnawave/node:3\.4\.6|remnawave/node:3.4.6' \
  'GODEBUG:[[:space:]]*"?multipathtcp=0"?|GODEBUG: "multipathtcp=0"' \
  'SNI_VERIFICATION|SNI_VERIFICATION'; do
  pattern="${pattern_desc%%|*}"
  desc="${pattern_desc##*|}"
  if grep -qE "$pattern" "$COMPOSE_FILE"; then
    pass "docker-compose.yml includes ${desc}"
  else
    fail "docker-compose.yml missing ${desc}"
  fi
done

# 7. setup-scripts/enable-network-tuning.sh configures net.mptcp.enabled = 0
if grep -qE 'net\.mptcp\.enabled[[:space:]]*=[[:space:]]*0' "${ROOT_DIR}/setup-scripts/enable-network-tuning.sh"; then
  pass "enable-network-tuning.sh configures net.mptcp.enabled = 0"
else
  fail "enable-network-tuning.sh missing net.mptcp.enabled = 0"
fi

# 8. setup-scripts/install-node-caddy.sh and install-node-caddy-arch.sh protect .env with chmod 0600
for script in install-node-caddy.sh install-node-caddy-arch.sh; do
  if grep -qE 'chmod[[:space:]]+0600[[:space:]]+.*\.env' "${ROOT_DIR}/setup-scripts/${script}"; then
    pass "${script} protects .env with chmod 0600"
  else
    fail "${script} missing chmod 0600 on .env"
  fi
done

if [[ "$errors" -gt 0 ]]; then
  echo "Validation failed with ${errors} error(s)." >&2
  exit 1
fi

echo "All validation checks passed."
