# Paperclip on Selan

> **Your Selan token is stored by Paperclip.** Paperclip keeps AI connections in its own database
> (`$SELAN_APP_HOME/data`, sealed with Paperclip's own key file), so `run.sh` saves `SELAN_TOKEN`
> there as the API key of a connection called "Selan". It goes nowhere else on disk. Every launch
> replaces the key with the current one; revoke the token in control.selan.ai and the connection
> stops working.

[Paperclip](https://github.com/paperclipai/paperclip) is a web app for running a company of AI
agents. This folder starts it with an AI connection to the Selan gateway, so its Claude Code
agents run on your company's Selan accounts, with no Claude login.

## Two ways in

With `selan-cli`:

```sh
selan app paperclip
```

By hand (a `selanct_` API token; an owner mints it in control under [Settings → API tokens](https://control.selan.ai/settings/access)):

```sh
export SELAN_TOKEN=selanct_...
curl -fsSL https://raw.githubusercontent.com/selan-ai/selan-apps/main/paperclip/install.sh | bash
~/.selan/apps/paperclip/run.sh
```

The UI opens at http://127.0.0.1:3100 (`PAPERCLIP_PORT` changes the port, for the server and the sync). Needs `curl`, `node`
and `npm`, and Claude Code (`claude`) on your PATH for the agents. Arguments after `run.sh` go to
`paperclipai run`. Stop it with Ctrl-C; if `run.sh` is killed any other way, even with `kill -9`, the server and its database stop within a few seconds.

## What `run.sh` does

1. Starts Paperclip (the first time with its own setup, local and loopback only).
2. In every company, creates the "Selan" connection (Anthropic Messages at
   `$SELAN_GATEWAY/anthropic`, shared with all agents, your company's models), or, if it exists,
   updates its key. Never a second one.
3. Binds every `claude_local` agent that has no AI connection to it. A company or agent you add
   while it runs is picked up within 15 seconds; an agent you point at another connection is left
   alone. Paperclip's own LLM calls use the same connections.

## What lands where

Everything is under `$SELAN_APP_HOME` (default `~/.selan/apps/paperclip`): `node_modules/` (the
`paperclipai` version pinned in `install.sh`), `data/` (Paperclip's database, keys and files),
`npm-cache/`, `xdg/`, and `run.sh`. Nothing is installed globally. Claude Code itself keeps its
sessions in its own `~/.claude`, as it always does.

Claude served from a Claude subscription works here: the agents are Claude Code itself, which
Anthropic does not treat as a third-party app (Hermes, by contrast, gets Anthropic's "extra usage" refusal).

## Other agent types

- `codex_local` works when its command is a wrapper that runs `selan codex "$@"`.
- `opencode_local` needs workarounds with the OpenCode versions Paperclip finds; not set up here.
- `claude_local` with its command set to `selan claude` stays in "verifying"; leave the command alone.
