#!/usr/bin/env bash
set -euo pipefail

SYSCTL_FILE="/etc/sysctl.d/99-remnawave-network-tuning.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root or with sudo." >&2
  exit 1
fi

cat > "$SYSCTL_FILE" <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
EOF

sysctl --system >/dev/null

echo "Network tuning applied:"
echo "  $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | sed 's/^/tcp_congestion_control = /')"
echo "  $(sysctl -n net.core.default_qdisc 2>/dev/null | sed 's/^/default_qdisc = /')"
echo "  $(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null | sed 's/^/tcp_fastopen = /')"
echo
echo "Config file: $SYSCTL_FILE"
