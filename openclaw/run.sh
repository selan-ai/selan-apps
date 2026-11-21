#!/usr/bin/env bash
# shellcheck disable=SC2016 # the single-quoted node programs are meant to stay unexpanded
# Starts OpenClaw on your company's Selan accounts. Arguments go to openclaw:
#   run.sh agent exec "hello"            run.sh tui
# With no arguments it runs OpenClaw's Gateway, which serves its web UI, on
# 127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}. With SELAN_APP_PORT set and no arguments it
# answers on 0.0.0.0:$SELAN_APP_PORT instead, for Selan's proxy, which signs members in by
# sending their identity in X-Forwarded-User.
#
# Needs SELAN_TOKEN. Asks the gateway for the company's models, writes OpenClaw's config
# from them (a reference to the token, never the token), and starts openclaw with the
# token in its environment only. SELAN_APP_MODEL, if set, is the default model instead of
# the company's first.
set -euo pipefail

: "${SELAN_TOKEN:?SELAN_TOKEN is not set: export a selanct_ API token, minted by an owner at control.selan.ai > Settings > API tokens}"
SELAN_GATEWAY="${SELAN_GATEWAY:-https://gw.selan.ai}"
SELAN_GATEWAY="${SELAN_GATEWAY%/}"
APP_HOME="${SELAN_APP_HOME:-$HOME/.selan/apps/openclaw}"

# Serving behind Selan's proxy: whoever reaches SELAN_APP_PORT reaches the Gateway's sign-in,
# so it is set only behind a proxy that signs people in.
SELAN_APP_PORT="${SELAN_APP_PORT:-}"
SELAN_APP_PUBLIC_URL="${SELAN_APP_PUBLIC_URL:-}"
SELAN_APP_PUBLIC_URL="${SELAN_APP_PUBLIC_URL%/}"
# OpenClaw's Gateway has no password a proxy could sign in with: a browser types it, and then
# still needs a one-time approval on the Gateway host. Behind Selan's proxy it trusts the proxy's
# X-Forwarded-User instead, so a password is not used there and not kept in the environment.
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

OPENCLAW="$APP_HOME/bin/openclaw"
[ -x "$OPENCLAW" ] || { echo "openclaw is not installed in $APP_HOME: run install.sh first" >&2; exit 1; }

# OpenClaw's whole state lives here, not in ~/.openclaw.
export OPENCLAW_STATE_DIR="$APP_HOME/home"
export OPENCLAW_CONFIG_PATH="$OPENCLAW_STATE_DIR/openclaw.json"
export OPENCLAW_WORKSPACE_DIR="$OPENCLAW_STATE_DIR/workspace"
mkdir -p "$OPENCLAW_STATE_DIR" "$APP_HOME/xdg"
chmod 700 "$OPENCLAW_STATE_DIR"

# What openclaw and the tools it starts would otherwise keep under ~/.local, ~/.cache and ~/.config.
export XDG_DATA_HOME="$APP_HOME/xdg/data" XDG_STATE_HOME="$APP_HOME/xdg/state"
export XDG_CACHE_HOME="$APP_HOME/xdg/cache" XDG_CONFIG_HOME="$APP_HOME/xdg/config"
export PYTHONPYCACHEPREFIX="$APP_HOME/xdg/cache/pycache" npm_config_cache="$APP_HOME/xdg/cache/npm"
# Nothing on the network should hear it advertise itself over mDNS.
export OPENCLAW_DISABLE_BONJOUR=1

# The token goes to curl on stdin, so it is not in a process listing.
settings="$(printf 'header = "Authorization: Bearer %s"\n' "$SELAN_TOKEN" \
  | curl -fsS --max-time 15 -K - "$SELAN_GATEWAY/selan/settings")" \
  || { echo "could not read company settings from $SELAN_GATEWAY/selan/settings" >&2; exit 1; }

# The model the host picked (Selan's Agents tab), checked against the company's picker models
# before anything starts. Unset, OpenClaw defaults to the first of them.
SELAN_APP_MODEL="${SELAN_APP_MODEL:-}"
if [ -n "$SELAN_APP_MODEL" ]; then
  SELAN_SETTINGS="$settings" node -e '
const ids = (JSON.parse(process.env.SELAN_SETTINGS).pickerModels || []).map((m) => m.id);
process.exit(ids.includes(process.argv[1]) ? 0 : 1);
' "$SELAN_APP_MODEL" \
    || { echo "SELAN_APP_MODEL $SELAN_APP_MODEL is not one of the company's models in its Selan settings" >&2; exit 1; }
fi

# On loopback, for the person at this machine: a password made once here and kept in
# gateway/password (owner only), which the Control UI asks for.
if [ -z "$SELAN_APP_PORT" ]; then
  mkdir -p "$APP_HOME/gateway"
  chmod 700 "$APP_HOME/gateway"
  [ -s "$APP_HOME/gateway/password" ] \
    || (umask 077 && node -e 'process.stdout.write(require("crypto").randomBytes(24).toString("base64url") + "\n")' >"$APP_HOME/gateway/password")
  OPENCLAW_GATEWAY_PASSWORD="$(cat "$APP_HOME/gateway/password")"
  export OPENCLAW_GATEWAY_PASSWORD
fi

if [ -n "$SELAN_APP_PORT" ]; then
  BIND=lan
  PORT="$SELAN_APP_PORT"
else
  BIND=loopback
  PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
fi
export SELAN_OPENCLAW_TOKEN="$SELAN_TOKEN"

# One validated write of everything Selan owns in openclaw.json: two model providers on the
# Anthropic Messages endpoint, the default model and, when this launch serves the Gateway, its
# bind, port, sign-in and public address (a command run beside a Gateway that is already up
# must not move it). Objects merge, so what you change elsewhere in OpenClaw stays; "null"
# removes a key. The token is only named.
#
# Claude has a provider of its own, "selan-claude", and every other model is in "selan". OpenClaw
# disables a provider for ten minutes and more on a billing error, and Claude served from a Claude
# subscription answers OpenClaw with one (Anthropic's "extra usage" 400). With one provider that
# would stop every model; with two it stops Claude alone. A provider with no models is removed.
SELAN_SETTINGS="$settings" SELAN_APP_MODEL="$SELAN_APP_MODEL" node -e '
const [gateway, bind, port, publicUrl, serve] = process.argv.slice(1);
const behindProxy = bind === "lan";
const settings = JSON.parse(process.env.SELAN_SETTINGS);
const models = settings.pickerModels || [];
const claude = (id) => id.startsWith("claude-") && !id.startsWith("claude-selan-");
const zero = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
const primary = process.env.SELAN_APP_MODEL || (models[0] || {}).id;
const provider = (claudeModels) => {
  const listed = models.filter((m) => claude(m.id) === claudeModels);
  return listed.length === 0 ? null : {
    baseUrl: gateway + "/anthropic",
    apiKey: "${SELAN_OPENCLAW_TOKEN}",
    api: "anthropic-messages",
    models: listed.map((m) => ({
      id: m.id, name: m.displayName, reasoning: claudeModels,
      input: claudeModels ? ["text", "image"] : ["text"],
      cost: zero, contextWindow: settings.contextLimit || 200000, maxTokens: 32000,
    })),
  };
};
process.stdout.write(JSON.stringify({
  ...(serve === "serve" ? { gateway: {
    mode: "local", bind, port: Number(port),
    // Behind the proxy: members arrive signed in, as the user it names, from a private address;
    // every browser of theirs is approved. On loopback: the password above.
    auth: behindProxy
      ? { mode: "trusted-proxy", trustedProxy: { userHeader: "x-forwarded-user",
          deviceAutoApprove: { enabled: true, scopes: ["operator.read", "operator.write", "operator.approvals", "operator.questions"] } } }
      : { mode: "password", password: "${OPENCLAW_GATEWAY_PASSWORD}" },
    trustedProxies: behindProxy ? ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fc00::/7"] : null,
    publicOrigin: publicUrl || null,
  } } : {}),
  models: {
    mode: "merge",
    providers: { selan: provider(false), "selan-claude": provider(true) },
  },
  ...(primary ? { agents: { defaults: { model: {
    primary: (claude(primary) ? "selan-claude/" : "selan/") + primary,
  } } } } : {}),
}));
' "$SELAN_GATEWAY" "$BIND" "$PORT" "$SELAN_APP_PUBLIC_URL" "$([ "$#" -eq 0 ] && echo serve || echo args)" \
  | "$OPENCLAW" config patch --stdin >/dev/null

if [ -n "$SELAN_APP_PORT" ] && [ "$#" -eq 0 ]; then
  echo "OpenClaw on 0.0.0.0:$SELAN_APP_PORT: members come in as the X-Forwarded-User the proxy sends"
  exec "$OPENCLAW" gateway
fi
if [ "$#" -eq 0 ]; then
  echo "OpenClaw on 127.0.0.1:$PORT: sign in with the password in $APP_HOME/gateway/password"
  exec "$OPENCLAW" gateway
fi
exec "$OPENCLAW" "$@"
