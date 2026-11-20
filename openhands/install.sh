#!/usr/bin/env bash
# Installs OpenHands under $SELAN_APP_HOME, and nowhere else: the Agent Canvas npm package (the
# web app and its launcher), uv (only if you have none), and the agent server, the automation
# backend and the Python they run on, which the launcher would otherwise fetch from PyPI at its
# first start. Safe to run again; it does nothing when this version is already there.
set -euo pipefail

# The release this repository has tried. Bump it by pull request. It pins the agent server and
# the automation backend it starts (see `agent-canvas --info`).
AGENT_CANVAS_VERSION="1.42.0"
RAW="https://raw.githubusercontent.com/selan-ai/selan-apps/main/openhands"

APP_HOME="${SELAN_APP_HOME:-$HOME/.selan/apps/openhands}"
mkdir -p "$APP_HOME"

copy_run_script() {
  # run.sh next to the app, so every launch runs the copy that was installed.
  local here=""
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
  if [ -n "$here" ] && [ -f "$here/run.sh" ]; then
    cp "$here/run.sh" "$APP_HOME/run.sh"
  else
    curl -fsSL "$RAW/run.sh" -o "$APP_HOME/run.sh"
  fi
  chmod +x "$APP_HOME/run.sh"
}

if [ -x "$APP_HOME/node_modules/.bin/agent-canvas" ] && [ "$(cat "$APP_HOME/installed" 2>/dev/null || true)" = "$AGENT_CANVAS_VERSION" ]; then
  copy_run_script
  echo "openhands $AGENT_CANVAS_VERSION is already installed in $APP_HOME"
  exit 0
fi

# agent-canvas's engines field.
node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)' \
  || { echo "openhands needs Node 24 or later, this is $(node -v)" >&2; exit 1; }

if ! command -v uv >/dev/null 2>&1 && [ ! -x "$APP_HOME/uv/uv" ]; then
  echo "installing uv into $APP_HOME/uv"
  curl -fsSL https://astral.sh/uv/install.sh \
    | env UV_UNMANAGED_INSTALL="$APP_HOME/uv" UV_NO_MODIFY_PATH=1 sh
fi

echo "installing openhands $AGENT_CANVAS_VERSION into $APP_HOME"
# A native dependency builds with node-gyp, which keeps node's headers in ~/Library or ~/.cache.
NPM_CONFIG_UPDATE_NOTIFIER=false npm_config_devdir="$APP_HOME/cache/node-gyp" npm install --prefix "$APP_HOME" --cache "$APP_HOME/npm-cache" \
  --no-audit --no-fund --loglevel=error "@openhands/agent-canvas@$AGENT_CANVAS_VERSION"

# The agent server and the automation backend, fetched now so that the first start needs no
# PyPI. They go into uv's cache under the same home, XDG and uv folders run.sh gives
# agent-canvas, which is where its uvx looks for them. Python comes from uv too, never from
# this machine, so the whole tree is here; run.sh's uv prefers the one it finds here.
export HOME="$APP_HOME/home"
mkdir -p "$HOME" "$APP_HOME/xdg"
chmod 700 "$HOME"
export XDG_DATA_HOME="$APP_HOME/xdg/data" XDG_STATE_HOME="$APP_HOME/xdg/state"
export XDG_CACHE_HOME="$APP_HOME/xdg/cache" XDG_CONFIG_HOME="$APP_HOME/xdg/config"
export UV_CACHE_DIR="$APP_HOME/xdg/cache/uv" UV_PYTHON_INSTALL_DIR="$APP_HOME/xdg/data/uv/python"
export PYTHONPYCACHEPREFIX="$APP_HOME/xdg/cache/pycache" UV_PYTHON_PREFERENCE=only-managed
[ ! -x "$APP_HOME/uv/uv" ] || export PATH="$APP_HOME/uv:$PATH"
echo "fetching the agent server and the automation backend into $UV_CACHE_DIR"
# The commands are agent-canvas's own, so its version pins and Python range are the ones used;
# each runs once, with --help.
node --input-type=module -e '
import { spawnSync } from "node:child_process";
const scripts = process.argv[1];
const { buildAgentServerCommand } = await import(scripts + "/dev-safe.mjs");
const { buildAutomationCommand } = await import(scripts + "/dev-with-automation.mjs");
for (const { command, args } of [buildAgentServerCommand(process.env), buildAutomationCommand(process.env)]) {
  console.log("  " + args[args.indexOf("--from") + 1]);
  const run = spawnSync(command, [...args, "--help"], { stdio: ["ignore", "ignore", "inherit"] });
  if (run.status !== 0) process.exit(1);
}
' "$APP_HOME/node_modules/@openhands/agent-canvas/scripts" \
  || { echo "could not fetch the agent server and the automation backend" >&2; exit 1; }

copy_run_script
echo "$AGENT_CANVAS_VERSION" >"$APP_HOME/installed"
echo "openhands $AGENT_CANVAS_VERSION installed in $APP_HOME"
