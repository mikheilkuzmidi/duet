#!/usr/bin/env bash
# How many questions, and which one is this.
#
# Setup used to open with "Ten questions, about two minutes." That was true of
# setup and of nothing else: the preset then ran its own gates, the read-back
# turned unknowns into more questions, and grilling has no cap. A real run
# reached question 17 of an unknown total.
#
# Stating a number and then quietly exceeding it is standing rule 7 applied to
# Duet's own promises, which was the one place the rules were not being applied.
#
# So: state the total before the first question, count every question against
# it, and when the variable part becomes knowable, revise OUT LOUD with the
# delta and the reason. A number silently replaced is worse than no number.

# Locate siblings via DUET_ROOT, never via BASH_SOURCE alone (empty under zsh).
: "${DUET_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
. "$DUET_ROOT/lib/duet-common.sh"
. "$DUET_ROOT/lib/duet-preset.sh"

duet_ask_state () { printf '%s/.duet/asked.json' "${DUET_PROJECT:-$PWD}"; }

# duet_ask_begin <preset|-> <total> [variable]
# `variable` non-empty means part of the total is still an estimate, which is
# what puts the tilde in front of the number.
duet_ask_begin () {
  local preset="${1:--}" total="${2:-0}" variable="${3:-}"
  local f; f="$(duet_ask_state)"
  mkdir -p "$(dirname "$f")"
  python3 - "$f" "$preset" "$total" "$variable" <<'PY'
import json,sys
f,preset,total,variable=sys.argv[1:5]
json.dump({"preset":preset,"total":int(total),"asked":0,
           "variable":bool(variable),"revisions":[]},open(f,'w'),indent=2)
open(f,'a').write("\n")
PY
}

# duet_ask <stage-index> <stage-title> [stage-count]
# Prints the header and counts the question. One call per question asked.
duet_ask () {
  local idx="${1:-}" title="${2:-}" count="${3:-}" f
  f="$(duet_ask_state)"
  [ -f "$f" ] || duet_ask_begin - 0
  [ -z "$count" ] && [ -n "$idx" ] && {
    local p; p="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("preset",""))' "$f" 2>/dev/null)"
    [ -n "$p" ] && [ "$p" != "-" ] && count="$(python3 -c '
import json,sys
print(len(json.load(open(sys.argv[1]))["stages"]))' "$(duet_preset_file "$p")" 2>/dev/null)"
  }
  python3 - "$f" "$idx" "$title" "$count" <<'PY'
import json,sys
f,idx,title,count=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
d=json.load(open(f))
d["asked"]+=1
json.dump(d,open(f,'w'),indent=2); open(f,'a').write("\n")
tot=d.get("total") or 0
approx="~" if d.get("variable") else ""
head=f"[Q {d['asked']} of {approx}{tot}" if tot else f"[Q {d['asked']}"
if idx and count: head+=f" · stage {idx}/{count}"
if title: head+=f" {title}"
print(head+"]")
PY
}

# duet_ask_revise <new total> <why> [still-variable]
# Both directions. A total that only ever grows is one nobody believes.
duet_ask_revise () {
  local total="${1:-0}" why="${2:-}" variable="${3:-}" f
  f="$(duet_ask_state)"
  [ -f "$f" ] || duet_ask_begin - "$total"
  python3 - "$f" "$total" "$why" "$variable" <<'PY'
import json,sys
f,total,why,variable=sys.argv[1:5]
d=json.load(open(f)); old=d.get("total") or 0; new=int(total)
d["total"]=new; d["variable"]=bool(variable)
d.setdefault("revisions",[]).append({"from":old,"to":new,"why":why})
json.dump(d,open(f,'w'),indent=2); open(f,'a').write("\n")
delta=new-old
if delta>0:   print(f"Revised: {new} questions, {delta} more than I said.")
elif delta<0: print(f"Revised: {new} questions, {-delta} fewer than I said.")
else:         print(f"Still {new} questions.")
if why: print(why)
PY
}

duet_ask_report () {
  local f; f="$(duet_ask_state)"
  [ -f "$f" ] || { duet_say "  no questions counted yet"; return 0; }
  python3 - "$f" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
tot=d.get("total") or 0; asked=d.get("asked",0)
approx="~" if d.get("variable") else ""
print(f"  asked {asked} of {approx}{tot}" + (f" · preset {d['preset']}" if d.get("preset") not in ("","-") else ""))
for r in d.get("revisions",[]):
    print(f"    revised {r['from']} -> {r['to']}: {r.get('why','')}")
PY
}
