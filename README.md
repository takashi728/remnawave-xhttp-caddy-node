# Remnawave Node Deployment Bundle

Deployment files for Remnawave Nodes on Ubuntu/Debian and Arch Linux.

## Supported Baseline

The recommended mode is VLESS XHTTP over a private Unix socket behind Caddy TLS:

- Node profile: `panel-profiles/vless-xhttp-caddy-socket-obfs.json`
- Host XHTTP Extra/XMUX: `host-overrides/xhttp-obfs-xmux.json`
- Minimum client core: Xray-core `v26.6.27`
- Remnawave Node: `2.8.0`

The Node profile owns the server transport. The Host override owns client XHTTP
parameters and XMUX. Leave the separate Remnawave Host **MUX** setting unset.

## Requirements

- Ubuntu 22.04+, Debian 11+, or Arch Linux
- root or sudo access
- a domain record pointing to the VPS
- a Remnawave Node secret key
- TCP `80`, `443`, and `2222`, plus the selected SSH port

## Install

Ubuntu/Debian:

```bash
git clone https://github.com/takashi728/remnawave-xhttp-caddy-node.git
cd remnawave-xhttp-caddy-node
sudo bash setup-scripts/install-node-caddy.sh
```

Arch Linux:

```bash
sudo bash setup-scripts/install-node-caddy-arch.sh
```

The installer asks for the ACME email, node domain, optional firewall ports,
XHTTP path, and Remnawave Node secret. Accept the generated random path unless
an external system requires a fixed value.

On Debian/Ubuntu, the installer prepares the latest available distro kernel
without rebooting. Debian uses backports when available; Ubuntu uses its
matching HWE/generic package. To skip that step:

```bash
sudo SKIP_KERNEL_UPDATE=1 bash setup-scripts/install-node-caddy.sh
```

When the installer finishes, enable the recommended web mode:

```bash
sudo /opt/remnanode/enable-xhttp-socket-caddy.sh
```

## Panel Setup

Create a Config Profile from:

```text
panel-profiles/vless-xhttp-caddy-socket-obfs.json
```

Create or edit its public Host:

| Field | Value |
|---|---|
| Address | node domain, or the proxied CDN hostname |
| Port | `443` |
| SNI | node domain |
| Host | node domain |
| Path | path printed by the installer |
| Security Layer | `TLS` |
| ALPN | `h2` for the standard CDN path; use `h3` only when client and edge support it |
| Fingerprint | `chrome` |
| XHTTP Extra/XMUX | contents of `host-overrides/xhttp-obfs-xmux.json` |
| MUX | unset |

The private path in the Node profile is fixed intentionally. Caddy maps each
node's generated public Host path to that private Unix-socket route.

After changing Host settings, update the client subscription. Confirm the
client uses Xray-core `v26.6.27` or newer and retained the XHTTP extra
parameters. Unsupported clients are outside this baseline.

For a proxied Cloudflare Host, use Full (strict) TLS and a cache rule that
bypasses cache for the exact hostname and generated XHTTP path.

## Cover Service

Caddy sends only the private XHTTP namespace to Xray. Other valid HTTPS
requests reach the bundled Element Web service. This gives unmatched probes a
normal web response; it does not make a public endpoint immune to traffic
analysis.

The certificate remains exported at:

```text
/etc/nginx/certs/fullchain.pem
/etc/nginx/certs/privkey.key
```

## Status

Run the policy check after installation, upgrades, and configuration changes:

```bash
sudo /opt/remnanode/node-status.sh
```

It exits nonzero when the reviewed image pins, minimum core version, socket,
certificates, generated profiles, or Caddy routes have drifted. A
`CUSTOM_CORE_URL` is reported explicitly and must be reviewed by the operator.

Basic logs:

```bash
docker logs remnanode --tail=100
docker logs remnawave-caddy --tail=100
```

## Legacy Profiles

`panel-profiles/legacy/` contains the old plain XHTTP and XTLS-Vision profiles.
They are retained for existing deployments and deliberate high-throughput use
in non-sensitive regions. They receive critical security and compatibility
fixes only. New features target the recommended XHTTP profile.

Fixed-pair bridge profiles were removed. A future multihop design must use a
managed topology and explicit balancing rather than embedded destination
credentials.

## Maintenance

Optional network tuning:

```bash
sudo /opt/remnanode/enable-network-tuning.sh
```

Uninstall:

```bash
sudo /opt/remnanode/uninstall-node.sh
```

Remove runtime data too:

```bash
sudo PURGE_DATA=1 /opt/remnanode/uninstall-node.sh
```

Certificate renewal is installed at
`/etc/cron.d/remnawave-caddy-cert-export`. Runtime files live under
`/opt/remnanode`.

All runtime images are pinned by version and multi-platform digest. Upgrades
must update both compose files, the status policy, and the repository
validator in one reviewed change.

## Repository Check

No container runtime is required:

```bash
bash tests/validate.sh
```

Before releasing a deployment change, follow
`docs/fresh-vps-smoke-test.md` on a disposable VPS.
