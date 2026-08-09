#!/usr/bin/env bash
# The run directory. Files are the source of truth; GitHub is a projection of
# them, not the other way round. (issues #10, #26)
#
#   .duet/runs/<run-id>/
#     plan.json          phases: owner, kind, inputs, outputs, done-condition, status
#     phases/<n>/in.md   the briefing handed to that phase's owner
#     phases/<n>/out.*   that phase's result, written ATOMICALLY
#     assumptions.md     intent calls made on the human's behalf
#     ledger.json        spend, accumulated as we go
#     questions.json     accumulating for the single final round
#
# Outputs are atomic (temp + rename), so a partial write is indistinguishable
# from an absent one. That deletes the "half-written phase" problem instead of
# trying to detect it, and it is what makes resume a two-line rule.

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

duet_run_root () { printf '%s/.duet/runs' "${DUET_PROJECT:-$PWD}"; }

duet_run_new () {
  local id dir
  id="$(date -u +%Y%m%dT%H%M%SZ)-$(duet_uuid | cut -c1-8)"
  dir="$(duet_run_root)/$id"
  mkdir -p "$dir/phases"
  printf '{"runId":"%s","version":"%s","phases":[],"status":"planning"}\n' \
    "$id" "$DUET_VERSION" | duet_write_atomic "$dir/plan.json"
  printf '[]\n' | duet_write_atomic "$dir/questions.json"
  printf '{"phases":[],"totalUsd":0}\n' | duet_write_atomic "$dir/ledger.json"
  : > "$dir/assumptions.md"
  printf '%s' "$dir"
}

duet_run_latest () { ls -1d "$(duet_run_root)"/*/ 2>/dev/null | sort | tail -1 | sed 's:/$::'; }

# A phase is complete iff its output file exists. Because writes are atomic,
# that single test is sufficient; there is no partial state to reason about.
duet_phase_done () { [ -s "$1/phases/$2/out.md" ]; }

# The resume point: the first phase without a completed output. Everything
# before it stands. The plan itself is NOT regenerated, because re-planning
# would invalidate work that already succeeded.
duet_run_resume_point () {
  local dir="$1" n
  n="$(python3 - "$dir/plan.json" <<'PY'
import json,sys
try: print(len(json.load(open(sys.argv[1])).get("phases",[])))
except Exception: print(0)
PY
)"
  local i=0
  while [ "$i" -lt "$n" ]; do
    duet_phase_done "$dir" "$i" || { printf '%s' "$i"; return; }
    i=$((i+1))
  done
  printf '%s' "$n"
}

# Research goes stale. Resuming a week-old run against week-old dependency facts
# would reintroduce exactly the staleness Duet exists to prevent.
duet_run_stale () {
  local dir="$1" max_h; max_h="$(duet_cfg resume.researchMaxAgeHours 24)"
  local mtime now age
  mtime="$(python3 -c 'import os,sys;print(int(os.path.getmtime(sys.argv[1])))' "$dir/plan.json" 2>/dev/null || echo 0)"
  now="$(date +%s)"; age=$(( (now - mtime) / 3600 ))
  [ "$age" -ge "$max_h" ]
}

duet_question_add () {   # <run-dir> <question> <recommendation> <why>
  python3 - "$1/questions.json" "$2" "$3" "$4" <<'PY'
import json,sys
p,q,rec,why=sys.argv[1:5]
try: d=json.load(open(p))
except Exception: d=[]
if not any(x.get("q")==q for x in d):        # dedupe, they accumulate all run
    d.append({"q":q,"recommend":rec,"why":why})
json.dump(d,open(p,'w'),indent=2); open(p,'a').write("\n")
PY
}

duet_assume () {   # <run-dir> <what> <why>
  printf -- '- **%s**\n  Why: %s\n' "$2" "$3" >> "$1/assumptions.md"
}

# ---------- the stop-list ---------------------------------------------------
# Things a diff cannot undo. Everything else an agent does can be read and
# reverted afterwards, which is why the list is short: a long stop-list gets
# switched off wholesale, and a short one survives.
#
# Two behaviours over one list, chosen at setup:
#
#   ask-now         hit one, stop, ask, wait. The safe default.
#   defer-to-final  never stop. Do NOT perform the action, queue it for the
#                   final round with the exact command, and carry on with
#                   everything else.
#
# defer-to-final is what max allowance uses. It is not a weaker guard, it is the
# same guard without the interruption: the action still does not happen until a
# human says so, but nobody's afternoon is spent watching for a prompt.

duet_safety_listed () {   # <action id> ; 0 if it is on the stop-list
  local action="$1" list
  list="$(duet_cfg safety.alwaysAsk "push-to-main,production-data,delete-outside-tree")"
  case ",$list," in *",$action,"*) return 0 ;; *) return 1 ;; esac
}

# duet_safety_gate <run-dir> <action id> <the exact command> <why it is wanted>
#   0  allowed, go ahead
#   1  must ask now, and the caller stops
#   2  deferred to the final round, and the caller carries on WITHOUT doing it
duet_safety_gate () {
  local dir="$1" action="$2" cmd="$3" why="$4"
  duet_safety_listed "$action" || return 0
  if [ "$(duet_cfg safety.mode ask-now)" = "defer-to-final" ]; then
    duet_defer_add "$dir" "$action" "$cmd" "$why"
    duet_warn "held for the final round: $action"
    return 2
  fi
  return 1
}

# A deferred action is a final-round question that happens to carry a command,
# so it lives in questions.json rather than a second file nobody would read.
duet_defer_add () {   # <run-dir> <action> <command> <why>
  python3 - "$1/questions.json" "$2" "$3" "$4" <<'PY'
import json,sys
p,action,cmd,why=sys.argv[1:5]
try: d=json.load(open(p))
except Exception: d=[]
q=f"Run this now? ({action})"
if not any(x.get("q")==q and x.get("cmd")==cmd for x in d):
    d.append({"q":q,"cmd":cmd,"recommend":"yes, if the work above is right","why":why,
              "kind":"deferred-action"})
json.dump(d,open(p,'w'),indent=2); open(p,'a').write("\n")
PY
}
