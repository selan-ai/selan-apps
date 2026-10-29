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

You need a `selanct_` CLI token (control.selan.ai, Settings).

```sh
export SELAN_TOKEN=selanct_...
curl -fsSL https://raw.githubusercontent.com/selan-ai/selan-apps/main/hermes/install.sh | bash
~/.selan/apps/hermes/run.sh chat
```

Replace `hermes` with `paperclip` (and drop `chat`) for the other app. Read the script before you
run it; that is what this repository is for.

## The contract

Every app has `install.sh`, `run.sh` and `README.md`, and an entry in `catalog.json`:
`{"apps":[{"name","description","homepage","needs":[commands that must be on PATH]}]}`.

| Variable | `selan app` sets | By hand, when unset |
|---|---|---|
| `SELAN_TOKEN` | the signed-in session's token, fresh for this launch | required |
| `SELAN_GATEWAY` | the channel's proxy base URL | `https://gw.selan.ai` |
| `SELAN_CONTROL` | the channel's control base URL | prod control |
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
- Claude served from a Claude subscription answers with Anthropic's "Third-party apps now draw from
  your extra usage" message; it is passed on.

`selan app <name> [args]` reads this repository at `main`, prints the commit, shows the scripts and
asks `[Y/n]` the first time and whenever they changed, checks `needs`, runs `install.sh`, then
`run.sh`. It does not run on Windows (use WSL).

## Adding an app

See [CLAUDE.md](CLAUDE.md). MIT licensed.
