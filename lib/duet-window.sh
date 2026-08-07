#!/usr/bin/env bash
# The visible Codex window. (issue #11)
#
# Proven working, not assumed: an independent client can start a turn on a
# thread it does not own, the owner receives the full event stream, and a TUI
# attached with `--remote` renders the injected turn on screen. See the
# prototype/oq1-codex-remote-attach branch for the harness and its output.
#
# Transport is WEBSOCKET. `--listen unix://PATH` creates a socket that accepts a
# connection, returns zero bytes, and logs nothing; `app-server proxy --sock`
# against it is equally silent. ws:// announces itself and exposes /readyz.
#
# Duet does NOT use `app-server daemon start`: it requires a managed standalone
# install at $CODEX_HOME/packages/standalone/current/codex which bun and npm
# installs do not have. Spawning app-server directly sidesteps that entirely.

# shellcheck source=duet-common.sh
. "$(dirname "${BASH_SOURCE[0]}")/duet-common.sh"

DUET_WS_PORT="${DUET_WS_PORT:-8791}"
DUET_WS_URL="ws://127.0.0.1:${DUET_WS_PORT}"

duet_window_enabled () { [ "$(duet_cfg window.visible false)" = "true" ]; }

duet_appserver_start () {   # <run-dir> ; echoes the pid
  local dir="$1" log="$1/app-server.log"
  codex app-server --listen "$DUET_WS_URL" > "$log" 2>&1 < /dev/null &
  local pid=$!
  local i=0
  while [ $i -lt 40 ]; do
    grep -q "listening on" "$log" 2>/dev/null && break
    sleep 0.25; i=$((i+1))
  done
  if ! kill -0 "$pid" 2>/dev/null; then
    duet_err "app-server failed to start (see $log)"; return 1
  fi
  duet_ok "codex app-server on $DUET_WS_URL"
  printf '%s' "$pid"
}

# Opening a terminal has no portable primitive, so this is a LADDER and every
# rung degrades honestly:
#   macOS   `open -a Terminal file.command` needs no TCC grant, unlike osascript
#   tmux    a new window in an existing session, if we are inside one
#   Linux   the -e flag means four incompatible things across terminals, so we
#           try a few and do not pretend to cover them all
#   last    print the command and let the human paste it. Not a failure; a
#           tool that says "run this" beats one that silently does nothing.
duet_window_open () {   # <run-dir>
  local dir="$1" launcher="$1/attach-codex.command"
  cat > "$launcher" <<EOF
#!/bin/bash
export CODEX_HOME="\${CODEX_HOME:-\$HOME/.codex}"
echo "Duet: attaching this window to $DUET_WS_URL"
echo "Work sent by the orchestrator appears here. Leave it open."
exec codex --remote "$DUET_WS_URL"
EOF
  chmod +x "$launcher"

  if [ "$(uname)" = "Darwin" ] && command -v open >/dev/null; then
    open -a Terminal "$launcher" && { duet_ok "opened a visible Codex window"; return 0; }
  fi
  if [ -n "${TMUX:-}" ] && duet_has tmux; then
    tmux new-window -n duet-codex "$launcher" && { duet_ok "opened a tmux window"; return 0; }
  fi
  for t in x-terminal-emulator gnome-terminal konsole xfce4-terminal alacritty kitty; do
    duet_has "$t" && { "$t" -e "$launcher" >/dev/null 2>&1 & duet_ok "opened $t"; return 0; }
  done

  duet_warn "no way to open a terminal window on this system."
  duet_say  "  run this yourself in another window to watch Codex work:"
  duet_say  "    codex --remote $DUET_WS_URL"
  return 1
}

# Inject a turn into whatever thread the attached TUI owns. Requires the
# `websockets` package; without it Duet falls back to headless delegation rather
# than failing, because the window is a nicety and the pipeline is not.
duet_window_send () {   # <prompt-file>
  local prompt="$1"
  python3 - "$DUET_WS_URL" "$prompt" <<'PY'
import asyncio,json,sys,time
try:
    import websockets
except ImportError:
    print("websockets not installed; falling back to headless delegation", file=sys.stderr)
    sys.exit(3)
url, path = sys.argv[1], sys.argv[2]
text = open(path).read()

async def rpc(ws, rid, method, params, timeout=300):
    await ws.send(json.dumps({"jsonrpc":"2.0","id":rid,"method":method,"params":params}))
    end=time.time()+timeout
    while time.time()<end:
        m=json.loads(await asyncio.wait_for(ws.recv(), timeout=timeout))
        if m.get("id")==rid and ("result" in m or "error" in m): return m
    return {"error":{"message":"timeout"}}

async def main():
    async with websockets.connect(url, max_size=64*1024*1024) as ws:
        await rpc(ws,1,"initialize",
                  {"clientInfo":{"name":"duet","version":"0.1.0"},
                   "capabilities":{"experimentalApi":True}})
        r=await rpc(ws,2,"thread/loaded/list",{})
        threads=(r.get("result") or {}).get("data") or []
        if not threads:
            print("no attached thread; is the Codex window open?", file=sys.stderr); return 4
        r=await rpc(ws,3,"turn/start",
                    {"threadId":threads[0],"input":[{"type":"text","text":text}]})
        if "error" in r:
            print(json.dumps(r)[:300], file=sys.stderr); return 5
        print(threads[0]); return 0

sys.exit(asyncio.run(main()) or 0)
PY
}

duet_appserver_stop () { [ -n "${1:-}" ] && kill "$1" 2>/dev/null && duet_ok "app-server stopped"; }

# The Codex desktop app runs its OWN app-server against ~/.codex and shares
# goals_1.sqlite. Warn rather than risk a collision.
duet_window_precheck () {
  if pgrep -f "ChatGPT.app.*codex app-server" >/dev/null 2>&1; then
    duet_warn "the Codex desktop app is running its own app-server."
    duet_warn "  consider a separate CODEX_HOME to avoid sqlite collisions."
  fi
}
