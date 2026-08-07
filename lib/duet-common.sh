#!/usr/bin/env bash
# Duet shared helpers. Source this, do not execute it.
#
# Everything here is deliberately dependency free: bash, coreutils, and the two
# CLIs. A tool that lints other people's dependency hygiene should not arrive
# with a pile of its own.

DUET_VERSION="0.1.0"
DUET_ROOT="${DUET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DUET_MAX_AGENTS_CEILING=10          # never raisable, see issue #21
DUET_MAX_AGENTS_DEFAULT=3

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

# Concurrency ceiling. A user may lower it; nothing may raise it past the
# ceiling, because the point is protecting their rate limits, not ours.
duet_max_agents () {
  local want; want="$(duet_cfg agents.max "$DUET_MAX_AGENTS_DEFAULT")"
  case "$want" in ''|*[!0-9]*) want="$DUET_MAX_AGENTS_DEFAULT" ;; esac
  [ "$want" -lt 1 ] && want=1
  [ "$want" -gt "$DUET_MAX_AGENTS_CEILING" ] && want="$DUET_MAX_AGENTS_CEILING"
  printf '%s' "$want"
}
