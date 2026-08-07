#!/usr/bin/env bash
# Which host am I running inside? (issue #24)
#
# Detection is genuinely unreliable, and it is unreliable in exactly the place
# Duet lives: when one CLI runs inside the other, the child sees BOTH sets of
# environment variables. So the handshake comes first and sniffing is only a
# fallback.
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

# The counterpart we would delegate to. On `unknown` we assume claude is the
# orchestrator, because that is the direction that works without weakening
# anyone's sandbox (issue #2: codex -> claude needs danger-full-access, since
# Codex's sandbox kills DNS to api.anthropic.com).
duet_counterpart () {
  case "$(duet_host)" in
    claude) printf 'codex' ;;
    codex)  printf 'claude' ;;
    *)      printf 'codex' ;;
  esac
}

# Announce an assumption rather than making it silently, so a wrong guess is
# visible and cheap instead of confusing.
duet_host_report () {
  local h; h="$(duet_host)"
  if [ "$h" = "unknown" ]; then
    duet_warn "could not identify the host CLI; assuming Claude orchestrates."
    duet_warn "set DUET_HOST=claude|codex to be explicit."
  fi
  printf '%s' "$h"
}
