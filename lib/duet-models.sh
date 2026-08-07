#!/usr/bin/env bash
# Model selection: always a strong reasoning model, never a hardcoded name.
# (issue #13)
#
# Neither platform's default is safe. Claude Code defaults to Sonnet on Pro
# seats; Codex's top-priority model ships default_reasoning_level "low". Taking
# the default would hand us the weak research pass this whole tool exists to
# prevent, so Duet never takes it.
#
# And selection is not proof: both platforms silently downgrade. So we verify
# afterwards too.

# shellcheck source=duet-common.sh
. "$(dirname "${BASH_SOURCE[0]}")/duet-common.sh"

# ---------- Claude ----------------------------------------------------------
# Tier aliases are documented to track the newest model over time, which is the
# whole no-hardcoding requirement solved in one flag.

duet_claude_model  () { duet_cfg models.claude.model  "best"; }
duet_claude_effort () { duet_cfg models.claude.effort "high"; }

# ---------- Codex -----------------------------------------------------------
# No aliases exist, so discover at runtime. Rank effort by ARRAY POSITION in the
# model's own advertised list, never a name-to-rank map: OpenAI's own SDK
# example does exactly this and ships two copyable bugs, a rank dict that throws
# on "max"/"ultra" and a lexicographic model sort.

# `codex debug models` renders the raw catalog as JSON on stdout. There is no
# --json flag. --bundled skips the network refresh and dumps what shipped with
# the binary, which is the right fallback when offline.
duet_codex_catalog () { codex debug models 2>/dev/null || codex debug models --bundled 2>/dev/null; }

# Catalog shape, verified against codex-cli 0.146.1:
#   slug                       the model id. NOT "id" and NOT "name".
#   priority                   lower is higher priority
#   visibility                 "list" (selectable) or "hide"
#   supported_reasoning_levels [{effort, description}, ...] in ascending order
#   default_reasoning_level    which is why we never take the default: the
#                              priority-1 model ships "low"
# NOTE: the catalog goes in as a FILE, not a pipe. `python3 - <<'PY'` makes the
# heredoc the program, so anything piped in is swallowed as source and stdin is
# already at EOF by the time the script runs.
duet_codex_model () {
  local override tmp out; override="$(duet_cfg models.codex.model "")"
  [ -n "$override" ] && { printf '%s' "$override"; return; }
  tmp="$(mktemp)"; duet_codex_catalog > "$tmp"
  out="$(python3 - "$tmp" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
models = d.get("models") if isinstance(d,dict) else d
if not isinstance(models,list) or not models: sys.exit(0)
vis=[m for m in models if m.get("visibility")=="list"] or models
vis.sort(key=lambda m: m.get("priority", 10**9))
print(vis[0].get("slug",""))
PY
)"
  rm -f "$tmp"; printf '%s' "$out"
}

# Effort is ranked by POSITION in the model's own advertised list, never by a
# name-to-rank map. OpenAI's own SDK example does this task with a rank dict
# that raises KeyError on "max" and "ultra", and it is very copyable.
#
# Default target is xhigh rather than the maximum. The top level on some models
# is "ultra", described as "maximum reasoning with automatic task delegation",
# and an agent that spawns its own helpers would run outside Duet's parallel
# cap. Configurable for anyone who wants it.
duet_codex_effort () {
  local override model target
  override="$(duet_cfg models.codex.effort "")"
  [ -n "$override" ] && { printf '%s' "$override"; return; }
  model="$1"; target="$(duet_cfg models.codex.effortTarget xhigh)"
  local tmp out; tmp="$(mktemp)"; duet_codex_catalog > "$tmp"
  out="$(python3 - "$tmp" "$model" "$target" <<'PY'
import json,sys
path, want, target = sys.argv[1], sys.argv[2], sys.argv[3]
try: d=json.load(open(path))
except Exception: print("high"); sys.exit(0)
models = d.get("models") if isinstance(d,dict) else d
m = next((x for x in models if x.get("slug")==want), None) if isinstance(models,list) else None
levels = [l.get("effort") for l in (m or {}).get("supported_reasoning_levels") or [] if l.get("effort")]
if not levels: print("high"); sys.exit(0)
# take the target when offered, otherwise the strongest available BY POSITION
print(target if target in levels else levels[-1])
PY
)"
  rm -f "$tmp"; printf '%s' "$out"
}

# ---------- verification ----------------------------------------------------
# Claude reports the served model in its JSON. Codex does NOT emit a model id in
# exec --json at all; it is only recoverable from the rollout's
# turn_context.model, which is why Duet must never pass --ephemeral.

duet_verify_claude_model () {   # <path to claude --output-format json output>
  python3 - "$1" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: print("unknown"); sys.exit(0)
usage=d.get("modelUsage") or {}
if len(usage)>1: print("SWITCHED:"+",".join(usage.keys())); sys.exit(0)
print(next(iter(usage), d.get("model","unknown")))
PY
}

# Fail loudly rather than degrade silently. Accepting a quiet downgrade here
# would make Duet an instance of the problem it was built to solve.
duet_require_strong () {   # <served-model-description>
  case "$1" in
    unknown) duet_warn "could not confirm which model served this phase" ; return 0 ;;
    SWITCHED:*) duet_err "model switched mid-run: ${1#SWITCHED:}"; return 1 ;;
    *haiku*|*mini*|*luna*|*nano*)
      duet_err "phase was served by a small model ($1), refusing to treat it as research"
      return 1 ;;
  esac
  return 0
}
