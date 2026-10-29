---
name: deploy-hostinger
description: Use when someone wants an app from the Selan apps catalog (Hermes, Paperclip) running on a Hostinger VPS they already have, as a systemd service, with the Hostinger MCP server or API to find the VPS and SSH to set it up.
allowed-tools: Bash Read WebFetch mcp__hostinger__authenticate mcp__hostinger__complete_authentication
---

# Run a Selan app on a Hostinger VPS

The VPS runs the catalog's own `install.sh` and `run.sh` (github.com/selan-ai/selan-apps), nothing
rewritten. This skill buys nothing: it uses a VPS the person already has. The Hostinger lookup
below was written from Hostinger's documentation and has not been run against a real account.

1. **Find the VPS.** With the Hostinger MCP server connected (authenticate it if it asks), list
   the virtual machines and show the person each one's id, hostname, plan, state and IP. Without
   the MCP server, the same from the API: `GET https://developers.hostinger.com/api/vps/v1/virtual-machines`
   with `Authorization: Bearer <API token from hPanel>`; the person types the token into the
   environment (`HOSTINGER_API_TOKEN`) themselves. Ask which VPS and the app (`catalog.json`).
   It needs Debian or Ubuntu with at least 1 GB of memory and root SSH; if the VPS is stopped,
   start it (`POST /api/vps/v1/virtual-machines/{id}/start`) and wait. Do not reinstall or recreate it.
2. **Show before running.** Print the commit
   (`git ls-remote https://github.com/selan-ai/selan-apps main`) and the full `<app>/install.sh` and
   `<app>/run.sh`; wait for a yes. The VPS runs exactly that commit, `SHA`.
3. **The token.** Claude never sees it. Tell the person to create a CLI token in control under
   Settings, CLI tokens, named `hostinger-<hostname>` (so it can be revoked). Create the file empty
   first (`ssh root@HOST 'install -m 600 /dev/null /etc/selan-APP.env'`), then give the person one
   line to run in their own terminal, which reads the token without echo and writes it straight
   into that root-owned 0600 file:
   ```sh
   read -rs T && printf 'SELAN_TOKEN=%s\n' "$T" | ssh root@HOST 'cat > /etc/selan-APP.env'; unset T
   ```
   Wait until they say it is done, check it is `root:root 0600` and not empty (`stat`, `wc -c`;
   never `cat`), then carry on. Only root and systemd read it.
4. **Prepare, over `ssh root@HOST`** (as on Google Cloud, step 4):
   ```sh
   apt-get update && apt-get install -y curl git ca-certificates
   useradd --create-home --shell /bin/bash selan
   git clone https://github.com/selan-ai/selan-apps /opt/selan-apps && git -C /opt/selan-apps checkout SHA
   ```
   Paperclip also needs:
   ```sh
   curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && apt-get install -y nodejs
   npm install -g @anthropic-ai/claude-code
   ```
5. **Install:** `sudo -u selan -H /opt/selan-apps/APP/install.sh`.
6. **The service**, `/etc/systemd/system/selan-APP.service`:
   ```ini
   [Unit]
   Description=Selan APP
   After=network-online.target
   Wants=network-online.target

   [Service]
   User=selan
   EnvironmentFile=/etc/selan-APP.env
   ExecStart=/home/selan/.selan/apps/APP/run.sh ARGS
   Restart=on-failure
   RestartSec=10

   [Install]
   WantedBy=multi-user.target
   ```
   `ARGS` is `gateway run` for Hermes, empty for Paperclip. systemd reads `EnvironmentFile` as root
   before it drops to `selan`. Then `systemctl daemon-reload && systemctl enable --now selan-APP`,
   and `systemctl status` / `journalctl -u selan-APP -n 50`.
7. **Finish.**
   - **Hermes** needs a chat platform and an allowed user, which only the person can give: in
     `/home/selan/.selan/apps/hermes/home/.env` (owner `selan`, 0600), e.g. `TELEGRAM_BOT_TOKEN=` and
     `TELEGRAM_ALLOWED_USERS=`, then `systemctl restart selan-hermes`. Never
     `GATEWAY_ALLOW_ALL_USERS`. Ask for the values.
   - **Paperclip** runs in trusted local mode on the VPS's loopback with no login (its sync loop talks
     to the API without one), so it is never exposed. Reach it by SSH tunnel:
     `ssh -N -L 3100:127.0.0.1:3100 root@HOST` (leave it running), then http://127.0.0.1:3100. Do not open port 3100 in
     Hostinger's firewall.
   - If Hostinger's firewall for the VPS is on, leave it on; nothing here needs a new port.
8. **Remove it.** `systemctl disable --now selan-APP`, delete the unit, `/etc/selan-APP.env`,
   `/home/selan` and `/opt/selan-apps` (and `userdel selan`); tell the person to revoke the
   token in control under Settings, CLI tokens. Deleting the VPS itself is the person's decision, in hPanel.
