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
# Locate siblings via DUET_ROOT, never via BASH_SOURCE alone.
#
# BASH_SOURCE IS EMPTY UNDER ZSH, which is the default shell on macOS and the
# one Claude Code's Bash tool runs. `dirname ""` yields ".", so every sibling
# source became ./duet-x.sh and failed. That made the whole goal path
# unreachable from the very shell the skills tell the orchestrator to use, and
# it survived every test that happened to run under `bash -c`.
: "${DUET_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
. "$DUET_ROOT/lib/duet-common.sh"

# ---------- Claude ----------------------------------------------------------
# Tier aliases are documented to track the newest model over time, which is the
# whole no-hardcoding requirement solved in one flag. But WHICH alias matters,
# and the obvious one was wrong.
#
# VERIFIED on claude 2.1.226, by running each alias and reading modelUsage back:
#
#   --model best      -> claude-fable-5      NOT Opus
#   --model opus      -> claude-opus-5        200k context
#   --model opus[1m]  -> claude-opus-5[1m]    1,000,000 context, same model
#
# THE DEFAULT IS opus[1m]. The 1M window is chosen for two phases specifically:
# the rescue preset, where an agent may need a large existing codebase in view
# at once, and any long autonomous goal, where compaction mid-run is the thing
# most likely to lose the plot. Same model, same price per token; you pay only
# for what you actually put in the window.
#
# The docs explain it: `best` means "Fable where your organization has access to
# it, otherwise the latest Opus". So Duet defaulting to `best` was quietly
# selecting a different model from the one its own README described. `opus` is
# the alias that means Opus and still tracks the newest one.
#
# EFFORT. `--effort <level>` takes low, medium, high, xhigh, max. Opus 5
# supports all five. Two things worth knowing:
#
#   `ultracode` is NOT a model and NOT a level above xhigh. It resolves TO
#   xhigh, and adds standing dynamic-workflow orchestration to an interactive
#   session. For a delegated -p call there is nothing to orchestrate, so xhigh
#   is exactly what ultracode would have given you.
#
#   `max` is a real level ABOVE xhigh. Duet does not default to it for the same
#   reason it does not default Codex to `ultra`: cost, and a delegated agent
#   that reasons for minutes at every phase boundary. Set it if you want it.
#
# THE TRAP: CLAUDE_CODE_EFFORT_LEVEL in the environment SILENTLY OVERRIDES the
# --effort flag. A tool that shells out must unset it or it will report one
# effort and get another. duet_delegate_claude does exactly that.

duet_claude_model  () { duet_cfg models.claude.model  "opus[1m]"; }
duet_claude_effort () { duet_cfg models.claude.effort "xhigh"; }

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
# Selection order, which exists to honour a preference without hardcoding into a
# corner:
#
#   1. models.codex.model      an explicit override. Used as given, no checking.
#   2. models.codex.prefer     a preferred slug, USED ONLY IF THE CATALOG STILL
#                              LISTS IT. Default gpt-5.6-terra.
#   3. discovery               highest priority visible model, as before.
#
# Step 2 is the point. Naming a model in config is how a human expresses a
# choice; silently keeping that name after it disappears from the catalog is how
# a tool breaks in a way nobody can read. So the preference is checked against
# the live catalog every time, and a preference that no longer exists degrades
# to discovery and says so.
#
# gpt-5.6-terra VERIFIED present: priority 2, visibility "list",
# supported_in_api true, reasoning levels low/medium/high/xhigh/max/ultra.
duet_codex_model () {
  local override prefer tmp out; override="$(duet_cfg models.codex.model "")"
  [ -n "$override" ] && { printf '%s' "$override"; return; }
  prefer="$(duet_cfg models.codex.prefer "gpt-5.6-terra")"
  tmp="$(mktemp)"; duet_codex_catalog > "$tmp"
  out="$(python3 - "$tmp" "$prefer" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
prefer = sys.argv[2] if len(sys.argv) > 2 else ""
models = d.get("models") if isinstance(d,dict) else d
if not isinstance(models,list) or not models: sys.exit(0)
if prefer and any(m.get("slug") == prefer for m in models):
    print(prefer); sys.exit(0)
vis=[m for m in models if m.get("visibility")=="list"] or models
vis.sort(key=lambda m: m.get("priority", 10**9))
print("FELLBACK", vis[0].get("slug",""))
PY
)"
  rm -f "$tmp"
  case "$out" in
    "FELLBACK "*)
      [ -n "$prefer" ] && duet_warn "codex model '$prefer' is not in the catalog; using ${out#FELLBACK }"
      printf '%s' "${out#FELLBACK }" ;;
    *) printf '%s' "$out" ;;
  esac
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

# A SECOND MODEL IN modelUsage IS NORMAL, and the naive check for it was a false
# positive that would have failed almost every phase. Claude Code runs small
# housekeeping tasks (conversation titles and similar) on Haiku alongside the
# model doing the work, so a healthy run reports two models. Verified: a single
# delegated call returned
#   modelUsage: ["claude-haiku-4-5-20251001", "claude-opus-5"]
# which the old test called "model switched mid-run" and refused.
#
# So: ignore the auxiliary tier, and report the model that did the most work. A
# genuine switch is two SUBSTANTIVE models, which is still worth refusing.
duet_verify_claude_model () {   # <path to claude --output-format json output>
  python3 - "$1" <<'PY'
import json,sys
AUX = ("haiku", "mini", "nano")            # housekeeping tiers, never the worker
try: d=json.load(open(sys.argv[1]))
except Exception: print("unknown"); sys.exit(0)
usage = d.get("modelUsage") or {}
if not usage:
    print(d.get("model","unknown")); sys.exit(0)

def tokens(v):
    if not isinstance(v, dict): return 0
    return sum(x for x in v.values() if isinstance(x, int))

primary = {k: v for k, v in usage.items() if not any(a in k.lower() for a in AUX)}
if len(primary) > 1:
    print("SWITCHED:" + ",".join(primary)); sys.exit(0)
if primary:
    print(next(iter(primary))); sys.exit(0)
# Only auxiliary models ran, which means the work itself was served small.
print(max(usage, key=lambda k: tokens(usage[k])))
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
