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
. "$(dirname "${BASH_SOURCE[0]}")/duet-common.sh"

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
