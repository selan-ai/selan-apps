#!/usr/bin/env bash
# Installs the paperclipai npm package into $SELAN_APP_HOME (not -g, and not a fresh
# npx download at every start). Safe to run again; it does nothing when this
# version is already there.
set -euo pipefail

# The version this repository has tried. Bump it by pull request.
PAPERCLIP_VERSION="2026.1023.0"
RAW="https://raw.githubusercontent.com/selan-ai/selan-apps/main/paperclip"

APP_HOME="${SELAN_APP_HOME:-$HOME/.selan/apps/paperclip}"
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

if [ -x "$APP_HOME/node_modules/.bin/paperclipai" ] \
  && [ "$(cat "$APP_HOME/installed" 2>/dev/null || true)" = "$PAPERCLIP_VERSION" ]; then
  copy_run_script
  echo "paperclipai $PAPERCLIP_VERSION is already installed in $APP_HOME"
  exit 0
fi

echo "installing paperclipai $PAPERCLIP_VERSION into $APP_HOME"
NPM_CONFIG_UPDATE_NOTIFIER=false npm_config_devdir="$APP_HOME/cache/node-gyp" npm install --prefix "$APP_HOME" --cache "$APP_HOME/npm-cache" \
  --no-audit --no-fund --loglevel=error "paperclipai@$PAPERCLIP_VERSION"

copy_run_script
echo "$PAPERCLIP_VERSION" >"$APP_HOME/installed"
echo "paperclipai $PAPERCLIP_VERSION installed in $APP_HOME"
