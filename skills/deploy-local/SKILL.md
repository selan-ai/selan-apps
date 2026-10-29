---
name: deploy-local
description: Use when someone wants to run an app from the Selan apps catalog (Hermes, Paperclip) on this machine, once or kept running as a service. Runs the catalog's own install.sh and run.sh; with the selan CLI that is `selan app <name>`.
allowed-tools: Bash Read Write WebFetch mcp__selan__selan_cli_token_create mcp__selan__selan_cli_token_revoke
---

# Run a Selan app on this machine

The apps are the folders of `catalog.json` in github.com/selan-ai/selan-apps. Each one is run by
its own `install.sh` and `run.sh`. This skill never repeats their steps; it only runs them.

1. **Pick the app.** Read `https://raw.githubusercontent.com/selan-ai/selan-apps/main/catalog.json`
   and ask which one, if the person did not say. Check its `needs` are on PATH.
2. **Show before running.** Print the commit (`git ls-remote https://github.com/selan-ai/selan-apps main`)
   and the full `<app>/install.sh` and `<app>/run.sh`, and wait for a yes. Say what they write: only
   under `~/.selan/apps/<app>`.
3. **Run it once.**
   - With `selan` installed (`command -v selan`, and `selan app list` works): `selan app <app> [args]`.
     It shows the scripts and asks for itself, and uses the person's signed-in session.
   - Without: the README's lines. A `selanct_` token from control.selan.ai, Settings, then
     ```sh
     export SELAN_TOKEN=selanct_...
     curl -fsSL https://raw.githubusercontent.com/selan-ai/selan-apps/main/<app>/install.sh | bash
     ~/.selan/apps/<app>/run.sh <args>
     ```
     Run the copy `install.sh` leaves; piping `run.sh` would leave Hermes without a terminal.
   - Hermes: `chat` for a terminal chat. Paperclip: no arguments; its UI is http://127.0.0.1:3100.
4. **Always on, only if the person asks.** A service has no signed-in session, so it needs a
   long-lived token.
   - Create one named `<app>-<hostname>` with `selan_cli_token_create` (ttl `90d` unless told
     otherwise). If refused, say that an owner mints one in control's Settings, CLI tokens, and stop.
   - Put it in `~/.selan/apps/<app>/service.env` as `SELAN_TOKEN=selanct_...`. Create the file empty
     first with mode 0600 (`install -m 600 /dev/null FILE`), then write the line with the Write tool,
     so the token is never in a command line or a log, nor mode 0644 for a moment.
   - The service starts a wrapper, `~/.selan/apps/<app>/service.sh`, because launchd has no
     environment file:
     ```sh
     #!/usr/bin/env bash
     set -euo pipefail
     APP=<app>
     set -a; . "$HOME/.selan/apps/$APP/service.env"; set +a
     exec "$HOME/.selan/apps/$APP/run.sh" "$@"
     ```
     with arguments `gateway run` for Hermes and none for Paperclip (`chmod +x`).
   - **macOS:** `~/Library/LaunchAgents/ai.selan.apps.<app>.plist` with `ProgramArguments` the
     wrapper (and its arguments), `RunAtLoad` and `KeepAlive` true, `StandardOutPath` and
     `StandardErrorPath` `~/.selan/apps/<app>/service.log`. Then
     `launchctl bootstrap gui/$(id -u) <plist>`.
   - **Linux:** `~/.config/systemd/user/selan-<app>.service` with `ExecStart=` the wrapper,
     `Restart=on-failure`, `WantedBy=default.target`. Then `systemctl --user daemon-reload`,
     `systemctl --user enable --now selan-<app>`, and `loginctl enable-linger $USER` so it
     survives logout.
   - Check it: `launchctl print gui/$(id -u)/ai.selan.apps.<app>` or `systemctl --user status`, and the
     log. Hermes needs a chat platform in `~/.selan/apps/hermes/home/.env` to do anything as a
     gateway (see deploy-google-cloud, Hermes). Paperclip answers on http://127.0.0.1:3100.
5. **Remove it.** `launchctl bootout gui/$(id -u)/ai.selan.apps.<app>` and delete the plist, or
   `systemctl --user disable --now selan-<app>` and delete the unit; delete
   `~/.selan/apps/<app>` (Paperclip's database is in it); revoke the token with
   `selan_cli_token_revoke`, using the id `selan_cli_token_create` answered.
