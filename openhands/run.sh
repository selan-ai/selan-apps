#!/usr/bin/env bash
# shellcheck disable=SC2016 # the single-quoted node programs are meant to stay unexpanded
# Starts OpenHands (Agent Canvas, its web UI, and the agent server behind it) on your company's
# Selan accounts. Arguments go to agent-canvas:
#   run.sh            run.sh --port 3000
# It answers on 127.0.0.1:8000, or, with SELAN_APP_PORT set, on 0.0.0.0:$SELAN_APP_PORT for
# Selan's proxy.
#
# Needs SELAN_TOKEN. Once the agent server is up it asks the gateway for the company's models and
# gives OpenHands one LLM setting: the Anthropic Messages endpoint at $SELAN_GATEWAY/anthropic
# with the token as its key. OpenHands keeps that key itself (see the README); the token is on no
# argument list. SELAN_APP_MODEL, if set, is the model instead of the company's first.
set -euo pipefail

: "${SELAN_TOKEN:?SELAN_TOKEN is not set: export a selanct_ API token, minted by an owner at control.selan.ai > Settings > API tokens}"
SELAN_GATEWAY="${SELAN_GATEWAY:-https://gw.selan.ai}"
SELAN_GATEWAY="${SELAN_GATEWAY%/}"
APP_HOME="${SELAN_APP_HOME:-$HOME/.selan/apps/openhands}"

# Serving behind Selan's proxy. Whoever reaches SELAN_APP_PORT is signed in to OpenHands as its
# owner, with a shell on this machine, so it is set only behind a proxy that signs people in.
SELAN_APP_PORT="${SELAN_APP_PORT:-}"
SELAN_APP_PUBLIC_URL="${SELAN_APP_PUBLIC_URL:-}"
SELAN_APP_PUBLIC_URL="${SELAN_APP_PUBLIC_URL%/}"
# OpenHands has no password a proxy could sign in with, and its agents need not see one.
unset SELAN_APP_PASSWORD
if [ -n "$SELAN_APP_PORT" ]; then
  { [[ "$SELAN_APP_PORT" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$SELAN_APP_PORT" -le 65535 ]; } \
    || { echo "SELAN_APP_PORT is not a port number: $SELAN_APP_PORT" >&2; exit 1; }
elif [ -n "$SELAN_APP_PUBLIC_URL" ]; then
  echo "SELAN_APP_PUBLIC_URL is set without SELAN_APP_PORT" >&2
  exit 1
fi
if [ -n "$SELAN_APP_PUBLIC_URL" ]; then
  [[ "$SELAN_APP_PUBLIC_URL" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] \
    || { echo "SELAN_APP_PUBLIC_URL must be https://<host>, with no path: $SELAN_APP_PUBLIC_URL" >&2; exit 1; }
fi

AGENT_CANVAS="$APP_HOME/node_modules/.bin/agent-canvas"
[ -x "$AGENT_CANVAS" ] || { echo "openhands is not installed in $APP_HOME: run install.sh first" >&2; exit 1; }

# OpenHands keeps its state in ~/.openhands and the agent's shell starts in ~, so the home it
# sees is one of its own: nothing lands in yours.
export HOME="$APP_HOME/home"
mkdir -p "$HOME" "$APP_HOME/xdg"
chmod 700 "$HOME"
export XDG_DATA_HOME="$APP_HOME/xdg/data" XDG_STATE_HOME="$APP_HOME/xdg/state"
export XDG_CACHE_HOME="$APP_HOME/xdg/cache" XDG_CONFIG_HOME="$APP_HOME/xdg/config"
export UV_CACHE_DIR="$APP_HOME/xdg/cache/uv" UV_PYTHON_INSTALL_DIR="$APP_HOME/xdg/data/uv/python"
export PYTHONPYCACHEPREFIX="$APP_HOME/xdg/cache/pycache" npm_config_cache="$APP_HOME/npm-cache"
# uv from the install, when there was none on PATH.
[ ! -x "$APP_HOME/uv/uv" ] || export PATH="$APP_HOME/uv:$PATH"
command -v uvx >/dev/null 2>&1 || { echo "uv is not installed: run install.sh first" >&2; exit 1; }
# agent-canvas starts the agent server and the automation backend with uvx, which asks PyPI again
# once its cache is a few minutes old, and fails when PyPI does not answer. install.sh fetched both
# and the Python they run on, so they start offline: agent-canvas finds this uvx first, and it runs
# uv's own with --offline. It takes itself off PATH before that, so the servers and their agents
# never see it, and an agent's own uv still reaches PyPI. UV_OFFLINE would reach them all.
mkdir -p "$APP_HOME/uvx-offline"
cat >"$APP_HOME/uvx-offline/uvx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
path=":$PATH:"
path="${path//:$(dirname "$0"):/:}"
path="${path#:}"
export PATH="${path%:}"
exec uvx --offline "$@"
EOF
chmod +x "$APP_HOME/uvx-offline/uvx"
export PATH="$APP_HOME/uvx-offline:$PATH"

# The token goes to curl on stdin, so it is not in a process listing.
settings="$(printf 'header = "Authorization: Bearer %s"\n' "$SELAN_TOKEN" \
  | curl -fsS --max-time 15 -K - "$SELAN_GATEWAY/selan/settings")" \
  || { echo "could not read company settings from $SELAN_GATEWAY/selan/settings" >&2; exit 1; }

# The model the host picked (Selan's Agents tab), checked against the company's picker models
# before anything starts. Unset, OpenHands gets the first of them.
SELAN_APP_MODEL="${SELAN_APP_MODEL:-}"
MODEL="$(SELAN_SETTINGS="$settings" node -e '
const ids = (JSON.parse(process.env.SELAN_SETTINGS).pickerModels || []).map((m) => m.id);
const wanted = process.argv[1];
if (wanted && !ids.includes(wanted)) process.exit(1);
process.stdout.write(wanted || ids[0] || "");
' "$SELAN_APP_MODEL")" \
  || { echo "SELAN_APP_MODEL $SELAN_APP_MODEL is not one of the company's models in its Selan settings" >&2; exit 1; }
[ -n "$MODEL" ] || { echo "the company has no models in its Selan settings" >&2; exit 1; }

# Agent Canvas and the agent server share one key; fixing it here is what lets this script call
# the server's API. Kept in backend-key (owner only), so a restart does not sign anyone out.
if [ ! -s "$APP_HOME/backend-key" ]; then
  (umask 077 && node -e 'process.stdout.write(require("crypto").randomBytes(32).toString("base64url") + "\n")' >"$APP_HOME/backend-key")
fi
LOCAL_BACKEND_API_KEY="$(cat "$APP_HOME/backend-key")"
export LOCAL_BACKEND_API_KEY

args=("$@")
if [ -n "$SELAN_APP_PORT" ]; then
  # On any address but loopback Agent Canvas does not put its key in the page, so every visitor
  # would be asked for it. Behind the proxy the proxy is the sign-in, so it does, and the proxy's
  # members are signed in as soon as they arrive.
  # SELAN_APP_PUBLIC_URL is checked above and used for nothing: the UI's links are relative, and
  # the automation backend gives its agents http://localhost:$SELAN_APP_PORT to call back on,
  # since the public address lets in only the members the proxy signed in.
  args+=(--host 0.0.0.0 --port "$SELAN_APP_PORT" --allow-lan-session-key)
  PORT="$SELAN_APP_PORT"
else
  PORT=8000
  for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[$i]}" in
      -p | --port) PORT="${args[$((i + 1))]:-8000}" ;;
      --port=*) PORT="${args[$i]#--port=}" ;;
    esac
  done
fi
API="http://127.0.0.1:$PORT/api"

# Gives OpenHands its one LLM setting: the LLM profile "default", saved and made the active one.
# The UI starts conversations from the default agent profile, which points at that LLM profile;
# OpenHands copies its settings into the LLM profile once and never again, so writing only the
# settings would leave the UI on the first launch's model and token. Activating it copies it into
# the settings too, for the API and automations. Whatever else the profile holds is kept. The key
# and the session key reach node through its environment, so neither is on an argument list.
apply_llm_settings() {
  SELAN_MODEL="$MODEL" node -e '
const [api, gateway] = process.argv.slice(1);
const call = async (method, path, body) => {
  const res = await fetch(api + path, {
    method, body: body && JSON.stringify(body), signal: AbortSignal.timeout(30000),
    headers: { "Content-Type": "application/json", "X-Session-API-Key": process.env.LOCAL_BACKEND_API_KEY },
  });
  if (res.status === 404 && method === "GET") return null;
  if (!res.ok) throw new Error(`${method} ${path}: HTTP ${res.status}`);
  return res.json();
};
const saved = await call("GET", "/profiles/default");
const llm = { ...saved?.config, model: "anthropic/" + process.env.SELAN_MODEL, base_url: gateway + "/anthropic", api_key: process.env.SELAN_TOKEN };
await call("POST", "/profiles/default", { llm, include_secrets: true });
await call("POST", "/profiles/default/activate");
' "$API" "$SELAN_GATEWAY"
}

# Job control gives agent-canvas a process group of its own, so the group can be stopped at once.
# The agent server, the automation backend and the rest it starts each get a group of their own,
# and agent-canvas stops them all when it gets SIGTERM.
set -m
server_pid=""
guard_pid=""
stop() {
  [ -z "$guard_pid" ] || kill "$guard_pid" 2>/dev/null || true
  if [ -n "$server_pid" ]; then
    kill -TERM -- "-$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}
trap stop EXIT
trap 'exit 130' INT TERM

"$AGENT_CANVAS" ${args[@]+"${args[@]}"} </dev/null &
server_pid=$!
# SIGKILL runs no trap, so a guard outside this shell stops the group once this script's pid is
# gone, with a SIGKILL after 10 seconds if it has not finished.
(
  while kill -0 "$$" 2>/dev/null; do sleep 1; done
  kill -TERM -- "-$server_pid" 2>/dev/null || exit 0
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$server_pid" 2>/dev/null || exit 0; sleep 1; done
  kill -KILL -- "-$server_pid" 2>/dev/null || true
) </dev/null >/dev/null 2>&1 &
guard_pid=$!

# uv sets up the agent server and the automation backend from what install.sh fetched, which
# takes a while the first time.
for _ in $(seq 1 600); do
  curl -fsS --max-time 3 "http://127.0.0.1:$PORT/alive" >/dev/null 2>&1 && break
  kill -0 "$server_pid" 2>/dev/null || { echo "OpenHands stopped before it was ready" >&2; exit 1; }
  sleep 1
done
apply_llm_settings || { echo "could not give OpenHands the Selan LLM setting" >&2; exit 1; }
echo "OpenHands runs on $MODEL"
wait "$server_pid"
