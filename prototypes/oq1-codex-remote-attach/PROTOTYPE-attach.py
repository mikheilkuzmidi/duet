#!/usr/bin/env python3
"""PROTOTYPE. Throwaway. Answers OQ-1 for duet#11.

QUESTION
  Can a second, independent client attach to a running `codex app-server`,
  start a turn on a thread it does not own, and does the OWNING client see
  the resulting event stream?

  That is the mechanism behind Duet's "visible Codex window": the human's TUI
  owns a thread, and the orchestrator (a separate process) pushes work into it.

TRANSPORT NOTE
  `--listen unix://PATH` creates a socket but never answers, and
  `app-server proxy --sock` against it returns nothing either. The websocket
  listener is the one that works and announces itself, so that is what the TUI
  `--remote ws://...` flag will be talking to as well.

Run:  PROTOTYPE-venv-WIPE-ME/bin/python PROTOTYPE-attach.py
"""
import asyncio, json, os, subprocess, sys, time
import websockets

HERE = os.path.dirname(os.path.abspath(__file__))
CODEX_HOME = os.path.join(HERE, "PROTOTYPE-codex-home-WIPE-ME")
PORT = 8137
URL = f"ws://127.0.0.1:{PORT}"
LOG = "/tmp/dq1/ws.log"


def log(tag, msg):
    print(f"  [{tag}] {msg}", flush=True)


class Client:
    def __init__(self, name):
        self.name = name
        self.ws = None
        self.next_id = 1
        self.replies = {}
        self.notes = []

    async def connect(self):
        self.ws = await websockets.connect(URL, max_size=64 * 1024 * 1024)
        asyncio.create_task(self._pump())

    async def _pump(self):
        try:
            async for raw in self.ws:
                msg = json.loads(raw)
                if "id" in msg and ("result" in msg or "error" in msg):
                    self.replies[msg["id"]] = msg
                else:
                    self.notes.append(msg)
                    m = msg.get("method", "?")
                    if m.startswith(("turn/", "item/", "thread/")):
                        log(self.name, f"NOTIFY {m}")
        except Exception as e:
            log(self.name, f"pump ended: {type(e).__name__}")

    async def call(self, method, params=None, timeout=180):
        rid = self.next_id
        self.next_id += 1
        await self.ws.send(json.dumps({"jsonrpc": "2.0", "id": rid,
                                       "method": method,
                                       "params": params if params is not None else {}}))
        end = time.time() + timeout
        while time.time() < end:
            if rid in self.replies:
                return self.replies.pop(rid)
            await asyncio.sleep(0.05)
        return {"error": {"message": f"TIMEOUT after {timeout}s"}}

    async def init(self):
        r = await self.call("initialize", {
            "clientInfo": {"name": f"duet-prototype-{self.name}", "version": "0.0.0"},
            "capabilities": {"experimentalApi": True},
        })
        ok = "result" in r
        log(self.name, f"initialize -> {'ok' if ok else json.dumps(r)[:200]}")
        return ok


async def main():
    os.makedirs("/tmp/dq1", exist_ok=True)
    env = dict(os.environ, CODEX_HOME=CODEX_HOME)

    print("\n=== 1. spawn app-server (websocket) ===", flush=True)
    srv = subprocess.Popen(["codex", "app-server", "--listen", URL],
                           env=env, cwd=HERE,
                           stdout=open(LOG, "wb"), stderr=subprocess.STDOUT,
                           stdin=subprocess.DEVNULL)
    await asyncio.sleep(5)
    log("srv", f"pid {srv.pid}, {open(LOG).read().strip().splitlines()[:2]}")

    try:
        print("\n=== 2. client A connects and starts a thread ===", flush=True)
        A = Client("A"); await A.connect()
        if not await A.init():
            return 1
        r = await A.call("thread/start", {"cwd": HERE})
        if "result" not in r:
            log("A", f"thread/start FAILED {json.dumps(r)[:300]}"); return 1
        res = r["result"]
        tid = res.get("threadId") or res.get("thread", {}).get("id") or res.get("id")
        log("A", f"thread/start -> threadId={tid}")

        print("\n=== 3. client B connects INDEPENDENTLY ===", flush=True)
        B = Client("B"); await B.connect()
        if not await B.init():
            return 1

        print("\n=== 4. can B see a thread it did not create? ===", flush=True)
        r = await B.call("thread/loaded/list", {})
        blob = json.dumps(r.get("result", r))
        visible = bool(tid) and tid in blob
        log("B", f"thread/loaded/list -> {blob[:300]}")
        log("B", f"A's thread visible to B: {visible}")

        print("\n=== 5. B starts a turn on A's thread (the real question) ===", flush=True)
        before = len(A.notes)
        r = await B.call("turn/start", {
            "threadId": tid,
            "input": [{"type": "text",
                       "text": "Reply with exactly: DUET_OQ1_OK. Nothing else."}],
        }, timeout=240)
        accepted = "result" in r
        log("B", "turn/start accepted=%s %s" % (
            accepted, "" if accepted else json.dumps(r)[:400]))

        print("\n=== 6. did the OWNER (A) receive the stream? ===", flush=True)
        await asyncio.sleep(8)
        new_a = [n.get("method", "?") for n in A.notes[before:]]
        log("A", f"notifications received while B drove: {len(new_a)}")
        for m in new_a[:30]:
            log("A", f"   {m}")

        text = ""
        for n in A.notes[before:]:
            s = json.dumps(n)
            if "DUET_OQ1_OK" in s:
                text = "DUET_OQ1_OK seen in A's stream"
                break

        print("\n=== VERDICT ===", flush=True)
        print(f"  B could list A's thread       : {visible}")
        print(f"  B's turn/start on A's thread  : {'ACCEPTED' if accepted else 'REJECTED'}")
        print(f"  A saw events from B's turn    : {len(new_a) > 0} ({len(new_a)} events)")
        print(f"  turn/* or item/* reached A    : "
              f"{any(m.startswith(('turn/', 'item/')) for m in new_a)}")
        print(f"  model output visible to A     : {text or 'not found'}")
        return 0
    finally:
        try:
            srv.terminate(); srv.wait(timeout=10)
        except Exception:
            srv.kill()
        log("srv", "stopped")


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
