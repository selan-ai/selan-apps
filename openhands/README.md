# OpenHands on Selan

> **Your Selan token is stored by OpenHands.** OpenHands keeps the API key of its LLM setting in its
> own files under `$SELAN_APP_HOME/home/.openhands` (its settings, its `default` LLM profile, and
> each conversation's state), encrypted with the key file it keeps there. Every launch replaces it
> in the settings and the profile with the current token (a conversation keeps the one it started
> with); revoke the token in control and it stops working.

[OpenHands](https://github.com/OpenHands/OpenHands) Agent Canvas is a web app for coding agents and
their automations. This folder starts it with one LLM setting on the Selan gateway, so its agents
run on your company's Selan accounts, on any of its models.

## Two ways in

With `selan-cli`:

```sh
selan app openhands
```

By hand (a `selanct_` API token; an owner mints it in control under [Settings → API tokens](https://control.selan.ai/settings/access)):

```sh
export SELAN_TOKEN=selanct_...
curl -fsSL https://raw.githubusercontent.com/selan-ai/selan-apps/main/openhands/install.sh | bash
~/.selan/apps/openhands/run.sh
```

The UI opens at http://127.0.0.1:8000 (`run.sh --port 3000` moves it). Needs `curl`, `node` 24 or
later and `npm`; `install.sh` fetches `uv` if you have none, and the agent server, the automation
backend and the Python they run on, so the first start needs no PyPI. Arguments after `run.sh` go
to `agent-canvas`. Stop it with Ctrl-C; if `run.sh` is killed any other way, even with `kill -9`,
everything it started stops within a few seconds.

## What `run.sh` does

1. Reads your company's models from `$SELAN_GATEWAY/selan/settings`. With `SELAN_APP_MODEL` set
   ([the contract](../README.md#the-contract)) that is the model, and an id the settings do not list
   stops `run.sh` before OpenHands starts; unset, it is the first one. Claude or not, every model
   goes through the same Anthropic Messages endpoint.
2. Starts Agent Canvas: its web UI, the agent server and the automation backend. Its session key
   is kept in `$SELAN_APP_HOME/backend-key` (owner only), so a restart signs nobody out. The agent
   server and the automation backend start offline, from what `install.sh` fetched: Agent Canvas
   runs them with `uvx`, and the first `uvx` on its PATH is `$SELAN_APP_HOME/uvx-offline/uvx`,
   which adds `--offline`. So a start never waits on PyPI, however old uv's cache is. That `uvx`
   takes itself off PATH before it runs uv's own, so the agents' own uv still reaches PyPI.
3. Once the agent server answers, gives OpenHands one LLM setting: the LLM profile `default`, with
   `$SELAN_GATEWAY/anthropic` as its endpoint, the token as its key and `anthropic/<model>` as its
   model. It is saved and made the active profile at every launch, which also puts it in
   OpenHands' settings. The default agent profile, which the UI starts conversations with, points
   at it, so a restart with another `SELAN_APP_MODEL` starts new conversations on that model. A
   conversation keeps the model it started with. Anything else you set in that profile is kept,
   and an agent profile you point at another LLM profile is left alone.

## Usage data

OpenHands' "Send anonymous usage data" (Settings > Application) starts off, and nobody is asked:
on its own, OpenHands asks each new browser with the box already ticked, and its page reports the
install to OpenHands before anyone answers. Once the agent server answers, `run.sh` turns the
setting off while nobody has set it. Until it is on, Agent Canvas serves its page with telemetry
switched off (`AGENT_CANVAS_DISABLE_TELEMETRY`), the install report included. Turn it on there
and OpenHands sends usage data from the next start; `run.sh` never turns it back off.

## Behind Selan's proxy

With `SELAN_APP_PORT` set ([the contract](../README.md#behind-a-proxy)), Agent Canvas answers on
`0.0.0.0:$SELAN_APP_PORT` with `--allow-lan-session-key`: the page carries the session key as it
does on loopback, so the proxy's members are signed in as soon as they arrive, with no key prompt.
The proxy's sign-in is the only one. Every member it lets through is OpenHands' owner, with a shell
on the VM through its agents and terminal, and OpenHands does not tell them apart.

- Agent Canvas's own frontend server listens on `0.0.0.0` as well, on port 3001, and serves the
  same app with the same key. Keep it closed to everything but the VM itself, as `SELAN_APP_PORT`
  is to everything but the proxy.
- `SELAN_APP_PUBLIC_URL` is checked and not used. The UI's links are relative, and the automation
  backend gives its agents `http://localhost:$SELAN_APP_PORT` to call back on, since the public
  address lets in only the members the proxy signed in.
- `SELAN_APP_PASSWORD` is ignored: there is no OpenHands sign-in for it to open. `run.sh` drops it
  from the environment, so OpenHands and its agents never see it.

## What lands where

Everything is under `$SELAN_APP_HOME` (default `~/.selan/apps/openhands`), about 3.2 GB after
`install.sh`:

- `node_modules/`: the `@openhands/agent-canvas` version pinned in `install.sh`, which pins the
  agent server and the automation backend.
- `xdg/`: uv's cache with the agent server and the automation backend, the Python they run on
  (`xdg/data/uv/python`), and their bytecode.
- `uv/`: uv itself, only if your PATH had none.
- `home/`: the home OpenHands sees. Its `.openhands` holds its settings, profiles, conversations,
  automations and keys, and the agents' workspaces; its terminal starts here.
- `uvx-offline/`: the `uvx` above, written by `run.sh` at every launch.
- `npm-cache/`, `cache/` (node-gyp's headers), `backend-key`, `installed` and `run.sh`.

Nothing is installed globally. The agent server keeps its terminal's tmux sockets in the system's
temporary directory, and removes them when it stops.

The browser tool uses a Chrome or Chromium that is already there: in `/usr/bin` (`google-chrome`,
`chromium` and the like), on PATH, or in Playwright's cache (`$PLAYWRIGHT_BROWSERS_PATH`, or
`~/.cache/ms-playwright` in the home OpenHands sees). `install.sh` adds none. With none, OpenHands
starts the agent without its browser tools, and every other tool works.

## Claude

Claude served from a Claude subscription answered OpenHands normally on every run tried, at the
version `install.sh` pins. Hermes, by contrast, gets Anthropic's "extra usage" refusal.
