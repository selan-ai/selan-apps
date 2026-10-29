# selan-apps

Third-party agent apps that run on your company's [Selan](https://selan.ai) accounts. One folder per
app, every step plain bash you can read. `selan app <name>` in [selan-cli](https://selan.ai) runs
these same scripts; without it you run them yourself.

| App | What | Run it |
|---|---|---|
| [hermes](hermes/) | Hermes Agent by Nous Research, a terminal agent | `selan app hermes chat` |
| [paperclip](paperclip/) | Paperclip, a web app for running a company of AI agents | `selan app paperclip` |

`selan app list` prints the catalog, which is [`catalog.json`](catalog.json).

## By hand

You need a `selanct_` API token. An owner mints it in control under [Settings → API tokens](https://control.selan.ai/settings/access).

```sh
export SELAN_TOKEN=selanct_...
curl -fsSL https://raw.githubusercontent.com/selan-ai/selan-apps/main/hermes/install.sh | bash
~/.selan/apps/hermes/run.sh chat
```

Replace `hermes` with `paperclip` (and drop `chat`) for the other app. Read the script before you
run it; that is what this repository is for.

## Install anywhere

This repository is also a Claude Code plugin. Add it and ask Claude to deploy an app:

```
/plugin marketplace add selan-ai/selan-apps
/plugin install selan-apps@selan-apps
```

| Skill | Where it runs the app |
|---|---|
| `deploy-local` | this machine; with `selan app <name>`, or by hand, and as a launchd or systemd user service if you want it always on |
| `deploy-google-cloud` | a Compute Engine VM in your project, a systemd service, reached over SSH through IAP with no open firewall port |
| `deploy-hostinger` | a Hostinger VPS you already have, a systemd service, over SSH |

Each runs the same `install.sh` and `run.sh` as above and shows you the commit and the scripts
first. A server cannot use your session, so a remote deploy uses a long-lived API token named
after the server. An owner creates it in control under Settings → API tokens, and you paste it into one command
in your own terminal that sends it to Secret Manager or a root-only file; Claude never sees it.
Removing the deploy means revoking it there. Paperclip's UI is never put on the internet: you
reach it by SSH tunnel.

## The contract

Every app has `install.sh`, `run.sh` and `README.md`, and an entry in `catalog.json`:
`{"apps":[{"name","description","homepage","needs":[commands that must be on PATH]}]}`.

| Variable | `selan app` sets | By hand, when unset |
|---|---|---|
| `SELAN_TOKEN` | the signed-in session's token, fresh for this launch | required |
| `SELAN_GATEWAY` | the channel's proxy base URL | `https://gw.selan.ai` |
| `SELAN_APP_HOME` | `~/.selan/apps/<name>` (`~/.selan-dev/apps/<name>` on dev) | `~/.selan/apps/<name>` |

The scripts read the company's models, connectors and plugin marketplaces from
`$SELAN_GATEWAY/selan/settings` with the token, so both ways in get the same ones.

- `install.sh` installs the app into `$SELAN_APP_HOME`, is safe to run again, and leaves a copy of
  `run.sh` there.
- `run.sh` starts the app on Selan and passes its arguments through.
- Scripts write only under `$SELAN_APP_HOME`: never your shell rc files, a global install, or the
  app's own default home. The token is not written to disk unless the app has to hold a key; that
  app's README says so in its first lines.
- The endpoint is the Anthropic Messages format at `$SELAN_GATEWAY/anthropic`.
- Claude served from a Claude subscription: Hermes gets Anthropic's "Third-party apps now draw from
  your extra usage" message (HTTP 400) instead of an answer. Paperclip's Claude Code agents are
  answered normally.

`selan app <name> [args]` reads this repository at `main`, prints the commit, shows the scripts and
asks `[Y/n]` the first time and whenever they changed, checks `needs`, runs `install.sh`, then
`run.sh`. It does not run on Windows (use WSL).

## Adding an app

See [CLAUDE.md](CLAUDE.md). MIT licensed.
