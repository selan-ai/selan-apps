#!/usr/bin/env bash
# shellcheck disable=SC2016 # the single-quoted programs for python and node are meant to stay unexpanded
# Starts Hermes Agent on your company's Selan accounts. Arguments go to hermes:
#   run.sh chat            run.sh chat -m claude-sonnet-5-5 -q "hello"
# With SELAN_APP_PORT set and no arguments, it serves Hermes's web dashboard on
# 0.0.0.0:$SELAN_APP_PORT instead, for Selan's proxy, with SELAN_APP_PASSWORD (if set)
# as its password.
#
# Needs SELAN_TOKEN. Asks the gateway for the company's models, connectors and plugin
# marketplaces, writes Hermes's config.yaml from them (references to the token, never
# the token), and starts hermes with the token in its environment only. SELAN_APP_MODEL,
# if set, is the default model instead of the company's first.
set -euo pipefail

: "${SELAN_TOKEN:?SELAN_TOKEN is not set: export a selanct_ API token, minted by an owner at control.selan.ai > Settings > API tokens}"
SELAN_GATEWAY="${SELAN_GATEWAY:-https://gw.selan.ai}"
SELAN_GATEWAY="${SELAN_GATEWAY%/}"
APP_HOME="${SELAN_APP_HOME:-$HOME/.selan/apps/hermes}"

# Serving behind Selan's proxy: whoever reaches SELAN_APP_PORT reaches the dashboard's
# sign-in, so it is set only behind a proxy that signs people in.
SELAN_APP_PORT="${SELAN_APP_PORT:-}"
SELAN_APP_PUBLIC_URL="${SELAN_APP_PUBLIC_URL:-}"
SELAN_APP_PUBLIC_URL="${SELAN_APP_PUBLIC_URL%/}"
# The dashboard password, from the host, so the proxy can sign in for its members. It stays
# in this script's memory and Hermes's environment, never in a file or an argument list.
APP_PASSWORD="${SELAN_APP_PASSWORD:-}"
unset SELAN_APP_PASSWORD
if [ -n "$SELAN_APP_PORT" ]; then
  { [[ "$SELAN_APP_PORT" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$SELAN_APP_PORT" -le 65535 ]; } \
    || { echo "SELAN_APP_PORT is not a port number: $SELAN_APP_PORT" >&2; exit 1; }
elif [ -n "$SELAN_APP_PUBLIC_URL" ]; then
  echo "SELAN_APP_PUBLIC_URL is set without SELAN_APP_PORT" >&2
  exit 1
elif [ -n "$APP_PASSWORD" ]; then
  echo "SELAN_APP_PASSWORD is set without SELAN_APP_PORT" >&2
  exit 1
fi
# Hermes trims the password it is given, so one with spaces at either end would never match.
[[ ! "$APP_PASSWORD" =~ ^[[:space:]]|[[:space:]]$ ]] \
  || { echo "SELAN_APP_PASSWORD must not start or end with whitespace" >&2; exit 1; }
if [ -n "$SELAN_APP_PUBLIC_URL" ]; then
  [[ "$SELAN_APP_PUBLIC_URL" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] \
    || { echo "SELAN_APP_PUBLIC_URL must be https://<host>, with no path: $SELAN_APP_PUBLIC_URL" >&2; exit 1; }
fi

PYTHON="$APP_HOME/venv/bin/python"
HERMES="$APP_HOME/venv/bin/hermes"
[ -x "$HERMES" ] || { echo "hermes is not installed in $APP_HOME: run install.sh first" >&2; exit 1; }

# Hermes's whole state lives here, not in ~/.hermes.
export HERMES_HOME="$APP_HOME/home"
mkdir -p "$HERMES_HOME" "$APP_HOME/marketplaces" "$APP_HOME/xdg"

# What hermes and the tools it starts would otherwise keep under ~/.local, ~/.cache and ~/Library.
export XDG_DATA_HOME="$APP_HOME/xdg/data" XDG_STATE_HOME="$APP_HOME/xdg/state"
export XDG_CACHE_HOME="$APP_HOME/xdg/cache" XDG_CONFIG_HOME="$APP_HOME/xdg/config" PIP_CACHE_DIR="$APP_HOME/xdg/cache/pip"
export PYTHONPYCACHEPREFIX="$APP_HOME/xdg/cache/pycache" npm_config_cache="$APP_HOME/xdg/cache/npm"

# A Hermes gateway daemon that an earlier launch left running keeps that launch's
# environment, token included, and a new launch would talk to it. Stop it first.
"$HERMES" gateway stop >/dev/null 2>&1 || true

# The token goes to curl on stdin, so it is not in a process listing.
settings="$(printf 'header = "Authorization: Bearer %s"\n' "$SELAN_TOKEN" \
  | curl -fsS --max-time 15 -K - "$SELAN_GATEWAY/selan/settings")" \
  || { echo "could not read company settings from $SELAN_GATEWAY/selan/settings" >&2; exit 1; }

# The model the host picked (Selan's Agents tab), checked against the company's picker models
# before anything starts. Unset, Hermes defaults to the first of them.
SELAN_APP_MODEL="${SELAN_APP_MODEL:-}"
if [ -n "$SELAN_APP_MODEL" ]; then
  printf '%s' "$settings" | "$PYTHON" -I -c '
import json, sys
sys.exit(0 if sys.argv[1] in [m.get("id") for m in json.load(sys.stdin).get("pickerModels", [])] else 1)
' "$SELAN_APP_MODEL" \
    || { echo "SELAN_APP_MODEL $SELAN_APP_MODEL is not one of the company's models in its Selan settings" >&2; exit 1; }
fi

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
gateway, home, markets, model = sys.argv[1:5]
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
if model or models:
    config["model"]["default"] = model or models[0]["id"]
if servers:
    config["mcp_servers"] = servers
if dirs:
    config["skills"] = {"external_dirs": dirs}
# JSON is YAML.
with open(os.path.join(home, "config.yaml"), "w") as f:
    json.dump(config, f, indent=2)
' "$SELAN_GATEWAY" "$HERMES_HOME" "$APP_HOME/marketplaces" "$SELAN_APP_MODEL"

export ANTHROPIC_BASE_URL="$SELAN_GATEWAY/anthropic"
export ANTHROPIC_API_KEY="$SELAN_TOKEN"
export SELAN_HERMES_TOKEN="$SELAN_TOKEN"

if [ -n "$SELAN_APP_PORT" ] && [ "$#" -eq 0 ]; then
  # Hermes refuses an unauthenticated dashboard on any address but loopback (--insecure no
  # longer skips that), and it has no way to trust a proxy's sign-in. So it gets its own
  # password provider: user "selan", SELAN_APP_PASSWORD or else a password made once here
  # and kept in dashboard/password, and a signing key in dashboard/secret so sign-ins
  # outlive a restart. Hermes hashes the password in memory and never writes it.
  command -v npm >/dev/null 2>&1 || { echo "the dashboard builds its web UI with npm: install node and npm" >&2; exit 1; }
  DASHBOARD="$APP_HOME/dashboard"
  mkdir -p "$DASHBOARD"
  chmod 700 "$DASHBOARD"
  if [ -n "$APP_PASSWORD" ]; then
    # A password made by an earlier launch no longer signs in; do not leave it lying here.
    rm -f "$DASHBOARD/password"
    files=(secret)
  else
    files=(password secret)
  fi
  for file in "${files[@]}"; do
    [ -s "$DASHBOARD/$file" ] \
      || (umask 077 && "$PYTHON" -I -c 'import secrets; print(secrets.token_urlsafe(24))' >"$DASHBOARD/$file")
  done
  export HERMES_DASHBOARD_BASIC_AUTH_USERNAME=selan
  HERMES_DASHBOARD_BASIC_AUTH_PASSWORD="${APP_PASSWORD:-$(cat "$DASHBOARD/password")}"
  HERMES_DASHBOARD_BASIC_AUTH_SECRET="$(cat "$DASHBOARD/secret")"
  export HERMES_DASHBOARD_BASIC_AUTH_PASSWORD HERMES_DASHBOARD_BASIC_AUTH_SECRET
  [ -z "$SELAN_APP_PUBLIC_URL" ] || export HERMES_DASHBOARD_PUBLIC_URL="$SELAN_APP_PUBLIC_URL"
  # The OpenAI-compatible API server (8642) stays on loopback whatever the config says.
  export API_SERVER_HOST=127.0.0.1
  if [ -n "$APP_PASSWORD" ]; then
    echo "Hermes dashboard on 0.0.0.0:$SELAN_APP_PORT: sign in as selan with SELAN_APP_PASSWORD"
  else
    echo "Hermes dashboard on 0.0.0.0:$SELAN_APP_PORT: sign in as selan with the password in $DASHBOARD/password"
  fi
  exec "$HERMES" dashboard --host 0.0.0.0 --port "$SELAN_APP_PORT" --no-open
fi
exec "$HERMES" "$@"
