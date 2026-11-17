#!/usr/bin/env bash
# Starts Paperclip and gives it a "Selan" AI connection, so its agents run on your
# company's Selan accounts. Arguments go to `paperclipai run`.
#
# Paperclip itself always listens on 127.0.0.1. With SELAN_APP_PORT set, a forwarder also
# answers on 0.0.0.0:$SELAN_APP_PORT, for Selan's proxy, and no browser is opened.
#
# Paperclip keeps AI connections in its own database, so SELAN_TOKEN is stored there
# (sealed with Paperclip's own key file) as the connection's API key. This script
# creates that connection in every company Paperclip has, updates its key at each launch
# (never a second connection), binds every claude_local agent that has no AI connection
# to it, and does the same for companies and agents added while it runs. SELAN_APP_MODEL,
# if set, is the model those agents run on.
set -euo pipefail

: "${SELAN_TOKEN:?SELAN_TOKEN is not set: export a selanct_ API token, minted by an owner at control.selan.ai > Settings > API tokens}"
SELAN_GATEWAY="${SELAN_GATEWAY:-https://gw.selan.ai}"
SELAN_GATEWAY="${SELAN_GATEWAY%/}"
APP_HOME="${SELAN_APP_HOME:-$HOME/.selan/apps/paperclip}"
PORT="${PAPERCLIP_PORT:-3100}"
API="http://127.0.0.1:$PORT/api"

# Serving behind Selan's proxy. Whoever reaches SELAN_APP_PORT reaches Paperclip as its
# admin, so it is set only behind a proxy that signs people in.
SELAN_APP_PORT="${SELAN_APP_PORT:-}"
SELAN_APP_PUBLIC_URL="${SELAN_APP_PUBLIC_URL:-}"
SELAN_APP_PUBLIC_URL="${SELAN_APP_PUBLIC_URL%/}"
# Paperclip has no sign-in of its own for a password to open, and its agents need not see one.
unset SELAN_APP_PASSWORD
if [ -n "$SELAN_APP_PORT" ]; then
  { [[ "$SELAN_APP_PORT" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$SELAN_APP_PORT" -le 65535 ]; } \
    || { echo "SELAN_APP_PORT is not a port number: $SELAN_APP_PORT" >&2; exit 1; }
  [ "$SELAN_APP_PORT" != "$PORT" ] \
    || { echo "SELAN_APP_PORT must differ from Paperclip's own port ($PORT, PAPERCLIP_PORT)" >&2; exit 1; }
elif [ -n "$SELAN_APP_PUBLIC_URL" ]; then
  echo "SELAN_APP_PUBLIC_URL is set without SELAN_APP_PORT" >&2
  exit 1
fi
if [ -n "$SELAN_APP_PUBLIC_URL" ]; then
  # Paperclip has no subpath support: the app is the whole of its own hostname.
  [[ "$SELAN_APP_PUBLIC_URL" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] \
    || { echo "SELAN_APP_PUBLIC_URL must be https://<host>, with no path: $SELAN_APP_PUBLIC_URL" >&2; exit 1; }
  # Paperclip's links use it, and its hostname guard then lets that Host header through.
  export PAPERCLIP_PUBLIC_URL="$SELAN_APP_PUBLIC_URL"
fi

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

# The model the host picked (Selan's Agents tab), checked against the company's picker models
# before Paperclip starts. Unset, agents keep the model Paperclip gives them.
SELAN_APP_MODEL="${SELAN_APP_MODEL:-}"
if [ -n "$SELAN_APP_MODEL" ]; then
  SELAN_SETTINGS="$settings" node -e '
const ids = (JSON.parse(process.env.SELAN_SETTINGS).pickerModels || []).map((m) => m.id);
process.exit(ids.includes(process.argv[1]) ? 0 : 1);
' "$SELAN_APP_MODEL" \
    || { echo "SELAN_APP_MODEL $SELAN_APP_MODEL is not one of the company's models in its Selan settings" >&2; exit 1; }
fi

# Paperclip's local REST API: one pass over every company, then (with "watch") again every
# 15 seconds. SELAN_TOKEN is written into the connection on the first pass only. The loop
# ends when run.sh or the server it started is gone (a SIGKILL of run.sh runs no trap).
# SELAN_APP_MODEL goes into an agent's adapterConfig.model the first time this launch sees
# the agent on the Selan connection: all of them on the first pass, then each agent added or
# bound later. A model someone picks in Paperclip afterwards stays until the next launch.
SYNC_PROGRAM='
const [api, gateway, mode, ...pids] = process.argv.slice(1);
const alive = (pid) => { try { process.kill(Number(pid), 0); return true; } catch (e) { return e.code === "EPERM"; } };
const settings = JSON.parse(process.env.SELAN_SETTINGS);
const NAME = "Selan";
const MODEL = process.env.SELAN_APP_MODEL || "";
const modelGiven = new Set();

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
    if (agent.adapterType !== "claude_local") continue;
    const bind = !runtime.aiConnection || dropped.has(bound);
    const onSelan = bind || bound === connection.id;
    const setModel = MODEL && onSelan && !modelGiven.has(agent.id) && (agent.adapterConfig || {}).model !== MODEL;
    if (bind || setModel) {
      await call("PATCH", "/agents/" + agent.id, {
        ...(bind ? { runtimeConfig: { ...runtime, aiConnection: binding } } : {}),
        ...(setModel ? { adapterConfig: { model: MODEL } } : {}),
      });
    }
    // Only once the change has landed, so a failed PATCH is tried again on the next pass.
    if (onSelan) modelGiven.add(agent.id);
    if (bind) console.log("bound agent " + agent.name + " to the " + NAME + " connection");
    if (setModel) console.log("agent " + agent.name + " runs on " + MODEL);
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
    for (let second = 0; second < 15 && pids.every(alive); second++) await new Promise((r) => setTimeout(r, 1000));
    if (!pids.every(alive)) break;
    try { await pass(false); } catch (e) { console.error("warning: " + e.message); }
  }
})();
'
# Paperclip's local_trusted mode only listens on loopback (it refuses any other bind),
# so the proxy reaches it through this byte-for-byte TCP forwarder, websockets included.
# It exits once run.sh or the server is gone, and stops run.sh if it cannot listen.
FORWARD_PROGRAM='
const net = require("net");
const [listenPort, targetPort, ...pids] = process.argv.slice(1);
const alive = (pid) => { try { process.kill(Number(pid), 0); return true; } catch (e) { return e.code === "EPERM"; } };
const server = net.createServer((client) => {
  const upstream = net.connect(Number(targetPort), "127.0.0.1");
  const close = () => { client.destroy(); upstream.destroy(); };
  for (const socket of [client, upstream]) { socket.on("error", close); socket.on("close", close); }
  client.pipe(upstream);
  upstream.pipe(client);
});
server.on("error", (e) => {
  console.error("could not listen on 0.0.0.0:" + listenPort + ": " + e.message);
  try { process.kill(Number(pids[0]), "SIGTERM"); } catch (_) {}
  process.exit(1);
});
server.listen(Number(listenPort), "0.0.0.0", () => console.log("Paperclip answers on 0.0.0.0:" + listenPort));
setInterval(() => { if (!pids.every(alive)) process.exit(0); }, 1000);
'
# Job control gives the server its own process group, which holds its embedded Postgres
# too, so the whole group can be stopped at once.
set -m
server_pid=""
watcher_pid=""
guard_pid=""
forwarder_pid=""
stop() {
  [ -z "$guard_pid" ] || kill "$guard_pid" 2>/dev/null || true
  [ -z "$forwarder_pid" ] || kill "$forwarder_pid" 2>/dev/null || true
  [ -z "$watcher_pid" ] || kill "$watcher_pid" 2>/dev/null || true
  if [ -n "$server_pid" ]; then
    kill -TERM -- "-$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
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
  # SIGKILL runs no trap, so a guard outside this shell stops the server's group once this
  # script's pid is gone, with a SIGKILL after 10 seconds if Paperclip has not finished.
  (
    while kill -0 "$$" 2>/dev/null; do sleep 1; done
    kill -TERM -- "-$server_pid" 2>/dev/null || exit 0
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$server_pid" 2>/dev/null || exit 0; sleep 1; done
    kill -KILL -- "-$server_pid" 2>/dev/null || true
  ) </dev/null >/dev/null 2>&1 &
  guard_pid=$!
  for _ in $(seq 1 120); do
    curl -fsS --max-time 3 "$API/health" >/dev/null 2>&1 && break
    kill -0 "$server_pid" 2>/dev/null || { echo "Paperclip stopped before it was ready" >&2; exit 1; }
    sleep 1
  done
fi

# Started here, not through a function, so watcher_pid is the node process itself. It is
# given this script's pid and the server's, and exits on its own once either is gone.
SELAN_SETTINGS="$settings" SELAN_APP_MODEL="$SELAN_APP_MODEL" node -e "$SYNC_PROGRAM" "$API" "$SELAN_GATEWAY" watch $$ $server_pid &
watcher_pid=$!

if [ -n "$SELAN_APP_PORT" ]; then
  node -e "$FORWARD_PROGRAM" "$SELAN_APP_PORT" "$PORT" $$ $server_pid &
  forwarder_pid=$!
else
  case "$(uname -s)" in
    Darwin) open "http://127.0.0.1:$PORT" >/dev/null 2>&1 || true ;;
    *) xdg-open "http://127.0.0.1:$PORT" >/dev/null 2>&1 || true ;;
  esac
fi

if [ -n "$server_pid" ]; then
  wait "$server_pid"
else
  wait "$watcher_pid"
fi
