# OpenClaw on Selan

> **Your Selan token is not written to disk.** OpenClaw's config (`$SELAN_APP_HOME/home/openclaw.json`)
> names `${SELAN_OPENCLAW_TOKEN}` as the API key of its Selan model providers and never holds the
> token itself. The token is in OpenClaw's environment only, for as long as `run.sh` runs.

[OpenClaw](https://github.com/openclaw/openclaw) is an assistant you chat with that uses tools on
its machine. This folder starts it with your company's Selan models, so it runs on your company's
Selan accounts.

## Two ways in

With `selan-cli`:

```sh
selan app openclaw
```

By hand (a `selanct_` API token; an owner mints it in control under [Settings → API tokens](https://control.selan.ai/settings/access)):

```sh
export SELAN_TOKEN=selanct_...
curl -fsSL https://raw.githubusercontent.com/selan-ai/selan-apps/main/openclaw/install.sh | bash
~/.selan/apps/openclaw/run.sh
```

With no arguments `run.sh` starts OpenClaw's Gateway, which serves its web UI at
http://127.0.0.1:18789 (`OPENCLAW_GATEWAY_PORT` moves it). Sign in with the password in
`$SELAN_APP_HOME/gateway/password` (owner only), which the first launch makes. Arguments go to
`openclaw` instead: `run.sh tui` for a terminal chat. Needs `curl`, `node` 24.16 or later on 24.x
or 26.1 or later, and `npm`.

## What `run.sh` does

1. Reads your company's models from `$SELAN_GATEWAY/selan/settings`.
2. Writes them into OpenClaw's config as two model providers on the Anthropic Messages endpoint
   at `$SELAN_GATEWAY/anthropic`: `selan-claude` with the Claude models and `selan` with every
   other one. The UI's model picker shows them as "Selan Claude" and "Selan". A provider with no
   models is removed. It is written again at every launch, so a model your company adds arrives
   at the next one; the rest of the config is yours and is kept.
3. Sets the default model: `SELAN_APP_MODEL` when it is set ([the contract](../README.md#the-contract)),
   otherwise your company's first model. An id the settings do not list stops `run.sh` before
   OpenClaw starts. A chat can switch models in the picker; that changes only that chat.
4. Starts `openclaw gateway` with the token in its environment as `SELAN_OPENCLAW_TOKEN`.

Claude has a provider of its own because of how OpenClaw treats a billing error. Claude served
from a Claude subscription answers OpenClaw with Anthropic's "Third-party apps now draw from your
extra usage" (HTTP 400), and OpenClaw then disables that provider's key for ten minutes, longer
if it happens again. With one provider, one Claude chat would stop every model; with two, it
stops only Claude, and chats on the other models carry on. Pick a non-Claude model if your
company's Claude comes from a subscription.

## Behind Selan's proxy

With `SELAN_APP_PORT` set and no arguments ([the contract](../README.md#behind-a-proxy)), the
Gateway answers on `0.0.0.0:$SELAN_APP_PORT` and signs members in by the proxy's word, with
OpenClaw's trusted-proxy sign-in:

- Selan's proxy sends the signed-in member's email as `X-Forwarded-User` and removes any the
  browser sent. Every member arrives signed in as their email, with no password and no pairing
  step: every browser of theirs is approved with operator scopes (`operator.read`,
  `operator.write`, `operator.approvals`, `operator.questions`).
- Every member is an operator. OpenClaw does not rank them: anyone the proxy lets through can
  chat, run the agent's tools on the VM and approve what it asks.
- Without the header OpenClaw refuses everyone. It takes the header only from a private address
  (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `fc00::/7`) that is not the machine's own, and
  never from loopback.
- `SELAN_APP_PUBLIC_URL` becomes OpenClaw's public origin: the address in its links, and the
  browser origin it accepts.
- `SELAN_APP_PASSWORD` is ignored: OpenClaw has no password a proxy could sign in with.
  `run.sh` drops it from the environment, so OpenClaw and its tools never see it.

## What lands where

Everything is under `$SELAN_APP_HOME` (default `~/.selan/apps/openclaw`), about 1 GB after
`install.sh`:

- `bin/` and `lib/`: the `openclaw` npm package at the version `install.sh` pins.
- `home/`: OpenClaw's own state (`OPENCLAW_STATE_DIR`, instead of `~/.openclaw`): `openclaw.json`,
  its databases with your chats, its logs, and `workspace/`, where the agent works.
- `gateway/password`: the UI's password, on loopback only.
- `xdg/`: what OpenClaw and the tools it starts would keep in `~/.local`, `~/.cache` and
  `~/.config`.
- `npm-cache/`, `installed` and `run.sh`.

Nothing is installed globally, and `~/.openclaw` is not used. The agent's tools run as you, with
your home directory. On a machine with Claude Code, OpenClaw runs `claude` once at start to read
its model list, and Claude Code updates its own `~/.claude.json` as it does whenever it runs.
OpenClaw's model picker still lists only Selan's models.
