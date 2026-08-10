#!/usr/bin/env bash
# Spend ledger. (issue #23)
#
# There is NO first-party API for a skill to read remaining plan budget.
# /usage is an interactive TUI, its figures are local-only and approximate, and
# polling it costs tokens. So Duet measures what it can measure exactly, and is
# honest about the rest.
#
# Sources:
#   Claude  total_cost_usd + a per-model breakdown, in every -p --output-format
#           json result. Free and exact.
#   Codex   a live app-server emits thread/tokenUsage/updated and
#           account/rateLimits/updated. Rate limit state IS observable there,
#           which was assumed impossible until the #11 prototype found it.

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

duet_ledger_add_claude () {   # <run-dir> <phase-label> <claude json output>
  python3 - "$1/ledger.json" "$2" "$3" <<'PY'
import json,sys
led,label,src=sys.argv[1:4]
try: d=json.load(open(led))
except Exception: d={"phases":[],"totalUsd":0}
try: r=json.load(open(src))
except Exception: r={}
usd=float(r.get("total_cost_usd") or 0)
d["phases"].append({"phase":label,"agent":"claude","usd":usd,
                    "models":list((r.get("modelUsage") or {}).keys())})
d["totalUsd"]=round(sum(p.get("usd",0) for p in d["phases"]),4)
json.dump(d,open(led,'w'),indent=2); open(led,'a').write("\n")
print(f"{usd:.4f} {d['totalUsd']:.4f}")
PY
}

duet_ledger_add_codex () {   # <run-dir> <phase-label> <codex jsonl output>
  python3 - "$1/ledger.json" "$2" "$3" <<'PY'
import json,sys
led,label,src=sys.argv[1:4]
try: d=json.load(open(led))
except Exception: d={"phases":[],"totalUsd":0}
# Token path, VERIFIED against a live app-server stream:
#   thread/tokenUsage/updated -> params.tokenUsage.total.totalTokens
#   thread/goal/updated       -> params.goal.tokensUsed
# The older guess at params.usage.total_tokens matches neither, so it recorded
# zero for every Codex phase. Both real paths are read, plus the old guess, so
# an exec-shaped stream still works.
tok=0
try:
    for line in open(src):
        line=line.strip()
        if not line: continue
        try: m=json.loads(line)
        except Exception: continue
        p=(m.get("params") or {}) if isinstance(m.get("params"),dict) else {}
        tu=(p.get("tokenUsage") or {}).get("total") or {}
        if isinstance(tu.get("totalTokens"),int): tok=max(tok,tu["totalTokens"])
        g=p.get("goal") or {}
        if isinstance(g.get("tokensUsed"),int): tok=max(tok,g["tokensUsed"])
        u=p.get("usage") or m.get("usage") or {}
        for k in ("total_tokens","totalTokens","total"):
            if isinstance(u.get(k),int): tok=max(tok,u[k])
except Exception: pass
# Codex does not report a dollar figure to the CLI, so we record tokens and say
# so rather than inventing a price.
d["phases"].append({"phase":label,"agent":"codex","tokens":tok,"usd":None})
json.dump(d,open(led,'w'),indent=2); open(led,'a').write("\n")
print(tok)
PY
}

duet_ledger_report () {   # <run-dir>
  python3 - "$1/ledger.json" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
# Say whose money this is. The dollar figure is CLAUDE ONLY, because Codex
# exposes no price to the CLI, and presenting the two together as one total
# would be a number that looks complete and is not.
n=len(d.get('phases',[]))
print(f"  claude spend: ${d.get('totalUsd',0):.4f} across {n} phases")
ct=sum(p.get("tokens") or 0 for p in d.get("phases",[]) if p.get("agent")=="codex")
if ct: print(f"  codex usage : {ct} tokens. No dollar figure exists for it; see `duet goal status` for the rate limit, which is the real ceiling on a subscription.")
PY
}

# A soft threshold warns. The hard stop CHECKPOINTS and exits cleanly rather
# than dying mid-phase, which is what makes it safe to trigger: the run
# directory is left resumable (issue #26).
duet_ledger_guard () {   # <run-dir> ; returns 1 when the run should stop
  local dir="$1" soft hard total
  soft="$(duet_cfg budget.warnUsd 0)"      # 0 means no warning; not asked at setup
  hard="$(duet_cfg budget.stopUsd 0)"      # 0 means no hard stop
  total="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("totalUsd",0))' "$dir/ledger.json" 2>/dev/null || echo 0)"
  awk -v t="$total" -v s="$soft" 'BEGIN{exit !(s>0 && t>=s)}' && \
    duet_warn "spend \$$total has passed the warn threshold \$$soft"
  if awk -v t="$total" -v h="$hard" 'BEGIN{exit !(h>0 && t>=h)}'; then
    duet_err "spend \$$total reached the hard stop \$$hard. Checkpointing."
    duet_err "resume with: duet resume"
    return 1
  fi
  return 0
}
