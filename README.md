# Remnawave VLESS-XHTTP-TLS Selfsteal Node

This bundle builds a no-fallback node layout:

```text
client -> Caddy :443 TLS/ACME -> /api/v1/data -> Xray XHTTP on 127.0.0.1:10001
                              -> all other paths -> static selfsteal website
```

Xray does not bind public `443` in this design. Caddy owns `80/443`, performs ACME, and reverse proxies only the XHTTP path to Xray.

## Files

- `panel-profiles/vless-xhttp-tls-selfsteal-no-fallback.json` - import/use this as the Remnawave panel config profile.
- `setup-scripts/install-node-caddy.sh` - installs Docker, Caddy, Remnawave Node, firewall rules, and a cert export cron.
- `docker/docker-compose.yml` - node stack used by the installer.
- `docker/docker.yaml` - same node stack under the filename you asked for.
- `caddy/Caddyfile.template` - Caddy ACME + selfsteal reverse proxy template.
- `setup-scripts/export-caddy-certs.sh` - exports Caddy's ACME cert to the old mounted paths.

## Remnawave Panel Settings

Use the profile JSON and make the public/client settings match:

- Protocol: `vless`
- Transport: `xhttp`
- Security: `tls`
- Public host/SNI: your node domain
- Public port: `443`
- Path: `/api/v1/data`
- Xray listen address from profile: `127.0.0.1`
- Xray listen port from profile: `10001`

The profile has `security: none` inside Xray because TLS terminates at Caddy. The client still sees and uses TLS on port `443`.

## Install On A Node

Copy this directory to the node, then run:

```bash
sudo bash setup-scripts/install-node-caddy.sh
```

The script writes the runtime stack to `/opt/remnanode`.

## Certificate Paths

The Remnawave node container still receives:

```text
/etc/nginx/certs/fullchain.pem
/etc/nginx/certs/privkey.key
```

Those files are exported from Caddy storage into `/opt/remnanode/certs/` for compatibility with existing panel assumptions. The no-fallback XHTTP profile does not require Xray to read them.

## Ports

- `80/tcp` - Caddy HTTP-01 / redirect handling
- `443/tcp` - Caddy HTTPS and XHTTP public endpoint
- `2222/tcp` - Remnawave node control port
- `10001/tcp` - local Xray XHTTP inbound; bound to `127.0.0.1` by the profile
