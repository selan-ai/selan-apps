# Hermes Agent on Selan

[Hermes Agent](https://github.com/NousResearch/hermes-agent) is Nous Research's terminal agent. This
folder runs it on your company's Selan accounts: its models come from the Selan gateway, its
tools from your company's connectors, and its skills from your company's plugin marketplaces.

## Two ways in

With `selan-cli`:

```sh
selan app hermes chat
```

By hand (a `selanct_` API token; an owner mints it in control under [Settings → API tokens](https://control.selan.ai/settings/access)):

```sh
export SELAN_TOKEN=selanct_...
curl -fsSL https://raw.githubusercontent.com/selan-ai/selan-apps/main/hermes/install.sh | bash
~/.selan/apps/hermes/run.sh chat
```

Everything after `run.sh` goes to `hermes`: `run.sh chat -m gpt-6-luna -q "hello"`. Needs `curl` and
`git`; the installer fetches `uv` and Python itself if you have none.

## What lands where

Everything is under `$SELAN_APP_HOME` (default `~/.selan/apps/hermes`):

| Path | What |
|---|---|
| `hermes-agent/` | the Hermes release this repository pins (see `HERMES_REF` in `install.sh`) |
| `venv/`, `python/`, `uv/`, `cache/` | its Python environment and the tools that build it |
| `home/` | Hermes's own home (`HERMES_HOME`): `config.yaml`, sessions, memory |
| `marketplaces/` | shallow clones of your company's plugin marketplaces |
| `xdg/` | what Hermes and its tools keep in `~/.local`, `~/.cache` and `~/.config` |
| `run.sh` | a copy of this folder's `run.sh`, so it runs with a terminal attached |

Nothing is written to your shell rc files, to `~/.local/bin` or to `~/.hermes`. (Upstream's own
installer does all three; this one does not use it. Running a bare `hermes` yourself still uses
`~/.hermes`; always go through `run.sh`.)

## The token

`SELAN_TOKEN` is never written to disk. `run.sh` hands it to `hermes` in its environment (as
`ANTHROPIC_API_KEY`, with `ANTHROPIC_BASE_URL` pointing at `$SELAN_GATEWAY/anthropic`), and
`config.yaml` only names it (`${SELAN_HERMES_TOKEN}`) in the connectors' `Authorization` header.
Only connectors that sign in with the Selan session, on `selan.ai`, get it.

Hermes starts a background gateway process that keeps the environment of the launch that started
it, token included, and a later launch would reuse it. `run.sh` stops any such process before it
starts `hermes`.

## Notes

- Claude served from a Claude subscription answers with Anthropic's "Third-party apps now draw
  from your extra usage" message; it is passed on as it is.
- `config.yaml` is written again at every launch, so changes to your company's models,
  connectors and marketplaces arrive at the next one. Edit Hermes's behaviour through
  `hermes config`, not by editing that file.
