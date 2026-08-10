#!/usr/bin/env bash
# Presets: the stages that are NOT generated per task.
#
# Duet's default is to generate phases for the task at hand, and that is right
# for "add rate limiting to the API". It is wrong for "build me an app", where
# the shape is known in advance, the order matters, and inventing it fresh each
# time means the agents cannot say where they are. So the four common jobs get a
# fixed stage list, held as data in reference/presets/.
#
# Fixed buys three things:
#   the human always sees [4/13] and knows what is left
#   an agent resuming mid-run locates itself by index, not by inference
#   a stage cannot be quietly skipped, because a missing number is visible
#
# The stages are hardcoded. What happens inside one is not.

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

duet_preset_file () { printf '%s/reference/presets/%s.json' "$DUET_ROOT" "$1"; }

duet_preset_list () {
  local f
  for f in "$DUET_ROOT"/reference/presets/*.json; do
    [ -f "$f" ] || continue
    python3 - "$f" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(f"  {d['preset']:<9} {len(d['stages']):>2} stages   {d['plain']}")
PY
  done
}

duet_preset_show () {   # <preset> [current-stage-index]
  local p="$1" cur="${2:--1}" f
  f="$(duet_preset_file "$p")"
  [ -f "$f" ] || duet_die "no such preset: $p (try: duet presets)"
  python3 - "$f" "$cur" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); cur = int(sys.argv[2])
n = len(d["stages"])
w = len(str(n))
for i, s in enumerate(d["stages"], 1):
    mark = ">" if i == cur else ("x" if i < cur else " ")
    gate = "   <- you answer here" if s.get("gate") == "user" else ""
    idx = f"[{i:>{w}}/{n}]"
    print(f" {mark} {idx} {s['title']:<22} {s['owner']:<6} {s['plain']}{gate}")
PY
}

# The banner. One line, printed on every transition, and the only thing that
# tells the human how much is left.
duet_preset_banner () {   # <preset> <stage-index, 1 based>
  local p="$1" i="$2" f
  f="$(duet_preset_file "$p")"
  python3 - "$f" "$i" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); i = int(sys.argv[2])
n = len(d["stages"])
s = d["stages"][i - 1] if 1 <= i <= n else None
print(f"[{i}/{n}] {s['title']}" if s else f"[{i}/{n}]")
PY
}

# One stage as shell-evaluable assignments, so a skill can read title, owner,
# gate and done-condition without re-parsing JSON in three places.
duet_preset_stage () {   # <preset> <index, 1 based>
  local p="$1" i="$2" f
  f="$(duet_preset_file "$p")"
  python3 - "$f" "$i" <<'PY'
import json, shlex, sys
d = json.load(open(sys.argv[1])); i = int(sys.argv[2])
if not (1 <= i <= len(d["stages"])):
    sys.exit(1)
s = d["stages"][i - 1]
for k in ("id", "title", "plain", "owner", "gate", "done"):
    print(f"DUET_STAGE_{k.upper()}={shlex.quote(str(s.get(k, '')))}")
print(f"DUET_STAGE_COUNT={len(d['stages'])}")
PY
}

# How many questions this preset asks, and where.
#
# Everything needed is already in the JSON: gate == "user" stages, also_ask
# entries, and whether a grill stage exists. Nothing surfaced it, which is why
# setup could only ever promise its own ten.
duet_preset_questions () {   # <preset>
  local p="$1" f; f="$(duet_preset_file "$p")"
  [ -f "$f" ] || duet_die "no such preset: $p"
  python3 - "$f" <<'PY2'
import json,sys
d=json.load(open(sys.argv[1])); st=d["stages"]
gates=[(i,s) for i,s in enumerate(st,1) if s.get("gate")=="user"]
also=sum(len(s.get("also_ask",[])) for s in st)
fixed=len(gates)+also
grill=[i for i,s in gates if s["id"]=="grill"]
where=", ".join(str(i) for i,_ in gates)
print(f"  duet-{d['preset']}, {len(st)} stages")
print(f"    {fixed} questions, at stage{'s' if len(gates)!=1 else ''} {where}")
if grill:
    print(f"    stage {grill[0]} is grilling and has no fixed count. The real number")
    print( "    is stated before it starts, not discovered while it runs")
if any(s["id"]=="readback" for _,s in gates):
    print("    stage 1 may add a few: every unknown worth asking becomes its own question")
lig=d.get("last_intent_gate")
if lig: print(f"    nothing asks you after stage {lig} until the final round")
print(f"FIXED={fixed}")
PY2
}

# Resolve a stage's gate command into something runnable.
#
#   {{cmd.test}}  ->  commands.test from .duet/config.json
#   {{out}}       ->  the phase output path
#
# An UNRESOLVED placeholder must never quietly disappear. Substituting an empty
# string turns `{{cmd.test}} && {{cmd.lint}}` into ` && lint`, which is either a
# syntax error or, worse, a gate that passes because there was nothing to fail.
# So an unset command resolves to a command that fails and says why, and the
# function returns non-zero so the caller can record it as outstanding rather
# than as done (reference/definition-of-done.md).
duet_gate_resolve () {   # <gate_cmd> [out-path] ; echoes the resolved command
  local cmd="$1" out="${2:-}" missing=0 key val
  [ -z "$cmd" ] && return 0

  # Substitute by iterating KNOWN KEYS rather than by regex.
  #
  # The regex version used ${BASH_REMATCH[1]}, which under zsh holds the WHOLE
  # match rather than the first group. The placeholder was therefore never
  # consumed and the while loop span forever, in the exact shell Claude Code's
  # Bash tool runs. A hang is the worst failure shape available: no error, no
  # output, and the human kills the run believing the model is thinking.
  for key in install dev build test lint typecheck deploy start migrate; do
    case "$cmd" in
      *"{{cmd.$key}}"*)
        val="$(duet_cfg "commands.$key" "")"
        if [ -z "$val" ]; then
          val="{ echo 'gate needs commands.$key, which is not configured'; false; }"
          missing=1
        fi
        cmd="${cmd//\{\{cmd.$key\}\}/$val}"
        ;;
    esac
  done

  # Anything still unsubstituted is a key nobody knows about. Say so rather than
  # handing a literal {{cmd.whatever}} to the shell.
  case "$cmd" in
    *"{{cmd."*)
      cmd="{ echo 'gate references an unknown command placeholder'; false; }"
      missing=1 ;;
  esac

  # Same trap, different placeholder, and this one is worse: an empty {{out}}
  # turns `test -s {{out}}` into `test -s`, which is a one-argument test of a
  # non-empty string and therefore TRUE. The gate would pass because there was
  # nothing to check. Substitute something that fails instead.
  case "$cmd" in
    *"{{out}}"*)
      if [ -n "$out" ]; then
        cmd="${cmd//\{\{out\}\}/$out}"
      else
        cmd="{ echo 'gate needs the phase output path, which was not supplied'; false; }"
        missing=1
      fi ;;
  esac

  printf '%s' "$cmd"
  return $missing
}

# Seed a run directory from a preset, so resume works by stage index and the
# plan the human approved is the plan on disk.
duet_preset_seed () {   # <run-dir> <preset>
  local dir="$1" p="$2" f
  f="$(duet_preset_file "$p")"
  [ -f "$f" ] || duet_die "no such preset: $p"
  python3 - "$f" "$dir" <<'PY'
import json, os, sys
src, dir = sys.argv[1], sys.argv[2]
d = json.load(open(src))
plan = json.load(open(os.path.join(dir, "plan.json")))
plan["preset"] = d["preset"]
plan["phases"] = [
    {"n": i, "id": s["id"], "title": s["title"], "owner": s["owner"],
     "gate": s.get("gate", "none"), "done": s.get("done", ""), "status": "pending"}
    for i, s in enumerate(d["stages"], 1)
]
tmp = os.path.join(dir, "plan.json.tmp")
json.dump(plan, open(tmp, "w"), indent=2)
os.replace(tmp, os.path.join(dir, "plan.json"))
print(len(plan["phases"]))
PY
}
