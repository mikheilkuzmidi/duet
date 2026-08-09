#!/usr/bin/env python3
"""PROTOTYPE. Throwaway. Second half of OQ-1 for duet#11.

QUESTION
  The app-server half is proven: an independent client can start a turn on a
  thread it does not own, and the owner receives the full stream.

  Remaining: does a REAL Codex TUI, attached with `--remote`, actually RENDER
  an externally injected turn? That is what makes the "visible Codex window"
  in Duet's design real rather than theatre.

WHAT THIS DOES
  1. starts `codex app-server --listen ws://127.0.0.1:8137` (isolated CODEX_HOME)
  2. opens a VISIBLE Terminal window running `codex --remote ws://...`
  3. waits for you to confirm the TUI is up
  4. finds the thread the TUI owns via thread/loaded/list
  5. injects a turn into it from this process
  6. you report whether the text appeared on screen

Run:  PROTOTYPE-venv-WIPE-ME/bin/python PROTOTYPE-tui.py
"""
import asyncio, json, os, subprocess, sys, time
import websockets

HERE = os.path.dirname(os.path.abspath(__file__))
CODEX_HOME = os.path.join(HERE, "PROTOTYPE-codex-home-WIPE-ME")
PORT = 8137
URL = f"ws://127.0.0.1:{PORT}"
LAUNCHER = os.path.join(HERE, "PROTOTYPE-open-tui.command")
MARKER = "DUET_OQ1_RENDERED_OK"


async def rpc(ws, rid, method, params, timeout=180):
    await ws.send(json.dumps({"jsonrpc": "2.0", "id": rid,
                              "method": method, "params": params}))
    end = time.time() + timeout
    while time.time() < end:
        raw = await asyncio.wait_for(ws.recv(), timeout=timeout)
        msg = json.loads(raw)
        if msg.get("id") == rid and ("result" in msg or "error" in msg):
            return msg
    return {"error": {"message": "timeout"}}


async def main():
    env = dict(os.environ, CODEX_HOME=CODEX_HOME)

    with open(LAUNCHER, "w") as f:
        f.write(f"""#!/bin/bash
# PROTOTYPE launcher. Throwaway.
export CODEX_HOME="{CODEX_HOME}"
echo "Codex TUI attaching to {URL} ..."
echo "Leave this window OPEN and VISIBLE."
exec codex --remote "{URL}"
""")
    os.chmod(LAUNCHER, 0o755)

    print("=== 1. start app-server ===", flush=True)
    srv = subprocess.Popen(["codex", "app-server", "--listen", URL],
                           env=env, cwd=HERE,
                           stdout=open("/tmp/dq1/tui-srv.log", "wb"),
                           stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    await asyncio.sleep(5)
    print(f"  server pid {srv.pid} on {URL}", flush=True)

    print("=== 2. open a VISIBLE Terminal window with the TUI attached ===", flush=True)
    subprocess.run(["open", "-a", "Terminal", LAUNCHER], check=False)
    print("  a Terminal window should now be opening", flush=True)

    print("=== 3. waiting 25s for the TUI to attach ===", flush=True)
    await asyncio.sleep(25)

    async with websockets.connect(URL, max_size=64 * 1024 * 1024) as ws:
        await rpc(ws, 1, "initialize",
                  {"clientInfo": {"name": "duet-injector", "version": "0"},
                   "capabilities": {"experimentalApi": True}})
        r = await rpc(ws, 2, "thread/loaded/list", {})
        threads = (r.get("result") or {}).get("data") or []
        print(f"=== 4. threads loaded on the server: {threads} ===", flush=True)
        if not threads:
            print("  NO THREAD. The TUI did not attach or did not create one.")
            print("  Leaving the server running so you can look. pid", srv.pid)
            return 2

        tid = threads[0]
        print(f"=== 5. injecting a turn into the TUI's thread {tid} ===", flush=True)
        r = await rpc(ws, 3, "turn/start", {
            "threadId": tid,
            "input": [{"type": "text",
                       "text": f"Reply with exactly: {MARKER}. Nothing else."}],
        }, timeout=240)
        print("  turn/start accepted:", "result" in r, flush=True)
        if "error" in r:
            print("  error:", json.dumps(r)[:400])

    print(f"""
=== 6. LOOK AT THE TERMINAL WINDOW ===

  Did '{MARKER}' appear in the attached Codex TUI?

  YES -> a --remote TUI renders externally injected turns. The visible
         Codex window in Duet is real.
  NO  -> the app-server accepts the turn but the TUI does not render it.
         Duet ships headless with a copy-pasteable handoff instead.

  Server still running as pid {srv.pid} so you can inspect.
  Stop it with:  kill {srv.pid}
""", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
