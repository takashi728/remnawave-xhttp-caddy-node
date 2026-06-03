#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root or with sudo." >&2
  exit 1
fi

REPO_OWNER="${REMNAWAVE_INSTALL_REPO_OWNER:-takashi728}"
REPO_NAME="${REMNAWAVE_INSTALL_REPO_NAME:-remnawave-xhttp-caddy-node}"
BRANCH="${REMNAWAVE_INSTALL_BRANCH:-new-install-script}"
ARCHIVE_URL="https://github.com/$REPO_OWNER/$REPO_NAME/archive/refs/heads/$BRANCH.tar.gz"

if [ ! -f /etc/os-release ]; then
  echo "/etc/os-release not found. Cannot detect distro." >&2
  exit 1
fi

. /etc/os-release

install_fetch_deps() {
  case "${ID:-}" in
    ubuntu|debian)
      apt-get update
      apt-get install -y ca-certificates curl tar gzip
      ;;
    arch|artix|endeavouros|manjaro)
      pacman -Sy --needed --noconfirm ca-certificates curl tar gzip
      ;;
    *)
      echo "Unsupported distro for bootstrap installer: ${ID:-unknown}" >&2
      echo "Supported: Ubuntu, Debian, Arch-based Linux." >&2
      exit 1
      ;;
  esac
}

select_installer() {
  case "${ID:-}" in
    ubuntu|debian)
      printf '%s\n' "setup-scripts/install-node-caddy.sh"
      ;;
    arch|artix|endeavouros|manjaro)
      printf '%s\n' "setup-scripts/install-node-caddy-arch.sh"
      ;;
    *)
      echo "Unsupported distro for bootstrap installer: ${ID:-unknown}" >&2
      exit 1
      ;;
  esac
}

echo "Remnawave node bootstrap"
echo "Distro: ${PRETTY_NAME:-${ID:-unknown}}"
echo "Source: $REPO_OWNER/$REPO_NAME branch $BRANCH"

update_system_no_reboot() {
  echo "Updating system packages. This installer will not reboot automatically."
  case "${ID:-}" in
    ubuntu|debian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
      ;;
    arch|artix|endeavouros|manjaro)
      pacman -Syu --noconfirm
      ;;
    *)
      echo "Unsupported distro for bootstrap installer: ${ID:-unknown}" >&2
      exit 1
      ;;
  esac
}

update_system_no_reboot
install_fetch_deps

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

ARCHIVE="$WORK_DIR/repo.tar.gz"
echo "Downloading deployment bundle..."
curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE"

tar -xzf "$ARCHIVE" -C "$WORK_DIR"
PROJECT_DIR="$(find "$WORK_DIR" -maxdepth 1 -type d -name "$REPO_NAME-*" | head -n 1)"

if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  echo "Failed to locate extracted deployment bundle." >&2
  exit 1
fi

INSTALLER="$(select_installer)"
if [ ! -f "$PROJECT_DIR/$INSTALLER" ]; then
  echo "Installer not found in bundle: $INSTALLER" >&2
  exit 1
fi

chmod +x "$PROJECT_DIR/$INSTALLER"
echo "Running: $INSTALLER"
exec bash "$PROJECT_DIR/$INSTALLER"
