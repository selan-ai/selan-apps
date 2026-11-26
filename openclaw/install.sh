#!/usr/bin/env bash
# Installs the openclaw npm package with a global install whose prefix is $SELAN_APP_HOME, so
# nothing is written outside it (npm only takes --allow-scripts, which openclaw needs, from a
# global install). Safe to run again; it does nothing when this version is already there.
#
# Upstream's own installer is not used on purpose: it provisions a Node of its own, installs
# openclaw globally and starts its onboarding wizard.
set -euo pipefail

# The release this repository has tried. Bump it by pull request.
OPENCLAW_VERSION="2026.11.7"
RAW="https://raw.githubusercontent.com/selan-ai/selan-apps/main/openclaw"

APP_HOME="${SELAN_APP_HOME:-$HOME/.selan/apps/openclaw}"
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

if [ -x "$APP_HOME/bin/openclaw" ] && [ "$(cat "$APP_HOME/installed" 2>/dev/null || true)" = "$OPENCLAW_VERSION" ]; then
  copy_run_script
  echo "openclaw $OPENCLAW_VERSION is already installed in $APP_HOME"
  exit 0
fi

# openclaw's engines field: Node 24.16 or later on 24.x, or 26.1 or later.
node -e '
const [major, minor] = process.versions.node.split(".").map(Number);
process.exit((major === 24 && minor >= 16) || (major === 26 && minor >= 1) || major > 26 ? 0 : 1);
' || { echo "openclaw needs Node 24.16+ (24.x) or 26.1+, this is $(node -v)" >&2; exit 1; }

# npm 11.16 and later skip a package's lifecycle scripts unless told which one may run.
allow=()
if node -e '
const [major, minor] = process.argv[1].split(".").map(Number);
process.exit(major > 11 || (major === 11 && minor >= 16) ? 0 : 1);
' "$(npm -v)"; then
  allow=(--allow-scripts=openclaw)
fi

# Everything the postinstall and the tools it starts would keep elsewhere stays here.
export XDG_DATA_HOME="$APP_HOME/xdg/data" XDG_STATE_HOME="$APP_HOME/xdg/state"
export XDG_CACHE_HOME="$APP_HOME/xdg/cache" XDG_CONFIG_HOME="$APP_HOME/xdg/config"

echo "installing openclaw $OPENCLAW_VERSION into $APP_HOME"
NPM_CONFIG_UPDATE_NOTIFIER=false npm install --global --prefix "$APP_HOME" --cache "$APP_HOME/npm-cache" \
  --no-audit --no-fund --loglevel=error ${allow[@]+"${allow[@]}"} "openclaw@$OPENCLAW_VERSION"

copy_run_script
echo "$OPENCLAW_VERSION" >"$APP_HOME/installed"
echo "openclaw $OPENCLAW_VERSION installed in $APP_HOME"
