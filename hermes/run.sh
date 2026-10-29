#!/usr/bin/env bash
# shellcheck disable=SC2016 # the single-quoted programs for python and node are meant to stay unexpanded
# Starts Hermes Agent on your company's Selan accounts. Arguments go to hermes:
#   run.sh chat            run.sh chat -m claude-sonnet-5-5 -q "hello"
#
# Needs SELAN_TOKEN. Asks the gateway for the company's models, connectors and plugin
# marketplaces, writes Hermes's config.yaml from them (references to the token, never
# the token), and starts hermes with the token in its environment only.
set -euo pipefail

: "${SELAN_TOKEN:?SELAN_TOKEN is not set: export a selanct_ CLI token from control.selan.ai > Settings}"
SELAN_GATEWAY="${SELAN_GATEWAY:-https://gw.selan.ai}"
SELAN_GATEWAY="${SELAN_GATEWAY%/}"
APP_HOME="${SELAN_APP_HOME:-$HOME/.selan/apps/hermes}"

PYTHON="$APP_HOME/venv/bin/python"
HERMES="$APP_HOME/venv/bin/hermes"
[ -x "$HERMES" ] || { echo "hermes is not installed in $APP_HOME: run install.sh first" >&2; exit 1; }

# Hermes's whole state lives here, not in ~/.hermes.
export HERMES_HOME="$APP_HOME/home"
mkdir -p "$HERMES_HOME" "$APP_HOME/marketplaces" "$APP_HOME/xdg"

# What hermes and the tools it starts would otherwise keep under ~/.local, ~/.cache and ~/Library.
export XDG_DATA_HOME="$APP_HOME/xdg/data" XDG_STATE_HOME="$APP_HOME/xdg/state"
export XDG_CACHE_HOME="$APP_HOME/xdg/cache" XDG_CONFIG_HOME="$APP_HOME/xdg/config" PIP_CACHE_DIR="$APP_HOME/xdg/cache/pip"
export PYTHONPYCACHEPREFIX="$APP_HOME/xdg/cache/pycache"

# A Hermes gateway daemon that an earlier launch left running keeps that launch's
# environment, token included, and a new launch would talk to it. Stop it first.
"$HERMES" gateway stop >/dev/null 2>&1 || true

# The token goes to curl on stdin, so it is not in a process listing.
settings="$(printf 'header = "Authorization: Bearer %s"\n' "$SELAN_TOKEN" \
  | curl -fsS --max-time 15 -K - "$SELAN_GATEWAY/selan/settings")" \
  || { echo "could not read company settings from $SELAN_GATEWAY/selan/settings" >&2; exit 1; }

# Plugin marketplaces the company switched on for the CLI: a shallow clone each.
while IFS=$'\t' read -r name url; do
  [ -n "$name" ] || continue
  dir="$APP_HOME/marketplaces/$name"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch --quiet --depth 1 origin HEAD && git -C "$dir" reset --quiet --hard FETCH_HEAD \
      || echo "warning: could not update $name; using the copy already here" >&2
  else
    git clone --quiet --depth 1 -- "$url" "$dir" || echo "warning: could not fetch $name from $url" >&2
  fi
done < <(printf '%s' "$settings" | "$PYTHON" -I -c '
import json, re, sys
for m in json.load(sys.stdin).get("pluginMarketplaces", []):
    if "cli" in m.get("apps", []) and not m["url"].lower().endswith(".json") and re.fullmatch(r"[A-Za-z0-9._-]+", m["name"]):
        print(m["name"], m["url"], sep="\t")
')

# config.yaml holds ${SELAN_HERMES_TOKEN}, which Hermes fills in from the environment.
printf '%s' "$settings" | "$PYTHON" -I -c '
import json, os, sys
settings = json.load(sys.stdin)
gateway, home, markets = sys.argv[1:4]
servers = {}
for c in settings.get("connectors", []):
    host = c["url"].split("/")[2].split(":")[0] if c["url"].startswith("https://") else ""
    # Only connectors that take the Selan session, and only on selan.ai: the token goes nowhere else.
    if c.get("auth") == "session" and c.get("transport") == "http" and (host == "selan.ai" or host.endswith(".selan.ai")):
        servers[c["slug"]] = {"url": c["url"], "headers": {"Authorization": "Bearer ${SELAN_HERMES_TOKEN}"}}
dirs = []
for m in settings.get("pluginMarketplaces", []):
    root = os.path.join(markets, m["name"])
    try:
        plugins = json.load(open(os.path.join(root, ".claude-plugin", "marketplace.json")))["plugins"]
    except (OSError, ValueError, KeyError):
        continue
    for p in plugins:
        if isinstance(p.get("source"), str):
            path = os.path.normpath(os.path.join(root, p["source"]))
            if (path == root or path.startswith(root + os.sep)) and os.path.isdir(path) and "cli" in m.get("apps", []):
                dirs.append(path)
config = {"model": {"provider": "anthropic", "base_url": gateway + "/anthropic"}}
models = settings.get("pickerModels", [])
if models:
    config["model"]["default"] = models[0]["id"]
if servers:
    config["mcp_servers"] = servers
if dirs:
    config["skills"] = {"external_dirs": dirs}
# JSON is YAML.
with open(os.path.join(home, "config.yaml"), "w") as f:
    json.dump(config, f, indent=2)
' "$SELAN_GATEWAY" "$HERMES_HOME" "$APP_HOME/marketplaces"

export ANTHROPIC_BASE_URL="$SELAN_GATEWAY/anthropic"
export ANTHROPIC_API_KEY="$SELAN_TOKEN"
export SELAN_HERMES_TOKEN="$SELAN_TOKEN"
exec "$HERMES" "$@"
