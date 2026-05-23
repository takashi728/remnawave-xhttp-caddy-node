# Remnawave VLESS-XHTTP-TLS Selfsteal Node

This bundle builds a no-fallback node layout:

```text
bootstrap/renewal: Caddy :80/:443 -> Let's Encrypt -> exported cert files
normal service:    client -> Xray :443 TLS -> VLESS XHTTP
```

Xray binds public `443` and terminates TLS. Caddy is used only to issue/renew ACME certificates and export them to the certificate paths mounted into the Remnawave node container. During normal service Caddy is stopped so it does not conflict with Xray on `443`.

Important: active HTTPS selfsteal on the same `443` at the same time requires either Caddy-front TLS or Xray fallback. This profile is the requested no-fallback, TLS-at-Xray mode.

## Files

- `panel-profiles/vless-xhttp-tls-selfsteal-no-fallback.json` - VLESS XHTTP TLS profile.
- `panel-profiles/vless-xtls-vision-tls-selfsteal-no-fallback.json` - VLESS Vision TLS profile.
- `panel-profiles/vless-xtls-vision-tls-selfsteal-fallback.json` - VLESS Vision TLS profile with fallback to local Caddy.
- `setup-scripts/install-node-caddy.sh` - installs Docker, bootstraps ACME with Caddy, starts Remnawave Node, firewall rules, and a renewal cron.
- `setup-scripts/renew-caddy-certs-for-xray.sh` - stops Remnawave Node briefly, starts Caddy for certificate renewal/export, then restores Remnawave Node.
- `setup-scripts/enable-vision-fallback-caddy.sh` - switches Caddy to local fallback website mode on `127.0.0.1:9443`.
- `docker/docker-compose.yml` - node stack used by the installer.
- `docker/docker.yaml` - same node stack under the filename you asked for.
- `caddy/Caddyfile.template` - Caddy ACME + selfsteal reverse proxy template.
- `setup-scripts/export-caddy-certs.sh` - exports Caddy's ACME cert to the old mounted paths.

The Caddy image is pinned to `caddy:2.11.3`.

The optional Vision fallback mode serves Element Web through Caddy instead of a static placeholder page. Element Web is a Matrix web client, not a homeserver: this node does not expose local account registration, a chat database, or Matrix media storage. It is bound to `127.0.0.1:8088`, not exposed publicly except through Xray fallback.

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

For the Vision profile, use:

- Protocol: `vless`
- Transport: `tcp` / `raw`
- Security: `tls`
- Flow: `xtls-rprx-vision`
- Public host/SNI: your node domain
- Public port: `443`

For the Vision fallback profile, run this after the installer:

```bash
sudo /opt/remnanode/enable-vision-fallback-caddy.sh
```

Then use `panel-profiles/vless-xtls-vision-tls-selfsteal-fallback.json`. Xray still owns public `443`; Caddy only listens locally with HTTP on `127.0.0.1:9443`, and Xray sends non-VLESS traffic to it after terminating public TLS.

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
