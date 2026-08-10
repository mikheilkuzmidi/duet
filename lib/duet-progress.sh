#!/usr/bin/env bash
# Showing that the other agent is alive.
#
# A four minute silent phase and a hung process look identical from the outside,
# and the human's reasonable response to both is to kill it. So Duet reports
# liveness, at a level the human chose at setup.
#
# TWO SCHEMAS, both verified against live runs rather than assumed, because
# Codex speaks differently depending on how you started it. The first version of
# this parser knew only one of them and reported "35 events" for the other.
#
# A. codex app-server (goals). Slashed names, payload under params:
#   item/started, item/completed    params.item {type, id, ...}
#   item/agentMessage/delta         params {itemId, delta}  one word at a time,
#                                   reassembled per itemId
#   turn/diff/updated               params.diff, a unified diff of the turn
#   thread/tokenUsage/updated       params.tokenUsage.total.totalTokens
#                                   NOT params.usage.total_tokens
#   thread/goal/updated             params.goal {status, tokensUsed, ...}
#   mcpServer/startupStatus/updated startup noise. Ignored deliberately.
#
# B. codex exec --json (briefs). DOTTED names, payload at TOP LEVEL:
#   item.started, item.completed    item {id, type, text, command, status}
#                                   item.type agent_message carries whole text
#                                   in item.text, not deltas
#   thread.started, turn.started
#
# Normalising "." to "/" and falling back from params to the message itself
# makes one parser serve both. Unrecognised shapes still fall back to event
# count: a progress line that lies about what an agent is doing is worse than a
# spinner.

# shellcheck source=duet-common.sh
# Locate siblings via DUET_ROOT, never via BASH_SOURCE alone.
#
# BASH_SOURCE IS EMPTY UNDER ZSH, which is the default shell on macOS and the
# one Claude Code's Bash tool runs. `dirname ""` yields ".", so every sibling
# source became ./duet-x.sh and failed. That made the whole goal path
# unreachable from the very shell the skills tell the orchestrator to use, and
# it survived every test that happened to run under `bash -c`.
: "${DUET_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
. "$DUET_ROOT/lib/duet-common.sh"
. "$DUET_ROOT/lib/duet-window.sh"
. "$DUET_ROOT/lib/duet-models.sh"

duet_progress_mode () { duet_cfg progress.mode heartbeat; }

# ---------- reading the stream ----------------------------------------------
# One line describing the most recent thing that happened. No model call, so
# calling this costs nothing and it can run as often as you like.

duet_progress_snapshot () {   # <jsonl file>
  local f="$1"
  [ -s "$f" ] || { printf 'starting'; return; }
  python3 - "$f" <<'PY'
import json, sys, os

path = sys.argv[1]
IGNORE_PREFIX = ("mcpServer/", "remoteControl/")   # startup chatter, not work

activity = None      # what it is doing right now
saying = {}          # itemId -> accumulated streamed text
last_item = None
tokens = 0
files = set()
status = None
n = 0

def describe(item):
    """A short label for a work item, whatever shape it turns out to be."""
    if not isinstance(item, dict):
        return None
    t = item.get("type") or "working"
    for key in ("command", "path", "file", "query", "url", "name"):
        v = item.get(key)
        if isinstance(v, list):
            v = " ".join(str(x) for x in v)
        if isinstance(v, str) and v.strip():
            return f"{t}: {' '.join(v.split())}"
    return str(t)

try:
    with open(path, errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                m = json.loads(line)
            except Exception:
                continue
            n += 1
            if not isinstance(m, dict):
                continue
            # TWO STREAM SHAPES, both real, and they are not the same:
            #   codex app-server  "method":"item/started",  payload under params
            #   codex exec --json "type":"item.completed",  payload at top level
            # Normalising the separator and falling back to the message itself
            # makes one parser serve both. Before this, the exec path fell all
            # the way through to "35 events", which was honest and useless.
            method = (m.get("method") or m.get("type") or "").replace(".", "/")
            if method.startswith(IGNORE_PREFIX):
                continue
            p = m.get("params") if isinstance(m.get("params"), dict) else m

            if method in ("item/started", "item/completed"):
                item = p.get("item") if isinstance(p.get("item"), dict) else None
                if item:
                    # exec carries whole agent messages rather than deltas
                    if item.get("type") == "agent_message" and isinstance(item.get("text"), str):
                        saying[item.get("id") or f"i{n}"] = item["text"]
                    elif method == "item/started":
                        last_item = describe(item)
                        activity = last_item
            elif method == "item/agentMessage/delta":
                iid = p.get("itemId") or "_"
                saying[iid] = saying.get(iid, "") + (p.get("delta") or "")
            elif method == "turn/diff/updated":
                for ln in (p.get("diff") or "").splitlines():
                    if ln.startswith("+++ b/"):
                        files.add(ln[6:])
            elif method == "thread/tokenUsage/updated":
                tu = (p.get("tokenUsage") or {}).get("total") or {}
                tokens = max(tokens, int(tu.get("totalTokens") or 0))
            elif method == "thread/goal/updated":
                status = ((p.get("goal") or {}).get("status") or None)
except Exception:
    pass

# What it is saying beats what kind of item it is, when there is any.
text = " ".join(saying[max(saying, key=lambda k: len(saying[k]))].split()) if saying else ""
label = text or activity or (f"{n} events" if n else "working")
if len(label) > 58:
    label = label[:55] + "..."

bits = [label]
if files:
    bits.append(f"{len(files)} file{'s' if len(files) != 1 else ''}")
if tokens:
    # CONTEXT processed, which includes cached input, not the goal's own
    # tokensUsed. Labelling both "tok" made a real screenshot read as a
    # contradiction: 125.0k next to a goal reporting 20,038.
    bits.append(f"{tokens/1000:.1f}k ctx" if tokens >= 1000 else f"{tokens} ctx")
if status and status.lower() != "active":
    bits.append(status)
print(" · ".join(bits))
PY
}

# The agent's own words, for digest to condense. Reading this is free; the
# condensing is the part that costs, which is why digest is the mode setup warns
# about.
#
# This looked for text/message/content until 0.4.0 and therefore found NOTHING
# in a real Codex stream, where agent text arrives one word at a time as
# params.delta on item/agentMessage/delta and has to be reassembled per itemId.
# Digest was calling this, getting an empty string, and silently returning. The
# mode looked implemented and did nothing.
duet_progress_excerpt () {   # <jsonl file> [count]
  local f="$1" n="${2:-3}"
  [ -s "$f" ] || return 0
  python3 - "$f" "$n" <<'PY'
import json, sys
path, want = sys.argv[1], int(sys.argv[2])
order, msgs = [], {}

def add(key, text):
    if key not in msgs:
        msgs[key] = ""
        order.append(key)
    msgs[key] += text

try:
    with open(path, errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                m = json.loads(line)
            except Exception:
                continue
            if not isinstance(m, dict):
                continue
            # Both stream shapes; see duet_progress_snapshot for why.
            method = (m.get("method") or m.get("type") or "").replace(".", "/")
            p = m.get("params") if isinstance(m.get("params"), dict) else m

            # exec --json delivers whole agent messages under item.text
            item0 = p.get("item") if isinstance(p.get("item"), dict) else None
            if item0 and item0.get("type") == "agent_message" and isinstance(item0.get("text"), str):
                add(item0.get("id") or f"m{len(order)}", item0["text"])
                continue

            # app-server streams the same text one fragment at a time.
            if method == "item/agentMessage/delta":
                d = p.get("delta")
                if isinstance(d, str):
                    add(p.get("itemId") or "_", d)
                continue

            # Completed items and any other whole-text shapes.
            item = p.get("item") if isinstance(p.get("item"), dict) else {}
            for src in (item, p):
                for key in ("text", "message", "content"):
                    v = src.get(key)
                    if isinstance(v, list):
                        v = " ".join(b.get("text", "") for b in v
                                     if isinstance(b, dict) and isinstance(b.get("text"), str))
                    if isinstance(v, str) and len(v.strip()) > 40:
                        add(f"{method}:{id(src)}:{len(order)}", " ".join(v.split()))
                        break
except Exception:
    pass

out = [" ".join(msgs[k].split()) for k in order if len(msgs[k].strip()) > 40]
for t in out[-want:]:
    print(t[:400])
PY
}

# ---------- the heartbeat ---------------------------------------------------
# Prints one line per interval while the given pid lives. Backgrounded by the
# caller; returns the watcher pid so it can be stopped.

# ---------- digest ----------------------------------------------------------
# The heartbeat is free because it only reads a file. Digest is the mode that
# actually costs something, and it has to, or the setup question warning about
# quota would be false.
#
# Deliberately cheap: haiku at low effort over a few hundred characters, once
# every five minutes. That is a rounding error next to the model doing the work,
# and it is a real call, which is what makes digest and heartbeat honestly
# different rather than two names for the same thing.

duet_progress_digest () {   # <jsonl file> ; up to two lines on stderr
  local f="$1" excerpt out
  duet_has claude || return 0
  excerpt="$(duet_progress_excerpt "$f" 4)"
  [ -z "$excerpt" ] && return 0
  out="$(printf 'Condense this agent transcript into exactly two lines. Line one: what it has finished. Line two: what it is doing now. No preamble, no bullets, no more than 90 characters a line.\n\n%s\n' "$excerpt" \
    | CLAUDE_CODE_EFFORT_LEVEL= claude -p --model haiku --effort low 2>/dev/null)"
  [ -z "$out" ] && return 0
  printf '%s\n' "$out" | head -2 | sed 's/^/      /' >&2
}

duet_progress_watch () {   # <jsonl file> <label> <pid> [interval] ; echoes watcher pid
  local f="$1" label="$2" pid="$3" iv="${4:-60}" mode dg
  mode="$(duet_progress_mode)"
  case "$mode" in off) return 0 ;; esac

  # window used to return here, which meant choosing the most visible mode
  # bought silence: the heartbeat was suppressed and nothing ever called
  # duet_window_open. It opens the viewer AND keeps a slow heartbeat, so
  # closing the window does not blind the run.
  if [ "$mode" = "window" ]; then
    duet_window_open "$f" "$label${DUET_STAGE_LABEL:+ · $DUET_STAGE_LABEL}" \
      "$(dirname "$f")" "$(duet_codex_model 2>/dev/null)" || true
    iv=$(( iv * 3 ))
  fi
  dg="$(duet_cfg progress.digestEverySec 300)"
  (
    waited=0        # subshell scope, so no `local` and no leak into the caller
    since_digest=0
    while kill -0 "$pid" 2>/dev/null; do
      sleep "$iv"
      kill -0 "$pid" 2>/dev/null || break
      waited=$((waited + iv))
      printf '  %s · %s · %s\n' "$label" "$(duet_progress_fmt "$waited")" \
        "$(duet_progress_snapshot "$f")" >&2
      if [ "$mode" = "digest" ]; then
        since_digest=$((since_digest + iv))
        if [ "$since_digest" -ge "$dg" ]; then
          since_digest=0
          duet_progress_digest "$f"
        fi
      fi
    done
  ) &
  printf '%s' "$!"
}

duet_progress_stop () { [ -n "${1:-}" ] && kill "$1" 2>/dev/null; return 0; }

duet_progress_fmt () {   # <seconds> -> 2m10s
  local s="$1"
  if [ "$s" -ge 60 ]; then printf '%dm%02ds' $((s / 60)) $((s % 60)); else printf '%ds' "$s"; fi
}
