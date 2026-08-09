#!/usr/bin/env bash
# Duet shared helpers. Source this, do not execute it.
#
# Everything here is deliberately dependency free: bash, coreutils, and the two
# CLIs. A tool that lints other people's dependency hygiene should not arrive
# with a pile of its own.

DUET_VERSION="0.4.0"
DUET_ROOT="${DUET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DUET_MAX_AGENTS_CEILING=10          # total across both sides, never raisable
DUET_MAX_AGENTS_DEFAULT=3           # legacy total, used when no side cap is set
DUET_SIDE_DEFAULT=2                 # per-side default, chosen at setup

# ---------- output ----------------------------------------------------------
# Everything Duet says goes through here so a caller can silence or capture it.

duet_say  () { printf '%s\n' "$*" >&2; }
duet_step () { printf '\n\033[1m%s\033[0m\n' "$*" >&2; }
duet_ok   () { printf '  \033[32mok\033[0m %s\n' "$*" >&2; }
duet_warn () { printf '  \033[33m!\033[0m  %s\n' "$*" >&2; }
duet_err  () { printf '  \033[31mx\033[0m  %s\n' "$*" >&2; }

duet_die () { duet_err "$*"; exit 1; }

# ---------- config ----------------------------------------------------------
# Global defaults in ~/.config/duet/config.json, optional per-project override
# in .duet/config.json. Nothing is ever written into the user's repo without
# them asking for it (standing rule 6).

duet_config_global () { printf '%s/duet/config.json' "${XDG_CONFIG_HOME:-$HOME/.config}"; }
duet_config_local  () { printf '%s/.duet/config.json' "${DUET_PROJECT:-$PWD}"; }

# duet_cfg <dotted.key> <default>
duet_cfg () {
  local key="$1" def="${2-}" out=""
  for f in "$(duet_config_local)" "$(duet_config_global)"; do
    [ -f "$f" ] || continue
    out=$(python3 - "$f" "$key" <<'PY' 2>/dev/null
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(1)
for part in sys.argv[2].split('.'):
    if not isinstance(d,dict) or part not in d: sys.exit(1)
    d=d[part]
print(d if not isinstance(d,bool) else str(d).lower())
PY
) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  done
  printf '%s' "$def"
}

# duet_cfg_set <dotted.key> <value> [scope=global|local]
duet_cfg_set () {
  local key="$1" val="$2" scope="${3:-global}" f
  [ "$scope" = "local" ] && f="$(duet_config_local)" || f="$(duet_config_global)"
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || printf '{}\n' > "$f"
  python3 - "$f" "$key" "$val" <<'PY'
import json,sys
p,key,val=sys.argv[1],sys.argv[2],sys.argv[3]
d=json.load(open(p))
if val in ("true","false"): val = val=="true"
elif val.isdigit(): val=int(val)
cur=d
parts=key.split('.')
for k in parts[:-1]: cur=cur.setdefault(k,{})
cur[parts[-1]]=val
json.dump(d,open(p,'w'),indent=2)
open(p,'a').write("\n")
PY
}

# ---------- misc ------------------------------------------------------------

duet_uuid () { python3 -c 'import uuid;print(uuid.uuid4())'; }

# Atomic write from stdin. Phase outputs use this so a partial write is
# indistinguishable from absent, which is what makes resume simple (issue #26).
duet_write_atomic () {
  local dest="$1" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp "${dest}.XXXXXX")"
  cat > "$tmp"
  mv -f "$tmp" "$dest"
}

duet_has () { command -v "$1" >/dev/null 2>&1; }

# Em dashes, as a gate rather than a hope. A preset's polish stage calls this,
# so "no em dashes" is checked by a command exiting zero rather than by an agent
# believing it complied. Written as a function because escaping a UTF-8 literal
# through JSON into eval is exactly the kind of thing that silently stops
# matching and reports success forever.
duet_no_emdash () {   # <dir> [extra find args...]
  local dir="${1:-.}"
  local hits
  hits="$(grep -rlF "$(printf '\xe2\x80\x94')" \
            --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
            --include='*.md' --include='*.html' --include='*.css' --include='*.py' \
            --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.duet \
            "$dir" 2>/dev/null)"
  [ -z "$hits" ] && return 0
  duet_err "em dashes found in:"; printf '%s\n' "$hits" | sed 's/^/      /' >&2
  return 1
}

# Path to a reference file, so callers never hand-build DUET_ROOT paths and a
# moved file breaks in one place instead of nine.
duet_ref () { printf '%s/reference/%s' "$DUET_ROOT" "$1"; }

# The reference set injected into EVERY delegated call, in reading order. It is
# re-injected at every phase boundary because prompt text does not survive
# context compaction and a system-prompt file does.
duet_ref_set () {
  printf '%s\n' \
    "$(duet_ref persona.md)" \
    "$(duet_ref standing-rules.md)" \
    "$(duet_ref output-format.md)" \
    "$(duet_ref goal-format.md)" \
    "$(duet_ref definition-of-done.md)"
}

# ---------- the run context -------------------------------------------------
# The reference files are the same for everyone. THIS is the part that differs
# per repo, and until 0.4.0 none of it reached a delegated agent: autonomy,
# voice and the coverage floor were written to .duet/config.json at setup and
# then never told to anybody.
#
# That is a real defect, not a tidiness one. Under autonomy=full an agent must
# never stop to ask, and an agent that was never told cannot comply. It would
# ask, correctly by its own lights, and the run would stall waiting on a human
# who was promised they would not be interrupted.
#
# Generated fresh per call so it cannot go stale, and kept to the settings that
# actually change what an agent does.

duet_context_block () {   # [stage-label] [resolved gate command]
  local stage="${1:-}" gate="${2:-}" a v
  a="$(duet_cfg autonomy product)"
  v="$(duet_cfg voice plain)"

  printf '# This run\n\n'
  case "$a" in
    full)    printf '  autonomy       full. Decide everything. NEVER stop to ask, not even once.\n'
             printf '                 Record what you would have asked and proceed on your own\n'
             printf '                 recommendation, marking the work provisional.\n' ;;
    off)     printf '  autonomy       off. Stop at every decision and wait for the human.\n' ;;
    *)       printf '  autonomy       product. Technical calls are yours alone: schema, API shape,\n'
             printf '                 hosting, dependencies, file layout. Anything that changes what\n'
             printf '                 a person SEES or READS stops and asks: copy, layout, flow,\n'
             printf '                 naming, visual design.\n' ;;
  esac
  case "$v" in
    technical) printf '  voice          technical. Direct, precise, assume they read code.\n' ;;
    *)         printf '  voice          plain. No jargon in anything the human reads. Somebody who\n'
               printf '                 has never opened a terminal must understand it.\n' ;;
  esac
  printf '  coverage floor %s%%\n' "$(duet_cfg done.coverageMin 80)"
  printf '  safety         %s: %s\n' \
    "$(duet_cfg safety.mode ask-now)" \
    "$(duet_cfg safety.alwaysAsk 'push-to-main,production-data,delete-outside-tree')"
  [ -n "$stage" ] && printf '  stage          %s\n' "$stage"
  [ -n "$gate" ]  && printf '  exit gate      %s\n' "$gate"

  local k first=1
  for k in install dev build test lint typecheck deploy; do
    local val; val="$(duet_cfg "commands.$k" "")"
    [ -z "$val" ] && continue
    if [ "$first" = "1" ]; then printf '\n  This project:\n'; first=0; fi
    printf '    %-10s %s\n' "$k" "$val"
  done
  printf '\n'
}

# ---------- concurrency -----------------------------------------------------
# Two pools, one ceiling. Claude and Codex bill against different accounts and
# rate limit independently, so a single shared number could only ever be wrong
# for one of them. The ceiling still applies to the sum, because the thing being
# protected is the human's afternoon, not either vendor's quota.

duet_clamp_int () {   # <value> <default> <max>
  local v="$1" def="$2" max="$3"
  case "$v" in ''|*[!0-9]*) v="$def" ;; esac
  [ "$v" -lt 1 ] && v=1
  [ "$v" -gt "$max" ] && v="$max"
  printf '%s' "$v"
}

# duet_max_agents_for <claude|codex>
duet_max_agents_for () {
  local side="$1" want
  want="$(duet_cfg "agents.${side}.max" "")"
  [ -z "$want" ] && want="$(duet_cfg agents.max "$DUET_SIDE_DEFAULT")"
  duet_clamp_int "$want" "$DUET_SIDE_DEFAULT" "$DUET_MAX_AGENTS_CEILING"
}

# The sum, clamped. Nothing may raise it past the ceiling: a user may lower a
# cap, and no phase may quietly grant itself a bigger budget.
duet_max_agents () {
  local total=$(( $(duet_max_agents_for claude) + $(duet_max_agents_for codex) ))
  [ "$total" -gt "$DUET_MAX_AGENTS_CEILING" ] && total="$DUET_MAX_AGENTS_CEILING"
  printf '%s' "$total"
}
