#!/usr/bin/env python3
"""Drive a Codex goal to completion over the app-server stdio protocol.

This is a file rather than a heredoc inside duet-goal.sh because it is a state
machine, not a one-liner, and a two hundred line program embedded in a shell
string is a program nobody will ever fix. Everything it needs is in the Python
standard library, so Duet stays dependency free.

The contract it speaks, and how each part was established, is documented at the
top of duet-goal.sh. Read that first.

Exit codes match duet-goal.sh:
  0 complete   1 error   75 usage limited   76 budget limited
  77 blocked   78 timed out
"""

import argparse
import json
import queue
import subprocess
import sys
import threading
import time

OK, ERROR, USAGE_LIMITED, BUDGET_LIMITED, BLOCKED, TIMEOUT = 0, 1, 75, 76, 77, 78

# The wire uses camelCase, the sqlite mirror uses snake_case. Accept both, or a
# usage limit passes as an unrecognised status and the run looks like a hang.
TERMINAL = {
    "complete": OK,
    "usagelimited": USAGE_LIMITED,
    "usage_limited": USAGE_LIMITED,
    "budgetlimited": BUDGET_LIMITED,
    "budget_limited": BUDGET_LIMITED,
    "blocked": BLOCKED,
}

CONTINUE_TEXT = (
    "Continue toward the objective. Do not summarise progress and do not ask "
    "questions. Keep working until the exit gate passes, then stop."
)


def log(msg):
    print(f"  {msg}", file=sys.stderr, flush=True)


class Server:
    """A newline-delimited JSON-RPC peer on a child process's stdio."""

    def __init__(self, sink=None):
        self.proc = subprocess.Popen(
            ["codex", "app-server"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1,
        )
        self.inbox = queue.Queue()
        self.sink = sink
        self._id = 0
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(target=self._read_err, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            line = line.strip()
            if not line:
                continue
            # Every protocol line lands in the run directory. duet-progress.sh
            # parses this file for the heartbeat, so the shape must not change.
            if self.sink:
                self.sink.write(line + "\n")
                self.sink.flush()
            try:
                self.inbox.put(json.loads(line))
            except Exception:
                pass
        self.inbox.put(None)

    def _read_err(self):
        for line in self.proc.stderr:
            if line.strip():
                log(f"app-server: {line.rstrip()}")

    def send(self, method, params):
        self._id += 1
        self._write({"jsonrpc": "2.0", "id": self._id, "method": method, "params": params})
        return self._id

    def notify(self, method, params):
        self._write({"jsonrpc": "2.0", "method": method, "params": params})

    def reply(self, rid, result):
        self._write({"jsonrpc": "2.0", "id": rid, "result": result})

    def _write(self, msg):
        try:
            self.proc.stdin.write(json.dumps(msg) + "\n")
            self.proc.stdin.flush()
        except (BrokenPipeError, ValueError):
            pass

    def stop(self):
        try:
            self.proc.terminate()
            self.proc.wait(timeout=5)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass


def status_of(msg):
    """The goal status carried by a notification or response, if any."""
    for holder in (msg.get("params") or {}, msg.get("result") or {}):
        goal = holder.get("goal")
        if isinstance(goal, dict) and isinstance(goal.get("status"), str):
            return goal
    return None


def run(args):
    sink = open(args.out, "a") if args.out and args.out != "-" else None
    srv = Server(sink)
    deadline = time.time() + args.max_minutes * 60
    pending = {}          # request id -> label, for the few we care about
    goal = None
    turns = 0
    turn_running = False
    awaiting_continue_since = None

    def wait(rid, timeout=60):
        """Pump the inbox until a specific response arrives, handling the rest."""
        end = time.time() + timeout
        while time.time() < end:
            try:
                m = srv.inbox.get(timeout=1)
            except queue.Empty:
                continue
            if m is None:
                return None
            handled = dispatch(m)
            if handled is None and m.get("id") == rid and ("result" in m or "error" in m):
                return m
        return None

    def dispatch(m):
        """Answer server-initiated requests. Returns True if it consumed one."""
        if "method" in m and "id" in m:
            # The server is asking us something. With approvalPolicy "never"
            # this should not happen, but a guardian check can still arrive and
            # an unanswered request is an indefinite hang.
            if args.approve_escalations:
                srv.reply(m["id"], {"decision": "approved"})
                log(f"approved escalation: {m['method']}")
            else:
                srv.reply(m["id"], {"decision": "denied"})
                log(f"DENIED escalation: {m['method']} (fast mode is off)")
            return True
        return None

    try:
        rid = srv.send("initialize", {
            "clientInfo": {"name": "duet", "version": "0.4.0"},
            "capabilities": {"experimentalApi": True},
        })
        r = wait(rid, timeout=30)
        if not r or "error" in r:
            log(f"initialize failed: {json.dumps(r)[:300] if r else 'no response'}")
            return ERROR
        srv.notify("initialized", {})

        if args.rate_limits_only:
            rid = srv.send("account/rateLimits/read", {})
            r = wait(rid, timeout=20) or {}
            print(json.dumps(r.get("result", {})))
            return OK

        start = {
            "cwd": args.cwd,
            "sandbox": args.sandbox,
            # Approvals are forced off, matching `codex exec -s <mode>`, which
            # is what Duet already relies on everywhere else.
            "approvalPolicy": "never",
        }
        if args.model:
            start["model"] = args.model
        if args.developer_instructions:
            start["developerInstructions"] = open(args.developer_instructions).read()

        rid = srv.send("thread/start", start)
        r = wait(rid, timeout=60)
        if not r or "error" in r:
            log(f"thread/start failed: {json.dumps(r)[:300] if r else 'no response'}")
            return ERROR
        res = r.get("result") or {}
        # The id is nested under `thread`, which is not what the parameter name
        # on every other method would lead you to expect.
        thread = res.get("thread") or {}
        tid = thread.get("id") or thread.get("threadId") or res.get("threadId")
        if not tid:
            log(f"no thread id in response: {json.dumps(res)[:300]}")
            return ERROR

        objective = open(args.objective).read().strip()
        goal_params = {"threadId": tid, "objective": objective}
        if args.token_budget and int(args.token_budget) > 0:
            goal_params["tokenBudget"] = int(args.token_budget)

        rid = srv.send("thread/goal/set", goal_params)
        r = wait(rid, timeout=60)
        if not r or "error" in r:
            log(f"thread/goal/set failed: {json.dumps(r)[:300] if r else 'no response'}")
            return ERROR
        goal = (r.get("result") or {}).get("goal")
        log(f"goal set, status {goal.get('status') if goal else 'unknown'}")

        # Setting a goal has been observed to start a turn on its own. Wait
        # briefly for that before starting one, so both behaviours cost exactly
        # one turn.
        grace_end = time.time() + 8
        while time.time() < grace_end and not turn_running:
            try:
                m = srv.inbox.get(timeout=1)
            except queue.Empty:
                continue
            if m is None:
                break
            if dispatch(m):
                continue
            if m.get("method") == "turn/started":
                turn_running = True
                turns = 1
                log("the goal started its own turn")
            g = status_of(m)
            if g:
                goal = g

        if not turn_running:
            srv.send("turn/start", {
                "threadId": tid,
                "input": [{"type": "text", "text": objective}],
                **({"effort": args.effort} if args.effort else {}),
                **({"model": args.model} if args.model else {}),
            })
            turns = 1
            turn_running = True

        # ---- the loop that makes a goal different from a prompt ------------
        while True:
            if time.time() > deadline:
                log(f"hit goal.maxMinutes ({args.max_minutes})")
                return TIMEOUT

            try:
                m = srv.inbox.get(timeout=2)
            except queue.Empty:
                m = None

            if m is None and srv.proc.poll() is not None:
                log("app-server exited")
                return ERROR

            if m is not None:
                if dispatch(m):
                    continue

                method = m.get("method")
                if method == "turn/started":
                    turn_running = True
                    awaiting_continue_since = None
                elif method == "turn/completed":
                    turn_running = False
                    awaiting_continue_since = time.time()

                g = status_of(m)
                if g:
                    goal = g
                    st = (g.get("status") or "").lower()
                    if st in TERMINAL:
                        code = TERMINAL[st]
                        log(f"goal {st}: {g.get('tokensUsed', 0)} tokens, "
                            f"{g.get('timeUsedSeconds', 0)}s, {turns} turns")
                        return code

            # A turn ended and the goal is not complete. Give the server its
            # own chance to continue, then push it. This is the part that turns
            # "the model stopped talking" into "the work is not done yet".
            if (not turn_running and awaiting_continue_since
                    and time.time() - awaiting_continue_since > args.continue_grace):
                if turns >= args.max_turns:
                    log(f"reached goal.maxTurns ({args.max_turns}) without completing")
                    return TIMEOUT
                turns += 1
                log(f"continuing, turn {turns}")
                srv.send("turn/start", {
                    "threadId": tid,
                    "input": [{"type": "text", "text": CONTINUE_TEXT}],
                    **({"effort": args.effort} if args.effort else {}),
                })
                turn_running = True
                awaiting_continue_since = None

    except KeyboardInterrupt:
        return ERROR
    finally:
        srv.stop()
        if sink:
            sink.close()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--objective")
    p.add_argument("--cwd", default=".")
    p.add_argument("--out", default="-")
    p.add_argument("--model", default="")
    p.add_argument("--effort", default="")
    p.add_argument("--sandbox", default="workspace-write")
    p.add_argument("--developer-instructions", default="")
    p.add_argument("--token-budget", default="0")
    p.add_argument("--max-minutes", type=float, default=120)
    p.add_argument("--max-turns", type=int, default=40)
    p.add_argument("--continue-grace", type=float, default=20)
    p.add_argument("--approve-escalations", action="store_true")
    p.add_argument("--rate-limits-only", action="store_true")
    args = p.parse_args()
    if not args.rate_limits_only and not args.objective:
        p.error("--objective is required")
    sys.exit(run(args))


if __name__ == "__main__":
    main()
