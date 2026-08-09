# PROTOTYPE: OQ-1, external attach to a live Codex session

Throwaway code that answered one question for [duet#11](https://github.com/mikheilkuzmidi/duet/issues/11). Not production, not a dependency, kept only as the primary source behind a decision.

## The question

Duet's design wants a **visible Codex window** the orchestrator can push work into, so the human watches the two agents collaborate instead of staring at a spinner.

[duet#3](https://github.com/mikheilkuzmidi/duet/issues/3) established that `codex app-server` accepts a turn on a thread the caller does not own. What it could not establish, because it ran in a credential-free home and stopped at a login screen, was whether a real **TUI** attached with `--remote` actually *renders* that injected turn.

If it does not render, the visible-window topology is theatre and Duet ships headless.

## Verdict: YES, both halves

`PROTOTYPE-attach.py`, two independent websocket clients against one app-server:

```
B could list A's thread       : True
B's turn/start on A's thread  : ACCEPTED
A saw events from B's turn    : True (18 events)
turn/* or item/* reached A    : True
model output visible to A     : DUET_OQ1_OK seen in A's stream
```

Client A owned the thread. Client B, a separate connection that never created it, started a turn on it. A received the entire stream: `turn/started`, `item/started`, six `item/agentMessage/delta` chunks, `item/completed`, `thread/tokenUsage/updated`, `turn/completed`, and the model's literal output text.

`PROTOTYPE-tui.py` then opened a real Terminal window running `codex --remote ws://...`, waited for it to attach, found the thread the TUI created, and injected a turn into it. **Confirmed visually: the injected text rendered in the TUI.**

## What this cost us to learn, so nobody repeats it

- **`--listen unix://PATH` creates a socket that never answers.** It accepts a connection, returns zero bytes, and logs nothing. `app-server proxy --sock` against it is equally silent. Use `ws://` instead, which announces itself and exposes `/readyz` and `/healthz`.
- **`app-server daemon start` needs a managed standalone install** at `$CODEX_HOME/packages/standalone/current/codex`. A bun or npm install of Codex does not have one, so the daemon path is unavailable. Spawning `app-server --listen` directly sidesteps it entirely.
- **Unix socket paths blow past `SUN_LEN`** (about 104 chars) if `CODEX_HOME` sits deep in a repo. Another reason to prefer `ws://`.
- **The protocol is discoverable, not guessable.** `codex app-server generate-json-schema --out DIR --experimental` emits a bundle matching the installed binary exactly: 127 client methods, including `thread/inject_items` and `turn/steer`, which are more direct injection primitives than `turn/start` and worth exploring.

## Running it again

Needs a `CODEX_HOME` with valid `auth.json` and a venv with `websockets`. Both were deleted after the run: the credential copy on purpose, since it should never have outlived the experiment.

```bash
python3 -m venv venv && venv/bin/pip install websockets
export CODEX_HOME=/path/to/an/isolated/home   # NOT ~/.codex, the desktop app shares its sqlite
venv/bin/python PROTOTYPE-attach.py
venv/bin/python PROTOTYPE-tui.py
```

Use an isolated `CODEX_HOME`. The ChatGPT desktop app runs its own `codex app-server` against `~/.codex` and shares `goals_1.sqlite`.
