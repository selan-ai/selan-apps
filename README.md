# selan-apps

Third-party agent apps that run on your company's [Selan](https://selan.ai) accounts. One folder per
app, every step plain bash you can read. `selan app <name>` in [selan-cli](https://selan.ai) runs
these same scripts; without it you run them yourself.

| App | What | Run it |
|---|---|---|
| [hermes](hermes/) | Hermes Agent by Nous Research, a terminal agent | `selan app hermes chat` |
| [paperclip](paperclip/) | Paperclip, a web app for running a company of AI agents | `selan app paperclip` |
| [openhands](openhands/) | OpenHands Agent Canvas, a web app for coding agents and their automations | `selan app openhands` |
| [openclaw](openclaw/) | OpenClaw, an assistant you chat with that uses tools on its machine | `selan app openclaw` |

`selan app list` prints the catalog, which is [`catalog.json`](catalog.json).

## By hand

You need a `selanct_` API token. An owner mints it in control under [Settings → API tokens](https://control.selan.ai/settings/access).

```sh
export SELAN_TOKEN=selanct_...
curl -fsSL https://raw.githubusercontent.com/selan-ai/selan-apps/main/hermes/install.sh | bash
~/.selan/apps/hermes/run.sh chat
```

Replace `hermes` with `paperclip`, `openhands` or `openclaw` (and drop `chat`) for the other apps.
Read the script before you run it; that is what this repository is for.

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
Removing the deploy means revoking it there. Paperclip's, OpenHands' and OpenClaw's UIs are never
put on the internet: you reach them by SSH tunnel.

## The contract

Every app has `install.sh`, `run.sh` and `README.md`, and an entry in `catalog.json`:
`{"apps":[{"name","description","homepage","needs":[commands that must be on PATH]}]}`.

| Variable | `selan app` sets | By hand, when unset |
|---|---|---|
| `SELAN_TOKEN` | the signed-in session's token, fresh for this launch | required |
| `SELAN_GATEWAY` | the channel's proxy base URL | `https://gw.selan.ai` |
| `SELAN_APP_HOME` | `~/.selan/apps/<name>` (`~/.selan-dev/apps/<name>` on dev) | `~/.selan/apps/<name>` |
| `SELAN_APP_MODEL` | not set | not set: the app's own default model |
| `SELAN_APP_PORT` | not set | not set: the app answers on `127.0.0.1` only |
| `SELAN_APP_PUBLIC_URL` | not set | not set |
| `SELAN_APP_PASSWORD` | not set | not set: an app with a sign-in makes its own password |

The scripts read the company's models, connectors and plugin marketplaces from
`$SELAN_GATEWAY/selan/settings` with the token, so both ways in get the same ones.

`SELAN_APP_MODEL` is the model the app's agents use, such as `claude-opus-5-5`: one of the
`pickerModels` in those settings. Any other id makes `run.sh` exit non-zero with one line saying
so, before the app starts. It is applied at every launch, so starting again with another id
switches the app over, agents the app already has included. Selan's Agents tab sets it from the
model a person picks. Each app's README says what it does with it.

- `install.sh` installs the app into `$SELAN_APP_HOME`, is safe to run again, and leaves a copy of
  `run.sh` there.
- `run.sh` starts the app on Selan and passes its arguments through.
- Scripts write only under `$SELAN_APP_HOME`: never your shell rc files, a global install, or the
  app's own default home. The token is not written to disk unless the app has to hold a key; that
  app's README says so in its first lines.
- The endpoint is the Anthropic Messages format at `$SELAN_GATEWAY/anthropic`.
- Claude served from a Claude subscription: Hermes gets Anthropic's "Third-party apps now draw from
  your extra usage" message (HTTP 400) instead of an answer. OpenClaw gets it too, and then stops
  only its Claude models for ten minutes or more; its other models still answer. Paperclip's Claude
  Code agents and OpenHands are answered normally.

## Behind a proxy

Selan's cloud (the Agents tab in control) runs an app's `run.sh` on a VM, with a Selan proxy in
front that lets only the company's signed-in members through. It sets `SELAN_APP_MODEL` to the
model picked there (changing it restarts the app with the new one), and up to three more variables:

- `SELAN_APP_PORT`: the app answers on `0.0.0.0` on this port, and `run.sh` opens no browser.
  Unset, nothing changes: loopback only.
- `SELAN_APP_PUBLIC_URL`: the `https://` address people open it at, such as
  `https://paperclip-7f3k.agents.selan.ai`. Only with `SELAN_APP_PORT`, and with no path: each app
  is served at the root of its own hostname.
- `SELAN_APP_PASSWORD`: the password of the app's own sign-in, so the proxy signs in for each member
  and nobody sees a second login. Only with `SELAN_APP_PORT`. Unset, an app with a sign-in makes a
  password once and keeps it in `$SELAN_APP_HOME`, as before. It is never written to disk (at most
  a hash, if the app keeps one) and never put on an argument list. Hermes uses it; Paperclip and
  OpenHands have no sign-in and ignore it, and OpenClaw ignores it too.

Selan's proxy also sends the signed-in member's email as `X-Forwarded-User`, and removes any the
browser sent. OpenClaw signs members in by it; the other apps ignore it.

**Whoever reaches that port reaches the app.** Set them only behind a proxy that authenticates,
and keep the port closed to everything else. Paperclip lets anyone through it in as its admin,
and OpenHands as its owner, with a shell; OpenClaw lets in whoever `X-Forwarded-User` names, as an
operator; Hermes asks for its dashboard password (`SELAN_APP_PASSWORD`, or the one it made). Each app's README says what it serves there.

`selan app <name> [args]` reads this repository at `main`, prints the commit, shows the scripts and
asks `[Y/n]` the first time and whenever they changed, checks `needs`, runs `install.sh`, then
`run.sh`. It does not run on Windows (use WSL).

## Adding an app

See [CLAUDE.md](CLAUDE.md). MIT licensed.
