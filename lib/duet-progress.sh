#!/usr/bin/env bash
# Showing that the other agent is alive.
#
# A four minute silent phase and a hung process look identical from the outside,
# and the human's reasonable response to both is to kill it. So Duet reports
# liveness, at a level the human chose at setup.
#
# THE SCHEMA, verified against a live app-server goal run rather than assumed.
# Recorded here the way duet-models.sh:34 records the catalog shape, because the
# first version of this parser guessed and surfaced MCP startup chatter as if it
# were the agent's work.
#
#   item/started / item/completed   params.item {type, id, ...}
#                                   type seen: reasoning. Command and file items
#                                   carry their own fields, handled generically.
#   item/agentMessage/delta         params {itemId, delta}  streaming text, one
#                                   word at a time. Accumulate per itemId.
#   turn/diff/updated               params.diff, a unified diff of the turn
#   thread/tokenUsage/updated       params.tokenUsage.total.totalTokens
#                                   NOT params.usage.total_tokens
#   thread/goal/updated             params.goal {status, tokensUsed, ...}
#   mcpServer/startupStatus/updated startup noise. Ignored deliberately.
#
# Unrecognised shapes still fall back to event count and elapsed time. A
# progress line that lies about what an agent is doing is worse than a spinner.

# shellcheck source=duet-common.sh
. "$(dirname "${BASH_SOURCE[0]}")/duet-common.sh"

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
            method = m.get("method") or ""
            if method.startswith(IGNORE_PREFIX):
                continue
            p = m.get("params") if isinstance(m.get("params"), dict) else {}

            if method == "item/started":
                last_item = describe(p.get("item"))
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
    bits.append(f"{tokens/1000:.1f}k tok" if tokens >= 1000 else f"{tokens} tok")
if status and status.lower() != "active":
    bits.append(status)
print(" · ".join(bits))
PY
}

# The last few things the agent said, for the orchestrator to condense in digest
# mode. Reading this is free; the condensing is what costs, which is why it is
# the mode setup warns about.
duet_progress_excerpt () {   # <jsonl file> [count]
  local f="$1" n="${2:-3}"
  [ -s "$f" ] || return 0
  python3 - "$f" "$n" <<'PY'
import json, sys
path, want = sys.argv[1], int(sys.argv[2])
out = []
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
            p = m.get("params") if isinstance(m.get("params"), dict) else m
            for key in ("text", "message", "content"):
                v = p.get(key)
                if isinstance(v, list):
                    v = " ".join(b.get("text", "") for b in v if isinstance(b, dict))
                if isinstance(v, str) and len(v.strip()) > 40:
                    out.append(" ".join(v.split()))
                    break
except Exception:
    pass
for t in out[-want:]:
    print(t[:400])
PY
}

# ---------- the heartbeat ---------------------------------------------------
# Prints one line per interval while the given pid lives. Backgrounded by the
# caller; returns the watcher pid so it can be stopped.

duet_progress_watch () {   # <jsonl file> <label> <pid> [interval] ; echoes watcher pid
  local f="$1" label="$2" pid="$3" iv="${4:-60}"
  case "$(duet_progress_mode)" in off|window) return 0 ;; esac
  (
    waited=0        # subshell scope, so no `local` and no leak into the caller
    while kill -0 "$pid" 2>/dev/null; do
      sleep "$iv"
      kill -0 "$pid" 2>/dev/null || break
      waited=$((waited + iv))
      printf '  %s · %s · %s\n' "$label" "$(duet_progress_fmt "$waited")" \
        "$(duet_progress_snapshot "$f")" >&2
    done
  ) &
  printf '%s' "$!"
}

duet_progress_stop () { [ -n "${1:-}" ] && kill "$1" 2>/dev/null; return 0; }

duet_progress_fmt () {   # <seconds> -> 2m10s
  local s="$1"
  if [ "$s" -ge 60 ]; then printf '%dm%02ds' $((s / 60)) $((s % 60)); else printf '%ds' "$s"; fi
}
