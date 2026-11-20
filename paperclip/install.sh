#!/usr/bin/env bash
# Installs the paperclipai npm package into $SELAN_APP_HOME (not -g, and not a fresh
# npx download at every start), and Claude Code beside it in $SELAN_APP_HOME/claude-code,
# which Paperclip's claude_local agents run (run.sh points them at it), as does its onboarding
# Test on a machine with no claude of its own.
# Safe to run again; it does nothing when these versions are already there.
set -euo pipefail

# The version this repository has tried. Bump it by pull request.
PAPERCLIP_VERSION="2026.1117.0"
CLAUDE_CODE_VERSION="2.1.329"
INSTALLED="paperclipai $PAPERCLIP_VERSION, claude-code $CLAUDE_CODE_VERSION"
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

if [ -x "$APP_HOME/node_modules/.bin/paperclipai" ] && [ -x "$APP_HOME/claude-code/node_modules/.bin/claude" ] \
  && [ "$(cat "$APP_HOME/installed" 2>/dev/null || true)" = "$INSTALLED" ]; then
  copy_run_script
  echo "$INSTALLED is already installed in $APP_HOME"
  exit 0
fi

# opencode-ai's postinstall makes its folders under ~/.cache, ~/.config and ~/.local
# unless XDG says otherwise; run.sh points the same variables at the same place.
export XDG_DATA_HOME="$APP_HOME/xdg/data" XDG_STATE_HOME="$APP_HOME/xdg/state"
export XDG_CACHE_HOME="$APP_HOME/xdg/cache" XDG_CONFIG_HOME="$APP_HOME/xdg/config"

echo "installing $INSTALLED into $APP_HOME"
NPM_CONFIG_UPDATE_NOTIFIER=false npm_config_devdir="$APP_HOME/cache/node-gyp" npm install --prefix "$APP_HOME" --cache "$APP_HOME/npm-cache" \
  --no-audit --no-fund --loglevel=error "paperclipai@$PAPERCLIP_VERSION"
# A prefix of its own, so run.sh can put this claude, and no other tool of Paperclip's, on PATH.
mkdir -p "$APP_HOME/claude-code"
NPM_CONFIG_UPDATE_NOTIFIER=false npm install --prefix "$APP_HOME/claude-code" --cache "$APP_HOME/npm-cache" \
  --no-audit --no-fund --loglevel=error "@anthropic-ai/claude-code@$CLAUDE_CODE_VERSION"

copy_run_script
echo "$INSTALLED" >"$APP_HOME/installed"
echo "$INSTALLED installed in $APP_HOME"
