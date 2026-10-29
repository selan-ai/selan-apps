---
name: deploy-google-cloud
description: Use when someone wants an app from the Selan apps catalog (Hermes, Paperclip) running on a Compute Engine VM in their own Google Cloud project, as a systemd service, reached over SSH through IAP with no open firewall port.
allowed-tools: Bash Read WebFetch
---

# Run a Selan app on a Google Cloud VM

The VM runs the catalog's own `install.sh` and `run.sh` (github.com/selan-ai/selan-apps), nothing
rewritten. Needs `gcloud` signed in with rights to create VMs, service accounts and secrets.

**Ask first:** the app (`catalog.json`), the project, the zone, and the machine type (default
`e2-small`, Debian 12). `APP` below is the app's name, `VM` is `selan-<app>`, `PROJECT` and
`ZONE` the answers.

1. **Show before running.** Print the commit
   (`git ls-remote https://github.com/selan-ai/selan-apps main`) and the full `<app>/install.sh` and
   `<app>/run.sh`; wait for a yes. The VM runs exactly that commit, `SHA` below.
2. **The token.** A server cannot use a person's session; it needs a long-lived API token, and
   Claude never sees it. Tell the person an owner mints one in control under Settings → API tokens (https://control.selan.ai/settings/access), named
   `VM` (so it can be revoked). Then create the secret empty and the service account, and give the
   person one line to run in their own terminal, which reads the token without echo and sends it
   straight to Secret Manager:
   ```sh
   gcloud services enable compute.googleapis.com secretmanager.googleapis.com iap.googleapis.com --project PROJECT
   gcloud secrets create VM --replication-policy=automatic --project PROJECT
   gcloud iam service-accounts create VM --project PROJECT
   gcloud secrets add-iam-policy-binding VM --project PROJECT \
     --member=serviceAccount:VM@PROJECT.iam.gserviceaccount.com --role=roles/secretmanager.secretAccessor
   ```
   (A new service account can take a few seconds to be known; repeat the binding if it says the account does not exist.)
   The person runs, pasting the token at the silent prompt:
   ```sh
   read -rs T && printf %s "$T" | gcloud secrets versions add VM --project PROJECT --data-file=-; unset T
   ```
   Wait until they say it is done (check `gcloud secrets versions list VM --project PROJECT`
   shows a version), then carry on. The service account can read this one secret and nothing else.
3. **Network: SSH only through IAP.** Tag the VM `selan-apps`; allow IAP's range and refuse every
   other source for port 22 on that tag. No app port is ever opened.
   ```sh
   gcloud compute firewall-rules create selan-apps-allow-iap-ssh --project PROJECT --network default \
     --direction INGRESS --priority 800 --allow tcp:22 --source-ranges 35.235.240.0/20 --target-tags selan-apps
   gcloud compute firewall-rules create selan-apps-deny-ssh --project PROJECT --network default \
     --direction INGRESS --priority 900 --action DENY --rules tcp:22 --source-ranges 0.0.0.0/0 --target-tags selan-apps
   gcloud compute instances create VM --project PROJECT --zone ZONE --machine-type e2-small \
     --image-family debian-12 --image-project debian-cloud --boot-disk-size 20GB \
     --tags selan-apps --service-account VM@PROJECT.iam.gserviceaccount.com --scopes cloud-platform
   ```
   (Skip a rule that exists.) The VM keeps an external address only so it can reach GitHub, npm and
   the gateway; nothing is allowed in. Every command below goes through
   `gcloud compute ssh VM --project PROJECT --zone ZONE --tunnel-through-iap --command '...'`;
   wait until it answers.
4. **Prepare, as root.**
   ```sh
   apt-get update && apt-get install -y curl git ca-certificates
   useradd --create-home --shell /bin/bash selan
   git clone https://github.com/selan-ai/selan-apps /opt/selan-apps && git -C /opt/selan-apps checkout SHA
   ```
   Paperclip also needs Node 24 and Claude Code for its agents:
   ```sh
   curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && apt-get install -y nodejs
   npm install -g @anthropic-ai/claude-code
   ```
5. **Install, as the `selan` user:** `sudo -u selan -H /opt/selan-apps/APP/install.sh`. It installs
   under `/home/selan/.selan/apps/APP` and leaves `run.sh` there. It needs no token.
6. **The service.** The unit reads the token from Secret Manager each time it starts, so it is
   never on the disk. `/usr/local/bin/selan-APP` (mode 0755):
   ```sh
   #!/usr/bin/env bash
   set -euo pipefail
   SELAN_TOKEN="$(gcloud secrets versions access latest --secret=VM --project=PROJECT)"
   export SELAN_TOKEN
   exec /home/selan/.selan/apps/APP/run.sh "$@"
   ```
   and `/etc/systemd/system/selan-APP.service`:
   ```ini
   [Unit]
   Description=Selan APP
   After=network-online.target
   Wants=network-online.target

   [Service]
   User=selan
   ExecStart=/usr/local/bin/selan-APP ARGS
   Restart=on-failure
   RestartSec=10

   [Install]
   WantedBy=multi-user.target
   ```
   `ARGS` is `gateway run` for Hermes and empty for Paperclip. Then
   `systemctl daemon-reload && systemctl enable --now selan-APP`.
   Check `systemctl status selan-APP` and `journalctl -u selan-APP -n 50`.
7. **Reach it and finish.**
   - **Hermes** runs as its chat gateway. It does nothing until it has a chat platform and an
     allowed user, which only the person can give: put them in `/home/selan/.selan/apps/hermes/home/.env`
     (owner `selan`, mode 0600), e.g. `TELEGRAM_BOT_TOKEN=` from @BotFather and
     `TELEGRAM_ALLOWED_USERS=` their numeric id (Slack, Discord and others have their own pairs;
     Hermes's `.env.example` lists them), then `systemctl restart selan-hermes`. Do not set
     `GATEWAY_ALLOW_ALL_USERS`. Ask the person for these; do not make them up.
   - **Paperclip** is started by its own setup in trusted local mode, bound to the VM's loopback,
     with no login, and its sync loop (which gives every Claude Code agent the Selan connection)
     talks to that API unauthenticated. It is never exposed. Reach it from the person's machine
     with a tunnel, which is the only way in and is gated by their Google login:
     `gcloud compute ssh VM --project PROJECT --zone ZONE --tunnel-through-iap -- -N -L 3100:127.0.0.1:3100`
     and open http://127.0.0.1:3100. Leave that command running while the UI is in use. (Paperclip has an authenticated mode for a public address; the
     sync loop does not log in, so this skill does not use it.)
8. **Remove it.** Delete everything, then the token:
   ```sh
   gcloud compute instances delete VM --project PROJECT --zone ZONE --delete-disks=all --quiet
   gcloud secrets delete VM --project PROJECT --quiet
   gcloud iam service-accounts delete VM@PROJECT.iam.gserviceaccount.com --project PROJECT --quiet
   gcloud compute firewall-rules delete selan-apps-allow-iap-ssh selan-apps-deny-ssh --project PROJECT --quiet
   ```
   (Keep the two rules if another selan-apps VM uses them.) Tell the person to revoke the token in
   control under Settings → API tokens, then show `gcloud compute instances list --project PROJECT`.
