#!/usr/bin/env bash
# Which host am I running inside? (issue #24)
#
# Detection is genuinely unreliable, and it is unreliable in exactly the place
# Duet lives: when one CLI runs inside the other, the child sees BOTH sets of
# environment variables. So the handshake comes first and sniffing is only a
# fallback.
#
# As of 0.2.0 the answer to "who orchestrates" is no longer detected, it is
# fixed: CLAUDE ORCHESTRATES. Codex is the fact-finder, the backend and the
# tests. That deleted a whole class of bugs. It also deleted a real constraint:
# Codex-orchestrates required danger-full-access, because Codex's sandbox kills
# DNS to api.anthropic.com, so the direction we kept is the one that works with
# nobody's sandbox weakened.
#
# THE STANDING RULE: host identity may select a default. It may never gate
# whether the work is correct. Anything that would produce a wrong answer under
# `unknown` is a bug in the caller, not a missing detection case.

# shellcheck source=duet-common.sh
. "$(dirname "${BASH_SOURCE[0]}")/duet-common.sh"

duet_host () {
  # 1. the handshake: set by Duet itself whenever it spawns a counterpart.
  if [ -n "${DUET_HOST:-}" ]; then printf '%s' "$DUET_HOST"; return; fi

  # 2. nesting signal, the only Claude marker documented for child sessions.
  if [ -n "${CLAUDE_CODE_CHILD_SESSION:-}" ]; then printf 'claude'; return; fi

  # 3. reliable but undocumented, so it may vanish without notice.
  if [ -n "${CLAUDECODE:-}" ]; then printf 'claude'; return; fi

  # 4. Codex has no unconditional marker. CODEX_SANDBOX is macOS-gated and
  #    disappears entirely under danger-full-access, which is what power users
  #    run. The arg0 shim survives every sandbox mode but is an implementation
  #    detail, so it sits last.
  if [ -n "${CODEX_SANDBOX:-}" ] || [ -x /tmp/arg0/codex-arg0 ]; then
    printf 'codex'; return
  fi

  printf 'unknown'
}

# Duet drives from Claude Code. Started from Codex, it says so in one line and
# stops, rather than half working in a direction that has been removed.
#
# `unknown` proceeds. Detection failing is not a reason to refuse, and the
# orchestrator being Claude is now an assumption Duet is entitled to make.
duet_require_claude_host () {
  if [ "$(duet_host)" = "codex" ]; then
    duet_err "Duet runs from Claude Code. Start it there."
    duet_say "  Codex is Duet's fact-finder, backend and test author. It does not drive."
    return 1
  fi
  return 0
}

duet_host_report () { printf '%s' "$(duet_host)"; }
