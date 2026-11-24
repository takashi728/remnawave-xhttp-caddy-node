#!/usr/bin/env bash
set -euo pipefail

SYSCTL_FILE="/etc/sysctl.d/99-remnawave-network-tuning.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root or with sudo." >&2
  exit 1
fi

mptcp_was_enabled=""
if [ -r /proc/sys/net/mptcp/enabled ]; then
  mptcp_was_enabled="$(tr -d '[:space:]' < /proc/sys/net/mptcp/enabled 2>/dev/null || true)"
fi

cat > "$SYSCTL_FILE" <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
EOF

if [ -e /proc/sys/net/mptcp/enabled ]; then
  cat >> "$SYSCTL_FILE" <<'EOF'
# CVE-2026-98432 defense-in-depth: disable Linux MPTCP unless explicitly required
net.mptcp.enabled = 0
EOF
fi

sysctl --system >/dev/null

echo "Network tuning applied:"
echo "  $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | sed 's/^/tcp_congestion_control = /')"
echo "  $(sysctl -n net.core.default_qdisc 2>/dev/null | sed 's/^/default_qdisc = /')"
echo "  $(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null | sed 's/^/tcp_fastopen = /')"
if [ -e /proc/sys/net/mptcp/enabled ]; then
  mptcp_now="$(sysctl -n net.mptcp.enabled 2>/dev/null || cat /proc/sys/net/mptcp/enabled 2>/dev/null || echo unknown)"
  echo "  net.mptcp.enabled = $mptcp_now"
  if [ -n "$mptcp_was_enabled" ] && [ "$mptcp_was_enabled" != "0" ]; then
    echo "  Note: MPTCP was previously enabled; restart running services (or reboot) so existing sockets do not keep MPTCP active."
  fi
else
  echo "  net.mptcp.enabled = not supported / disabled"
fi
echo
echo "Config file: $SYSCTL_FILE"
