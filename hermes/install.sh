#!/usr/bin/env bash
# Installs Nous Research's Hermes Agent under $SELAN_APP_HOME, and nowhere else:
# a git checkout of one release tag, a Python venv built from its lock file, and
# uv (only if you have none) to build it. Safe to run again; it does nothing when
# the release is already in place.
#
# Upstream's own installer is not used on purpose: it adds lines to your shell rc
# files and links hermes into ~/.local/bin.
set -euo pipefail

# The release this repository has tried. Bump it by pull request.
HERMES_REF="v2026.9.24"
# The mcp extra is what lets Hermes talk to the company's connectors.
STAMP="$HERMES_REF+mcp"
HERMES_REPO="https://github.com/NousResearch/hermes-agent.git"
RAW="https://raw.githubusercontent.com/selan-ai/selan-apps/main/hermes"

APP_HOME="${SELAN_APP_HOME:-$HOME/.selan/apps/hermes}"
mkdir -p "$APP_HOME"

# Everything uv would keep goes under the app home, not ~/.cache or ~/.local.
export UV_CACHE_DIR="$APP_HOME/cache/uv"
export UV_PYTHON_INSTALL_DIR="$APP_HOME/python"
export UV_PROJECT_ENVIRONMENT="$APP_HOME/venv"
export UV_NO_CONFIG=1
export UV_PYTHON_PREFERENCE=only-managed

copy_run_script() {
  # run.sh next to the app, so it runs with a terminal attached.
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

if [ "$(cat "$APP_HOME/installed" 2>/dev/null || true)" = "$STAMP" ] && [ -x "$APP_HOME/venv/bin/hermes" ]; then
  copy_run_script
  echo "hermes $HERMES_REF is already installed in $APP_HOME"
  exit 0
fi

if command -v uv >/dev/null 2>&1; then
  UV="$(command -v uv)"
else
  UV="$APP_HOME/uv/uv"
  if [ ! -x "$UV" ]; then
    echo "installing uv into $APP_HOME/uv"
    curl -fsSL https://astral.sh/uv/install.sh \
      | env UV_UNMANAGED_INSTALL="$APP_HOME/uv" UV_NO_MODIFY_PATH=1 sh
  fi
fi

SRC="$APP_HOME/hermes-agent"
if [ -d "$SRC/.git" ]; then
  git -C "$SRC" fetch --quiet --depth 1 origin "refs/tags/$HERMES_REF:refs/tags/$HERMES_REF"
  git -C "$SRC" -c advice.detachedHead=false checkout --quiet --force "$HERMES_REF"
else
  rm -rf "$SRC"
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$HERMES_REF" "$HERMES_REPO" "$SRC"
fi

echo "building hermes $HERMES_REF"
(cd "$SRC" && "$UV" sync --frozen --extra mcp --no-progress)

copy_run_script
echo "$STAMP" >"$APP_HOME/installed"
echo "hermes $HERMES_REF installed in $APP_HOME"
