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
# OBSERVED, once, and therefore handled rather than relied upon: setting a goal
# appeared to start a turn on its own. So this waits briefly for turn/started
# before starting one itself, which is correct under both behaviours and double
# spends under neither.
# ---------------------------------------------------------------------------

# shellcheck source=duet-common.sh
. "$(dirname "${BASH_SOURCE[0]}")/duet-common.sh"
. "$(dirname "${BASH_SOURCE[0]}")/duet-models.sh"
. "$(dirname "${BASH_SOURCE[0]}")/duet-progress.sh"

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

# duet_goal_run <objective-file> <cwd> <out.jsonl> [developer-instructions-file]
#
# Streams every notification to out.jsonl in the same shape duet-progress.sh
# already parses, so the heartbeat keeps working unchanged.
duet_goal_run () {
  local obj="$1" cwd="${2:-$PWD}" out="${3:-/dev/stdout}" dev="${4:-}"
  local sandbox model effort budget maxmin maxturns grace

  [ -f "$obj" ] || duet_die "objective file not found: $obj"

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
