#!/usr/bin/env bash
# Starts Paperclip and gives it a "Selan" AI connection, so its agents run on your
# company's Selan accounts. Arguments go to `paperclipai run`.
#
# Paperclip keeps AI connections in its own database, so SELAN_TOKEN is stored there
# (sealed with Paperclip's own key file) as the connection's API key. This script
# creates that connection in every company Paperclip has, updates its key at each launch
# (never a second connection), binds every claude_local agent that has no AI connection
# to it, and does the same for companies and agents added while it runs.
set -euo pipefail

: "${SELAN_TOKEN:?SELAN_TOKEN is not set: export a selanct_ API token, minted by an owner at control.selan.ai > Settings > API tokens}"
SELAN_GATEWAY="${SELAN_GATEWAY:-https://gw.selan.ai}"
SELAN_GATEWAY="${SELAN_GATEWAY%/}"
APP_HOME="${SELAN_APP_HOME:-$HOME/.selan/apps/paperclip}"
PORT="${PAPERCLIP_PORT:-3100}"
API="http://127.0.0.1:$PORT/api"

PAPERCLIP="$APP_HOME/node_modules/.bin/paperclipai"
[ -x "$PAPERCLIP" ] || { echo "paperclip is not installed in $APP_HOME: run install.sh first" >&2; exit 1; }

# Everything Paperclip, npm and the tools they start would keep elsewhere stays here.
mkdir -p "$APP_HOME/data" "$APP_HOME/xdg"
export XDG_DATA_HOME="$APP_HOME/xdg/data" XDG_STATE_HOME="$APP_HOME/xdg/state"
export XDG_CACHE_HOME="$APP_HOME/xdg/cache" XDG_CONFIG_HOME="$APP_HOME/xdg/config"
export PYTHONPYCACHEPREFIX="$APP_HOME/xdg/cache/pycache" npm_config_devdir="$APP_HOME/xdg/cache/node-gyp"
export npm_config_cache="$APP_HOME/npm-cache" BROWSER=none

# The token goes to curl on stdin, so it is not in a process listing.
settings="$(printf 'header = "Authorization: Bearer %s"\n' "$SELAN_TOKEN" \
  | curl -fsS --max-time 15 -K - "$SELAN_GATEWAY/selan/settings")" \
  || { echo "could not read company settings from $SELAN_GATEWAY/selan/settings" >&2; exit 1; }

# Paperclip's local REST API: one pass over every company, then (with "watch") again every
# 15 seconds. SELAN_TOKEN is written into the connection on the first pass only. The loop
# ends when run.sh or the server it started is gone (a SIGKILL of run.sh runs no trap).
SYNC_PROGRAM='
const [api, gateway, mode, ...pids] = process.argv.slice(1);
const alive = (pid) => { try { process.kill(Number(pid), 0); return true; } catch (e) { return e.code === "EPERM"; } };
const settings = JSON.parse(process.env.SELAN_SETTINGS);
const NAME = "Selan";

async function call(method, path, body) {
  const res = await fetch(api + path, {
    method,
    headers: { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!res.ok) throw new Error(method + " " + path + " answered " + res.status + ": " + (await res.text()).slice(0, 300));
  return res.json();
}

const connectionBody = (existingId) => ({
  provider: "anthropic", method: "api_key", name: NAME, ownership: "shared",
  apiKey: process.env.SELAN_TOKEN, agentIds: [], allAgents: true,
  routing: {
    kind: "gateway", protocol: "messages", auth: "api_key", baseUrl: gateway + "/anthropic",
    models: (settings.pickerModels || []).map((m) => ({ id: m.id, label: m.displayName })),
  },
  ...(existingId ? { connectionId: existingId } : {}),
});

const findConnections = async (company) =>
  ((await call("GET", "/companies/" + company + "/ai-connections")).connections || []).filter((c) => c.name === NAME && c.status !== "revoked");

// Keeps the first "Selan" connection and archives the rest (Paperclip has no other way to
// remove one; an archived connection stays listed with status "revoked", which is skipped). Their ids are returned so agents bound to them can be moved.
async function dropDuplicates(company, found) {
  const dropped = new Set();
  for (const extra of found.slice(1)) {
    await call("DELETE", "/tool-connections/" + extra.id);
    dropped.add(extra.id);
    console.log("removed a duplicate " + NAME + " connection in company " + company);
  }
  return dropped;
}

async function syncCompany(company, writeKey) {
  const found = await findConnections(company);
  const dropped = await dropDuplicates(company, found);
  let connection = found[0];
  if (!connection || writeKey) {
    await call("POST", "/companies/" + company + "/ai-connections", connectionBody(connection && connection.id));
    console.log((connection ? "updated" : "created") + " the " + NAME + " connection in company " + company);
    connection = (await findConnections(company))[0];
  }
  const binding = { provider: "anthropic", method: "api_key", mode: "shared", connectionId: connection.id, grantId: connection.grantId };
  for (const agent of await call("GET", "/companies/" + company + "/agents")) {
    const runtime = agent.runtimeConfig || {};
    const bound = runtime.aiConnection && runtime.aiConnection.connectionId;
    if (agent.adapterType !== "claude_local" || (runtime.aiConnection && !dropped.has(bound))) continue;
    await call("PATCH", "/agents/" + agent.id, { runtimeConfig: { ...runtime, aiConnection: binding } });
    console.log("bound agent " + agent.name + " to the " + NAME + " connection");
  }
}

async function pass(writeKey) {
  for (const company of await call("GET", "/companies")) {
    try { await syncCompany(company.id, writeKey); }
    catch (e) { console.error("warning: company " + company.id + ": " + e.message); }
  }
}

(async () => {
  await pass(true);
  while (mode === "watch") {
    await new Promise((r) => setTimeout(r, 15000));
    if (!pids.every(alive)) break;
    try { await pass(false); } catch (e) { console.error("warning: " + e.message); }
  }
})();
'
server_pid=""
watcher_pid=""
stop() {
  [ -z "$watcher_pid" ] || kill "$watcher_pid" 2>/dev/null || true
  [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
}
trap stop EXIT
trap 'exit 130' INT TERM

if curl -fsS --max-time 3 "$API/health" >/dev/null 2>&1; then
  echo "Paperclip already answers on port $PORT; using it"
else
  if [ -f "$APP_HOME/data/instances/default/config.json" ]; then
    PORT="$PORT" "$PAPERCLIP" run --data-dir "$APP_HOME/data" "$@" </dev/null &
  else
    # First launch: Paperclip's own setup with its defaults (local, loopback only, no
    # service installed), which goes on to start the server.
    PORT="$PORT" "$PAPERCLIP" onboard --yes --no-install-service --data-dir "$APP_HOME/data" </dev/null &
  fi
  server_pid=$!
  for _ in $(seq 1 120); do
    curl -fsS --max-time 3 "$API/health" >/dev/null 2>&1 && break
    kill -0 "$server_pid" 2>/dev/null || { echo "Paperclip stopped before it was ready" >&2; exit 1; }
    sleep 1
  done
fi

# Started here, not through a function, so watcher_pid is the node process itself. It is
# given this script's pid and the server's, and exits on its own once either is gone.
SELAN_SETTINGS="$settings" node -e "$SYNC_PROGRAM" "$API" "$SELAN_GATEWAY" watch $$ $server_pid &
watcher_pid=$!

case "$(uname -s)" in
  Darwin) open "http://127.0.0.1:$PORT" >/dev/null 2>&1 || true ;;
  *) xdg-open "http://127.0.0.1:$PORT" >/dev/null 2>&1 || true ;;
esac

if [ -n "$server_pid" ]; then
  wait "$server_pid"
else
  wait "$watcher_pid"
fi
