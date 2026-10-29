# selan-apps

Public catalog of third-party agent apps that run on a company's Selan accounts. `selan app <name>`
(in selan-cli) and a person with a terminal run the same scripts. Read `README.md` for the contract.

## Adding an app

1. A folder `<name>/` with `install.sh`, `run.sh` and `README.md`.
2. An entry in `catalog.json`: `name`, `description`, `homepage` (https), `needs` (commands that must
   be on PATH before install).
3. `.github/check-catalog.sh` and shellcheck must pass; run both before pushing.

## Rules for every script

- `#!/usr/bin/env bash`, `set -euo pipefail`, shellcheck-clean, readable top to bottom, macOS and Linux.
- Inputs are `SELAN_TOKEN`, `SELAN_GATEWAY`, `SELAN_CONTROL`, `SELAN_APP_HOME`. Never invent another.
- Write only under `$SELAN_APP_HOME`: no shell rc files, no global installs, not the app's default home.
- The token never lands on disk, except where the app must hold a key; that README says so in its first lines.
- The endpoint is the Anthropic Messages format at `$SELAN_GATEWAY/anthropic`. `/v1/chat/completions` is not forwarded.
- `install.sh` is idempotent, exits 0 when done, and leaves a copy of `run.sh` in `$SELAN_APP_HOME`.
- Pin the app's version in `install.sh`; bump it by pull request after trying it.
- Prove a change by running both scripts in a throwaway `HOME` against the real gateway.

`main` takes changes by pull request only. Commits carry no AI attribution.
