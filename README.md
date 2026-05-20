# Remnawave VLESS-XHTTP-TLS Selfsteal Node

This bundle builds a no-fallback node layout:

```text
bootstrap/renewal: Caddy :80/:443 -> Let's Encrypt -> exported cert files
normal service:    client -> Xray :443 TLS -> VLESS XHTTP
```

Xray binds public `443` and terminates TLS. Caddy is used only to issue/renew ACME certificates and export them to the certificate paths mounted into the Remnawave node container. During normal service Caddy is stopped so it does not conflict with Xray on `443`.

Important: active HTTPS selfsteal on the same `443` at the same time requires either Caddy-front TLS or Xray fallback. This profile is the requested no-fallback, TLS-at-Xray mode.

## Files

- `panel-profiles/vless-xhttp-tls-selfsteal-no-fallback.json` - import/use this as the Remnawave panel config profile.
- `setup-scripts/install-node-caddy.sh` - installs Docker, bootstraps ACME with Caddy, starts Remnawave Node, firewall rules, and a renewal cron.
- `setup-scripts/renew-caddy-certs-for-xray.sh` - stops Remnawave Node briefly, starts Caddy for certificate renewal/export, then restores Remnawave Node.
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
- Xray listen port from profile: `443`

The profile has `streamSettings.security: "tls"` because TLS terminates in Xray. Caddy only provides the certificate files.

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

Those files are exported from Caddy storage into `/opt/remnanode/certs/`, then mounted into the Remnawave node container. Xray reads these exact paths from the profile.

## Ports

- `80/tcp` - Caddy ACME bootstrap/renewal
- `443/tcp` - Xray VLESS-XHTTP-TLS during normal service; Caddy only during certificate bootstrap/renewal
- `2222/tcp` - Remnawave node control port
