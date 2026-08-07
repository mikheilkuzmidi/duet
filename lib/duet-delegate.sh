#!/usr/bin/env bash
# Spawning the other agent. This is where most of the research findings live,
# because almost every flag here exists to avoid a specific silent failure.
# (issues #15, #2, #6)

# shellcheck source=duet-common.sh
. "$(dirname "${BASH_SOURCE[0]}")/duet-common.sh"
. "$(dirname "${BASH_SOURCE[0]}")/duet-models.sh"
. "$(dirname "${BASH_SOURCE[0]}")/duet-host.sh"

DUET_BASH_CEILING=600   # Claude Code's own Bash tool timeout, in seconds

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

duet_delegate_codex () {
  local brief="$1" cwd="${2:-$PWD}" out="${3:-/dev/stdout}"
  local sandbox model effort
  [ -f "$brief" ] || duet_die "briefing file not found: $brief"

  if duet_fastmode 2>/dev/null; then sandbox="danger-full-access"; else sandbox="workspace-write"; fi
  model="$(duet_codex_model)"
  effort="$(duet_codex_effort "$model")"

  local -a args=(exec -s "$sandbox" -C "$cwd" --skip-git-repo-check --json)
  [ -n "$model" ]  && args+=(-m "$model")
  [ -n "$effort" ] && args+=(-c "model_reasoning_effort=\"$effort\"")

  duet_say "  codex: model=${model:-default} effort=${effort:-default} sandbox=$sandbox"

  # NEVER pipe codex --json into head: a broken pipe panics it with exit 101.
  DUET_HOST=codex codex "${args[@]}" < "$brief" > "$out" 2>>"${out}.err"
  local rc=$?
  [ $rc -ne 0 ] && duet_err "codex exited $rc (see ${out}.err)"
  return $rc
}

# ---------- Claude ----------------------------------------------------------
# duet_delegate_claude <briefing-file> <task-file> <cwd> <out.json>
#
#   --append-system-prompt-file  carries the briefing AND the standing rules.
#                                Hidden from --help but real. Far better than
#                                stuffing them into a user turn, and it is the
#                                injection point that survives compaction.
#   --session-id                 pre-set, so resuming needs no output parsing
#   --permission-mode            default is Manual, i.e. READS ONLY. A naive
#                                claude -p cannot edit anything.

duet_delegate_claude () {
  local brief="$1" task="$2" cwd="${3:-$PWD}" out="${4:-/dev/stdout}"
  local sid rules sysprompt mode
  sid="$(duet_uuid)"
  rules="$DUET_ROOT/reference/standing-rules.md"

  sysprompt="$(mktemp)"
  { [ -f "$rules" ] && cat "$rules"; echo; [ -f "$brief" ] && cat "$brief"; } > "$sysprompt"

  if duet_fastmode 2>/dev/null; then
    mode="bypassPermissions"
  else
    mode="acceptEdits"
  fi

  duet_say "  claude: model=$(duet_claude_model) effort=$(duet_claude_effort) mode=$mode"

  ( cd "$cwd" && DUET_HOST=claude claude -p \
      --model "$(duet_claude_model)" \
      --permission-mode "$mode" \
      --output-format json \
      --session-id "$sid" \
      --append-system-prompt-file "$sysprompt" \
      < "$task" > "$out" 2>>"${out}.err" )
  local rc=$?
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
    [ $((waited % 60)) -eq 0 ] && duet_say "  ${label}: still running (${waited}s)"
  done
  wait "$pid"; return $?
}
