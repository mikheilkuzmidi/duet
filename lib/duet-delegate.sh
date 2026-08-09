#!/usr/bin/env bash
# Spawning the other agent. This is where most of the research findings live,
# because almost every flag here exists to avoid a specific silent failure.
# (issues #15, #2, #6)
#
# Direction is fixed as of 0.2.0: Claude orchestrates, Codex is delegated to.
# duet_delegate_claude remains, because the orchestrator still farms parallel
# Claude work out to sub-sessions, but nothing here drives Duet from Codex.

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
. "$DUET_ROOT/lib/duet-host.sh"
. "$DUET_ROOT/lib/duet-progress.sh"
. "$DUET_ROOT/lib/duet-goal.sh"
. "$DUET_ROOT/lib/duet-preflight.sh"   # duet_fastmode

DUET_BASH_CEILING=600   # Claude Code's own Bash tool timeout, in seconds

# ---------- the brief check -------------------------------------------------
# Standing rule 8. A brief containing its own conclusion gets that conclusion
# back, and the agreement then looks like verification.
#
# This runs automatically on every Codex brief. It WARNS and does not block:
# there are real briefs that legitimately contain the word "confirm", and a gate
# people learn to route around protects nothing. A warning at the moment of
# sending is enough, because the fix takes ten seconds.

duet_brief_check () {   # <brief file> ; returns 1 if anything was flagged
  local f="$1" hits
  [ -f "$f" ] || return 0
  hits="$(grep -nEio \
    'confirm (that|the|it|this)|just confirm|verify that [a-z_]+ (is|are|still)|as we discussed|as expected|as you know|should (be|still be)|i (believe|think)|presumably|obviously|make sure (it|this) is still' \
    "$f" 2>/dev/null | head -5)"
  [ -z "$hits" ] && return 0
  duet_warn "this brief may be leading (standing rule 8):"
  printf '%s\n' "$hits" | sed 's/^/      /' >&2
  duet_say  "      ask for the table, not the yes or no. reference/briefing-codex.md"
  return 1
}

# ---------- the injected reference set --------------------------------------
# Rules, output discipline and the shared definition of done, in front of every
# delegated call. Re-injected at every phase boundary because prompt text does
# not survive context compaction and a system-prompt file does.

# The run context goes FIRST, before the reference files. The rules are the same
# for every run; the settings are what makes this one different, and an agent
# that reads them last has already formed a plan without them.
#
# DUET_STAGE_LABEL and DUET_GATE_CMD are set by the caller when a preset stage
# is being run, so the agent knows where it is and what it is being measured by.
duet_compose_context () {   # <dest> [extra files...]
  local dest="$1"; shift
  : > "$dest"
  duet_context_block "${DUET_STAGE_LABEL:-}" "${DUET_GATE_CMD:-}" >> "$dest"
  local f
  while IFS= read -r f; do
    [ -f "$f" ] && { cat "$f" >> "$dest"; printf '\n\n' >> "$dest"; }
  done < <(duet_ref_set)
  for f in "$@"; do
    [ -f "$f" ] && { cat "$f" >> "$dest"; printf '\n\n' >> "$dest"; }
  done
}

# ---------- Codex -----------------------------------------------------------
# duet_delegate_codex <briefing-file> <cwd> <out.jsonl>
#
# Every flag is load bearing:
#   -s workspace-write      the default is environment-dependent and lands on
#                           read-only in a normal project dir, where writes fail
#                           SILENTLY because exec forces approval: never. Codex
#                           would report building something never written.
#   --skip-git-repo-check   codex exits 1 outside a trusted directory
#   --json                  JSONL on stdout, the only machine-readable form
#   < /dev/null             codex blocks FOREVER on inherited stdin. Two
#                           independent investigations hit this.
#   no --ephemeral          the served model is only recoverable from the
#                           rollout, and we need it to verify no downgrade
#   prompt via stdin/file   codex rejects >1,048,576 chars and the npm shim dies
#                           near 1MB with a misleading Node RangeError, exit 7
#
# Codex exec has no system-prompt flag, so the reference set is PREPENDED to the
# prompt file. Same effect, one file, and it stays inside the size limit that
# the brief was already sized against.

duet_delegate_codex () {
  local brief="$1" cwd="${2:-$PWD}" out="${3:-/dev/stdout}"
  local sandbox model effort prompt watcher pid rc
  [ -f "$brief" ] || duet_die "briefing file not found: $brief"

  duet_brief_check "$brief" || true

  prompt="$(mktemp)"
  duet_compose_context "$prompt" "$(duet_ref briefing-codex.md)" "$brief"

  if duet_fastmode 2>/dev/null; then sandbox="danger-full-access"; else sandbox="workspace-write"; fi
  model="$(duet_codex_model)"
  effort="$(duet_codex_effort "$model")"

  local -a args=(exec -s "$sandbox" -C "$cwd" --skip-git-repo-check --json)
  [ -n "$model" ]  && args+=(-m "$model")
  [ -n "$effort" ] && args+=(-c "model_reasoning_effort=\"$effort\"")

  duet_say "  codex · ${model:-default} · effort ${effort:-default} · $sandbox"

  # NEVER pipe codex --json into head: a broken pipe panics it with exit 101.
  # Backgrounded so the heartbeat can prove it is alive; a phase that runs for
  # four silent minutes gets killed by a reasonable human.
  DUET_HOST=codex codex "${args[@]}" < "$prompt" > "$out" 2>>"${out}.err" &
  pid=$!
  watcher="$(duet_progress_watch "$out" "codex" "$pid")"
  wait "$pid"; rc=$?
  duet_progress_stop "$watcher"
  rm -f "$prompt"

  [ $rc -ne 0 ] && duet_err "codex exited $rc (see ${out}.err)"
  return $rc
}

# ---------- Claude ----------------------------------------------------------
# duet_delegate_claude <briefing-file> <task-file> <cwd> <out.json>
#
#   --append-system-prompt-file  carries the briefing AND the reference set.
#                                Hidden from --help but real. Far better than
#                                stuffing them into a user turn, and it is the
#                                injection point that survives compaction.
#   --session-id                 pre-set, so resuming needs no output parsing
#   --permission-mode            default is Manual, i.e. READS ONLY. A naive
#                                claude -p cannot edit anything.

duet_delegate_claude () {
  local brief="$1" task="$2" cwd="${3:-$PWD}" out="${4:-/dev/stdout}"
  local sid sysprompt mode rc
  sid="$(duet_uuid)"

  sysprompt="$(mktemp)"
  duet_compose_context "$sysprompt" "$brief"

  if duet_fastmode 2>/dev/null; then
    mode="bypassPermissions"
  else
    mode="acceptEdits"
  fi

  duet_say "  claude · $(duet_claude_model) · effort $(duet_claude_effort) · $mode"

  # --effort is passed, not merely reported. Duet printed an effort it never
  # applied until 0.3.1, which is the exact shape of the thing standing rule 7
  # exists to forbid.
  #
  # CLAUDE_CODE_EFFORT_LEVEL in the environment silently OVERRIDES --effort, so
  # it is cleared for the child. Inheriting it would mean the line above is a
  # lie whenever the human has that variable set.
  ( cd "$cwd" && DUET_HOST=claude CLAUDE_CODE_EFFORT_LEVEL= claude -p \
      --model "$(duet_claude_model)" \
      --effort "$(duet_claude_effort)" \
      --permission-mode "$mode" \
      --output-format json \
      --session-id "$sid" \
      --append-system-prompt-file "$sysprompt" \
      < "$task" > "$out" 2>>"${out}.err" )
  rc=$?
  rm -f "$sysprompt"

  # The auto-mode classifier blocks launching agent runners when approvals are
  # disabled. That failure is "Duet does not run", not "Duet is less safe", so
  # it must never look like a hang or a generic error (issue #29).
  if [ $rc -ne 0 ] && duet_fastmode 2>/dev/null; then
    if grep -qiE 'approval|permission|classifier|not allowed' "${out}.err" 2>/dev/null; then
      duet_err "Claude refused to launch a delegated agent while fast mode is on."
      duet_err "This is the auto-mode classifier blocking approval-disabled runners."
      duet_err "Fix: duet config permissions.bypass false   (then re-run)"
      return 78
    fi
  fi
  [ $rc -ne 0 ] && duet_err "claude exited $rc (see ${out}.err)"
  return $rc
}

# ---------- goals: work that must come back finished ------------------------
#
# WHICH MECHANISM FOR WHICH PHASE, and the reason:
#
#   brief and research  ->  duet_delegate_codex, one shot.
#       One deliverable, no continuation to manage. Quality is already governed
#       by duet_brief_check and the verdict vocabulary.
#
#   anything that writes code  ->  duet_work_codex / duet_work_claude, as goals.
#       These are the phases that come back at eighty percent, because a prompt
#       ends when the model stops talking. A goal ends when a command exits zero.

# The gate. A phase is done when a command says so, not when an agent says so.
duet_gate_check () {   # <gate command> <cwd>
  local cmd="$1" cwd="${2:-$PWD}"
  [ -z "$cmd" ] && return 0            # no gate declared, nothing to check
  ( cd "$cwd" && eval "$cmd" ) >/dev/null 2>&1
}

# duet_work_codex <objective-file> <cwd> <out.jsonl> [briefing-file]
#
# The reference set AND any phase briefing ride in as developerInstructions on
# the thread, never in the objective. The objective is capped at 4000 characters
# by the goal API, so a briefing put there fails the whole call.
duet_work_codex () {
  local obj="$1" cwd="${2:-$PWD}" out="${3:-/dev/stdout}" brief="${4:-}" dev rc
  dev="$(mktemp)"
  duet_compose_context "$dev" "$brief"
  duet_fastmode 2>/dev/null && export DUET_FASTMODE_APPROVE=1
  duet_goal_run "$obj" "$cwd" "$out" "$dev"
  rc=$?
  rm -f "$dev"
  [ $rc -ne 0 ] && duet_err "codex goal $(duet_goal_explain $rc)"
  return $rc
}

# duet_work_claude <objective-file> <cwd> <out.json> <gate command>
#
# Claude has no goal API. `/goal` is not a file under ~/.claude, and built-in
# commands never are, so its existence could not be established either way.
# Rather than bet a delegation path on an unverified command, this builds the
# same property out of parts that are verified: run, check the gate, resume the
# same session if it has not passed. A loop that ends on a command exiting zero
# is what a goal is; the API is a convenience, not the mechanism.
duet_work_claude () {
  local obj="$1" cwd="${2:-$PWD}" out="${3:-/dev/stdout}" gate="${4:-}"
  local sid sysprompt mode turns max rc
  sid="$(duet_uuid)"
  max="$(duet_cfg goal.maxTurns 40)"
  turns=0

  sysprompt="$(mktemp)"
  duet_compose_context "$sysprompt" "$(duet_ref goal-format.md)"

  if duet_fastmode 2>/dev/null; then mode="bypassPermissions"; else mode="acceptEdits"; fi
  duet_say "  claude goal · $(duet_claude_model) · $mode · gate: ${gate:-none}"

  while [ "$turns" -lt "$max" ]; do
    turns=$((turns + 1))
    if [ "$turns" -eq 1 ]; then
      ( cd "$cwd" && DUET_HOST=claude CLAUDE_CODE_EFFORT_LEVEL= claude -p \
          --model "$(duet_claude_model)" --effort "$(duet_claude_effort)" \
          --permission-mode "$mode" \
          --output-format json --session-id "$sid" \
          --append-system-prompt-file "$sysprompt" \
          < "$obj" > "$out" 2>>"${out}.err" )
    else
      printf 'Continue toward the objective. Do not summarise progress and do not ask questions. Keep working until this passes: %s\n' "$gate" \
        | ( cd "$cwd" && DUET_HOST=claude CLAUDE_CODE_EFFORT_LEVEL= claude -p \
              --model "$(duet_claude_model)" --effort "$(duet_claude_effort)" \
              --permission-mode "$mode" \
              --output-format json --resume "$sid" \
              --append-system-prompt-file "$sysprompt" \
              > "$out" 2>>"${out}.err" )
    fi
    rc=$?
    [ $rc -ne 0 ] && { duet_err "claude exited $rc (see ${out}.err)"; break; }

    if duet_gate_check "$gate" "$cwd"; then
      duet_say "  claude goal · gate passed on turn $turns"
      rm -f "$sysprompt"; return 0
    fi
    [ -z "$gate" ] && { rm -f "$sysprompt"; return 0; }   # nothing to loop on
    duet_say "  claude goal · gate not passed, continuing (turn $turns)"
  done

  rm -f "$sysprompt"
  duet_err "claude goal did not pass its gate in $max turns"
  return 78
}

# ---------- long phases -----------------------------------------------------
# Neither CLI has a timeout flag, and Claude Code's Bash tool caps at 600s. So
# anything that might run long is detached with output redirected to the run
# directory and polled, rather than awaited.

duet_delegate_detached () {   # <cmd...> ; echoes the pid
  "$@" &
  printf '%s' "$!"
}

duet_poll () {   # <pid> <label> [interval]
  local pid="$1" label="$2" iv="${3:-10}" waited=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$iv"; waited=$((waited+iv))
    [ $((waited % 60)) -eq 0 ] && duet_say "  ${label} · $(duet_progress_fmt $waited) · still running"
  done
  wait "$pid"; return $?
}
