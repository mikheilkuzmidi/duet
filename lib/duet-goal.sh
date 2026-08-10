#!/usr/bin/env bash
# Goals: why a delegated task comes back finished instead of half built.
#
# A prompt ends when the model stops talking. A goal ends when its status
# reaches `complete`. That is the entire difference, and it is the difference
# between an app and most of an app.
#
# ---------------------------------------------------------------------------
# VERIFIED, on codex-cli with `goals` at stage stable, by generating the
# server's own schema and then driving it live. Not recalled, not assumed.
#
#   $ codex features list | grep goals
#   goals                                stable             true
#
#   $ codex app-server generate-json-schema --out DIR
#
# Methods (v2 protocol, JSON-RPC 2.0):
#   thread/start        params {cwd, model, sandbox, approvalPolicy,
#                               developerInstructions, baseInstructions, ...}
#                       result {thread: {id, sessionId, ...}}
#                       NOTE the id is at result.thread.id, NOT result.threadId
#   thread/goal/set     params {threadId (required), objective, status,
#                               tokenBudget}
#                       result {goal: ThreadGoal}
#   thread/goal/get     params {threadId} -> {goal: ThreadGoal | null}
#   thread/goal/clear   params {threadId}
#   turn/start          params {threadId (required), input (required array),
#                               model, effort, sandboxPolicy, cwd}
#                       input items are {type:"text", text:"..."}
#
# Notifications: thread/goal/updated, thread/goal/cleared, turn/started,
#   turn/completed, thread/started, account/rateLimits/updated
#
# ThreadGoal: {threadId, objective, status, tokenBudget, tokensUsed,
#              timeUsedSeconds, createdAt, updatedAt}
#
# ThreadGoalStatus, and this is a trap: the WIRE form is camelCase
#   active | paused | blocked | usageLimited | budgetLimited | complete
# while ~/.codex/goals_1.sqlite stores the same states snake_case
#   active | paused | blocked | usage_limited | budget_limited | complete
# Match on both or you will silently never detect a usage limit.
#
# Enums that must be exact, because a wrong one hangs rather than errors:
#   AskForApproval  untrusted | on-request | never | {granular:{...}}
#   SandboxMode     read-only | workspace-write | danger-full-access
#
# TRANSPORT IS STDIO, not websockets. `codex app-server` defaults to stdio://
# and speaks newline-delimited JSON-RPC on the pipe. duet-window.sh uses ws://
# because it needs a socket a second terminal can attach to; goals need no such
# thing, so they cost no extra dependency. `pip install websockets` is required
# for the visible window and for nothing else.
#
# THE OBJECTIVE IS CAPPED AT 4000 CHARACTERS. Verified the hard way, by sending
# 9,237 and receiving:
#   {"error":{"code":-32600,"message":"goal objective must be at most 4000 characters"}}
# It is in no documentation this repo could find. That cap is WHY the briefing
# belongs in developerInstructions on thread/start and only the objective goes
# into thread/goal/set: a briefing is thousands of characters and an objective
# is a paragraph. Duet refuses over-long objectives rather than truncating,
# because the exit gate lives at the END of the block and a truncated objective
# would silently lose the one line that decides when the work is done.
#
# OBSERVED, once, and therefore handled rather than relied upon: setting a goal
# appeared to start a turn on its own. So this waits briefly for turn/started
# before starting one itself, which is correct under both behaviours and double
# spends under neither.
# ---------------------------------------------------------------------------

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
. "$DUET_ROOT/lib/duet-models.sh"
. "$DUET_ROOT/lib/duet-progress.sh"

# Exit codes, so a caller can tell "not finished" apart from "cannot finish".
DUET_GOAL_OK=0
DUET_GOAL_ERROR=1
DUET_GOAL_USAGE_LIMITED=75
DUET_GOAL_BUDGET_LIMITED=76
DUET_GOAL_BLOCKED=77
DUET_GOAL_TIMEOUT=78

duet_goal_supported () {
  codex features list 2>/dev/null | awk '$1=="goals"{print $NF}' | grep -q true
}

DUET_GOAL_OBJECTIVE_MAX=4000

# duet_goal_run <objective-file> <cwd> <out.jsonl> [developer-instructions-file]
#
# Streams every notification to out.jsonl in the same shape duet-progress.sh
# already parses, so the heartbeat keeps working unchanged.
duet_goal_run () {
  local obj="$1" cwd="${2:-$PWD}" out="${3:-/dev/stdout}" dev="${4:-}"
  local sandbox model effort budget maxmin maxturns grace

  [ -f "$obj" ] || duet_die "objective file not found: $obj"

  local objlen; objlen=$(wc -c < "$obj" | tr -d ' ')
  if [ "$objlen" -gt "$DUET_GOAL_OBJECTIVE_MAX" ]; then
    duet_err "objective is $objlen characters; the goal API caps it at $DUET_GOAL_OBJECTIVE_MAX."
    duet_err "Put the briefing in the developer-instructions argument, not the objective."
    duet_err "An objective is a paragraph and a gate. See reference/goal-format.md."
    return $DUET_GOAL_ERROR
  fi

  if duet_fastmode 2>/dev/null; then sandbox="danger-full-access"; else sandbox="workspace-write"; fi
  model="$(duet_codex_model)"
  effort="$(duet_codex_effort "$model")"
  budget="$(duet_cfg goal.tokenBudget 0)"
  maxmin="$(duet_cfg goal.maxMinutes 120)"
  maxturns="$(duet_cfg goal.maxTurns 40)"
  grace="$(duet_cfg goal.continueGraceSec 20)"

  duet_say "  codex goal · ${model:-default} · effort ${effort:-default} · $sandbox"

  # A goal runs longer than anything else Duet does, so it is the path that most
  # needs to prove it is alive. The driver streams every protocol line into
  # $out, which is the same file duet_progress_snapshot parses.
  : > "$out"
  local watcher rc
  DUET_HOST=codex python3 "$DUET_ROOT/lib/duet-goal.py" \
    --objective "$obj" \
    --cwd "$cwd" \
    --out "$out" \
    --model "$model" \
    --effort "$effort" \
    --sandbox "$sandbox" \
    --token-budget "$budget" \
    --max-minutes "$maxmin" \
    --max-turns "$maxturns" \
    --continue-grace "$grace" \
    ${dev:+--developer-instructions "$dev"} \
    ${DUET_FASTMODE_APPROVE:+--approve-escalations} &
  local pid=$!
  watcher="$(duet_progress_watch "$out" "codex" "$pid" "$(duet_cfg progress.everySec 60)")"
  wait "$pid"; rc=$?
  duet_progress_stop "$watcher"
  return $rc
}

# Real rate limit state. The README used to say no platform exposes remaining
# plan budget to a tool. For Codex that is false: account/rateLimits/read
# returns usedPercent, the window length, and when it resets.
duet_rate_limits () {
  python3 "$DUET_ROOT/lib/duet-goal.py" --rate-limits-only 2>/dev/null
}

# The ceiling that actually binds on a subscription. Duet used to ask the human
# for a dollar limit it could only half measure; this is the real number and it
# comes from the platform rather than from a guess.
duet_rate_report () {
  local j; j="$(duet_rate_limits)"
  [ -z "$j" ] && { duet_say "  rate limits: unavailable"; return 0; }
  printf '%s' "$j" | python3 -c "
import json,sys,time
try: d=json.load(sys.stdin)
except Exception: print('  rate limits: unreadable'); raise SystemExit
r=(d.get('rateLimits') or {})
p=(r.get('primary') or {})
used=p.get('usedPercent'); reset=p.get('resetsAt'); win=p.get('windowDurationMins')
if used is None: print('  rate limits: none reported'); raise SystemExit
bits=[f'{used}% of the codex window used']
if win: bits.append(f'{int(win)//1440}d window' if win>=1440 else f'{int(win)}m window')
if reset:
    left=int(reset)-int(time.time())
    if left>0: bits.append(f'resets in {left//86400}d {left%86400//3600}h' if left>=86400 else f'resets in {left//3600}h')
plan=r.get('planType')
if plan: bits.append(plan)
print('  ' + ' · '.join(bits))
"
}

duet_goal_explain () {   # <exit code> ; one line, for the human
  case "${1:-}" in
    "$DUET_GOAL_OK")             printf 'complete' ;;
    "$DUET_GOAL_USAGE_LIMITED")  printf 'stopped: usage limit reached. Resume when it resets; do not retry now' ;;
    "$DUET_GOAL_BUDGET_LIMITED") printf 'stopped: token budget spent. Raise goal.tokenBudget and resume' ;;
    "$DUET_GOAL_BLOCKED")        printf 'blocked: the goal cannot proceed without something it does not have' ;;
    "$DUET_GOAL_TIMEOUT")        printf 'stopped: hit goal.maxMinutes. The work so far stands' ;;
    *)                           printf 'failed' ;;
  esac
}
