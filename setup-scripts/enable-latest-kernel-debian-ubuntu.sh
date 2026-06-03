#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root or with sudo." >&2
  exit 1
fi

if [ ! -f /etc/os-release ]; then
  echo "/etc/os-release not found. Cannot detect distro." >&2
  exit 1
fi

. /etc/os-release

red() {
  printf '\033[1;31m%s\033[0m\n' "$*"
}

yellow() {
  printf '\033[1;33m%s\033[0m\n' "$*"
}

green() {
  printf '\033[1;32m%s\033[0m\n' "$*"
}

newest_installed_kernel() {
  local newest

  newest="$(
    find /boot -maxdepth 1 -type f -name 'vmlinuz-*' -printf '%f\n' 2>/dev/null |
      sed 's/^vmlinuz-//' |
      sort -V |
      tail -n 1
  )"

  printf '%s' "$newest"
}

stop_if_reboot_required() {
  local current_kernel newest_kernel

  current_kernel="$(uname -r)"
  newest_kernel="$(newest_installed_kernel)"

  echo "Current running kernel: $current_kernel"

  if [ -z "$newest_kernel" ]; then
    yellow "Could not detect installed kernel images under /boot."
    yellow "Continuing without reboot gate."
    return 0
  fi

  echo "Newest installed kernel: $newest_kernel"

  if [ "$newest_kernel" != "$current_kernel" ]; then
    echo
    red "REBOOT REQUIRED BEFORE NODE DEPLOYMENT"
    yellow "A newer kernel is installed, but this SSH session is still running the old kernel."
    yellow "Please reboot the VPS, reconnect with SSH, then re-run the installer."
    echo
    yellow "After reboot, run again:"
    echo "  curl -fsSL https://raw.githubusercontent.com/takashi728/remnawave-xhttp-caddy-node/new-install-script/setup-scripts/install.sh | sudo bash"
    echo
    yellow "The installer will continue to the email/domain/SECRET_KEY prompts after the new kernel is active."
    exit 75
  fi

  green "Running kernel is already the newest installed kernel. Continuing."
}

install_debian_backports_kernel() {
  local codename="${VERSION_CODENAME:-}"
  local components="main contrib non-free"
  local source_file

  if [ -z "$codename" ]; then
    echo "Debian VERSION_CODENAME is missing; skipping backports kernel setup." >&2
    return 0
  fi

  source_file="/etc/apt/sources.list.d/${codename}-backports.list"

  case "$codename" in
    bookworm|trixie|forky|duke)
      components="main contrib non-free non-free-firmware"
      ;;
  esac

  if [ ! -f "$source_file" ]; then
    echo "Adding Debian backports repository: ${codename}-backports"
    printf 'deb http://deb.debian.org/debian %s-backports %s\n' "$codename" "$components" > "$source_file"
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get update

  if apt-cache policy linux-image-amd64 | grep -q "${codename}-backports"; then
    echo "Installing latest Debian backports kernel package."
    apt-get install -y -t "${codename}-backports" linux-image-amd64 linux-headers-amd64
  else
    echo "Backports kernel is not available for ${codename}; installing distro kernel package."
    apt-get install -y linux-image-amd64 linux-headers-amd64
  fi
}

install_ubuntu_kernel() {
  local version="${VERSION_ID:-}"
  local hwe_pkg="linux-generic"

  export DEBIAN_FRONTEND=noninteractive

  case "$version" in
    22.04|24.04|26.04)
      hwe_pkg="linux-generic-hwe-$version"
      ;;
  esac

  apt-get update

  if apt-cache show "$hwe_pkg" >/dev/null 2>&1; then
    echo "Installing Ubuntu kernel package: $hwe_pkg"
    apt-get install -y "$hwe_pkg"
  else
    echo "$hwe_pkg is unavailable; installing linux-generic."
    apt-get install -y linux-generic
  fi
}

echo "Preparing latest available kernel. This script will not reboot automatically."

case "${ID:-}" in
  debian)
    install_debian_backports_kernel
    ;;
  ubuntu)
    install_ubuntu_kernel
    ;;
  *)
    echo "Kernel helper supports Debian/Ubuntu only. Detected: ${ID:-unknown}" >&2
    exit 1
    ;;
esac

stop_if_reboot_required
