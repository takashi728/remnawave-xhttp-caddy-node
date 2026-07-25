# Fresh VPS Smoke Test

Use a disposable Ubuntu/Debian or Arch Linux VPS with a test domain.

1. Run the documented installer and complete any requested kernel reboot.
   Record the values printed by the installer:

   ```bash
   export DOMAIN='node.example.com'
   export XHTTP_PATH='/api/replace-with-generated-path'
   ```

2. Enable XHTTP socket mode:

   ```bash
   sudo /opt/remnanode/enable-xhttp-socket-caddy.sh
   ```

3. Confirm all reviewed services are running:

   ```bash
   docker compose -f /opt/remnanode/docker-compose.yml ps
   ```

4. Confirm ACME and the unchanged certificate exports:

   ```bash
   sudo test -s /opt/remnanode/certs/fullchain.pem
   sudo test -s /opt/remnanode/certs/privkey.key
   docker exec remnanode test -s /etc/nginx/certs/fullchain.pem
   docker exec remnanode test -s /etc/nginx/certs/privkey.key
   ```

5. Confirm an ordinary request reaches the cover service and the private path
   does not return the same page:

   ```bash
   curl --fail --silent --show-error "https://$DOMAIN/" >/dev/null
   curl --http2 --include "https://$DOMAIN$XHTTP_PATH"
   ```

6. Apply the canonical Node profile and Host override in Remnawave. Refresh a
   test subscription and verify direct traffic. For CDN deployment, enable the
   proxy and exact-host/path cache-bypass rule, refresh again, and verify
   traffic.

7. Run the policy check:

   ```bash
   sudo /opt/remnanode/node-status.sh
   ```

   It must end with `Policy check passed.`

8. Verify unsupported-core detection without changing the running core:

   ```bash
   sudo cp /opt/remnanode/node-status.sh /tmp/remnanode-old-core-check.sh
   sudo sed -i 's/MIN_XRAY_VERSION="26.6.27"/MIN_XRAY_VERSION="99.0.0"/' /tmp/remnanode-old-core-check.sh
   if sudo /tmp/remnanode-old-core-check.sh; then
     echo "ERROR: unsupported-core policy did not fail" >&2
     exit 1
   fi
   ```

9. Remove the temporary checker:

   ```bash
   sudo rm -f /tmp/remnanode-old-core-check.sh
   ```
