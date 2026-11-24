# Remnawave Node & Caddy Deployment

Deployment bundle for Remnawave nodes paired with Caddy (automatic ACME certificates, HTTPS termination in XHTTP socket mode or reverse proxy fallback) and Element Web as a local cover site. Supports Ubuntu 22.04+, Debian 11+ (amd64/arm64), and Arch Linux.

## Pinned Stack & Security Baseline

| Component | Version / Setting | Key Characteristics |
| :--- | :--- | :--- |
| **Remnawave Node** | `remnawave/node:3.4.6` | Bundles Xray-core `v26.11.9` with built-in RootCAs, Chrome 155+ uTLS default, MPTCP disabled by default, strict JSON validation (`XRAY_JSON_STRICT=true`), strict `SECRET_KEY` checks, optional derived-SNI gating on port `2222` (`SNI_VERIFICATION`), and Node.js `24.22` (fixes CVE-2026-111497). |
| **Caddy Server** | `caddy:2.11.9` | ACME TLS termination, reverse proxy, and Unix socket streaming with `GODEBUG=multipathtcp=0`. |
| **Element Web** | `vectorim/element-web:v1.12.36` | Local cover site (`127.0.0.1:8088`), active only when XHTTP socket mode or Vision fallback mode is enabled. |

### Vulnerability Mitigation (CVE-2026-98432)
Linux kernel IPv4 TCP/MPTCP RCE is mitigated across this stack by:
1. Updating the host kernel and rebooting (`enable-latest-kernel-debian-ubuntu.sh`).
2. Setting `GODEBUG=multipathtcp=0` in Caddy.
3. Upgrading Xray to `v26.11.9`.
4. Disabling kernel MPTCP (`net.mptcp.enabled=0`) via `enable-network-tuning.sh`.

## Requirements

- **OS**: Ubuntu 22.04+, Debian 11+, or Arch Linux (amd64 or arm64)
- **Privileges**: Root or `sudo` access
- **DNS**: A and/or AAAA record pointing your domain to the VPS IP address
- **Secret**: A valid Remnawave node `SECRET_KEY`

## Installation

Clone the repository onto your VPS and run the installer:

```bash
git clone https://github.com/takashi728/remnawave-xhttp-caddy-node.git
cd remnawave-xhttp-caddy-node
sudo bash setup-scripts/install-node-caddy.sh
```

*(For Arch Linux, use `sudo bash setup-scripts/install-node-caddy-arch.sh`)*

### Installer Prompts
1. **Let's Encrypt Email**: For ACME certificate registration and renewal notices.
2. **Node Domain**: Your fully qualified domain name (e.g. `node.example.com`).
3. **Extra TCP Ports**: Optional additional inbound ports or ranges (comma-separated, e.g. `10000-10005,20000`).
4. **Remnawave SECRET_KEY**: Your node secret key from the panel.
5. **SNI Verification**: Optional derived-SNI gating on port `2222` (`y/N`).
6. **XHTTP Path**: Auto-generated random endpoint path (e.g. `/api/abcdef...`), or custom.

### Kernel Updates
On Debian/Ubuntu, the installer prepares the latest available distro kernel (backports on Debian, HWE/generic on Ubuntu). It does not reboot automatically. If a new kernel is installed, reboot your VPS. To bypass kernel checks:
```bash
sudo SKIP_KERNEL_UPDATE=1 bash setup-scripts/install-node-caddy.sh
```

All runtime files are placed in `/opt/remnanode`, with `.env` permissions locked to `0600`.

## Panel Profiles & Enabling Web Mode

Add the node in your Remnawave panel and apply one of the profile configurations from `panel-profiles/`.

### 1. Recommended — XHTTP over Caddy Unix Socket
This mode routes incoming HTTPS traffic through Caddy over a Unix socket (`/dev/shm/remnawave-xhttp.socket`), keeping Xray off public ports.

- **Profile File**: `panel-profiles/vless-xhttp-caddy-socket-obfs.json` (obfuscated `packet-up` mode) or `panel-profiles/vless-xhttp-caddy-socket-selfsteal.json` (`auto` mode).
- **Client Extra Settings**: Use `host-overrides/xhttp-obfs-xmux.json` (`maxConnections: "3"`, matching Xray `v26.7.28+` anti-TSPU default; leave general outbound MUX unset; do not combine `maxConcurrency` with `maxConnections`).
- **Panel Host Settings**:
  - **Address**: Your node domain
  - **Port**: `443`
  - **Security Layer**: `TLS` (do not leave on inherited/none)
  - **SNI**: Your node domain
  - **ALPN**: `h2`
  - **Fingerprint**: `chrome`
  - **Host Path**: The generated `XHTTP_PATH` (printed during install or in `/opt/remnanode/node-status.sh`)

Enable Caddy socket mode on the server:
```bash
sudo /opt/remnanode/enable-xhttp-socket-caddy.sh
```

### 2. XTLS-Vision (Optional / Legacy)
- **Profile Files**: `panel-profiles/vless-xtls-vision-tls-selfsteal-no-fallback.json` or `panel-profiles/vless-xtls-vision-tls-selfsteal-fallback.json` (flow: `xtls-rprx-vision`).
- **Enable Fallback Site**:
  ```bash
  sudo /opt/remnanode/enable-vision-fallback-caddy.sh
  ```
> [!NOTE]
> XHTTP socket mode and Vision fallback mode are mutually exclusive on a single node instance.

### Advanced & Test Profiles
The `panel-profiles/` directory also includes test and bridge configurations (`xhttp-obfs-test.json`, `bridge-a-transit-xhttp-obfs-to-b-vision.json`, `bridge-b-dest-xtls-vision.json`) for experimental multi-hop setups.

## Operations & Maintenance

### Status Check
Run the status check to inspect containers, bundled Xray version, certificate expiry, `.env` permissions, kernel MPTCP state, firewall rules, and the XHTTP socket:
```bash
sudo /opt/remnanode/node-status.sh
```

### Network Tuning & MPTCP Mitigation
Apply TCP BBR congestion control, fast-open, and disable MPTCP:
```bash
sudo /opt/remnanode/enable-network-tuning.sh
```

### Container Management
```bash
# View running containers
docker ps

# Check node logs
docker logs remnanode --tail=100
```

### Certificate Renewal
ACME certificates renew automatically via a cron job:
```bash
cat /etc/cron.d/remnawave-caddy-cert-export
```

### Optional Environment Settings
Edit `/opt/remnanode/.env` to adjust:
- `NODE_PORT` (default `2222`)
- `SNI_VERIFICATION` (`true`/`false`)
- `CUSTOM_CORE_URL`
- `NFTABLES_TABLE_NAME` (`remnanode`)
- `SUPPRESS_DUPLICATE_INSTANCE_WARNING`

### Uninstallation
```bash
# Stop and remove containers
sudo /opt/remnanode/uninstall-node.sh

# Remove containers and purge all runtime data/certs
sudo PURGE_DATA=1 /opt/remnanode/uninstall-node.sh
```

### Local Repository Validation
```bash
bash tests/validate.sh
```
