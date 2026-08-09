#!/usr/bin/env bash
# Preflight: are both CLIs here, are both logged in, and how autonomous should
# this run be? (issues #14, #28, #29)
#
# Duet is a two-agent tool. With one agent it is not a degraded Duet, it is the
# CLI you already had, so preflight refuses rather than pretending. But the fix
# is always one yes away.

# shellcheck source=duet-common.sh
. "$(dirname "${BASH_SOURCE[0]}")/duet-common.sh"
. "$(dirname "${BASH_SOURCE[0]}")/duet-setup.sh"

# ---------- detection -------------------------------------------------------
# Returns: ok | missing | logged-out
#
# Auth traps, both learned the hard way (issue #6):
#   claude auth status exits 0 whether or not you are logged in. Parse the JSON.
#   codex exec is NOT a probe: unauthenticated it burns ~40s of retries first.

duet_check_claude () {
  duet_has claude || { printf 'missing'; return; }
  local out
  out="$(claude auth status --json 2>/dev/null || true)"
  if printf '%s' "$out" | grep -q '"loggedIn"[[:space:]]*:[[:space:]]*true'; then
    printf 'ok'
  else
    printf 'logged-out'
  fi
}

duet_check_codex () {
  duet_has codex || { printf 'missing'; return; }
  if codex login status >/dev/null 2>&1; then printf 'ok'; else printf 'logged-out'; fi
}

# ---------- remedies --------------------------------------------------------

duet_install_hint () {
  case "$1" in
    codex)  printf 'npm install -g @openai/codex   # or: brew install codex' ;;
    claude) printf 'curl -fsSL https://claude.ai/install.sh | bash' ;;
  esac
}

duet_login_hint () {
  case "$1" in
    codex)  printf 'codex login' ;;
    claude) printf 'claude auth login' ;;
  esac
}

# ---------- the gate --------------------------------------------------------

duet_preflight () {
  local c_claude c_codex bad=0
  duet_step "Duet preflight"

  c_claude="$(duet_check_claude)"
  c_codex="$(duet_check_codex)"

  case "$c_claude" in
    ok)         duet_ok  "claude CLI present and authenticated" ;;
    missing)    duet_err "claude CLI not installed"; bad=1 ;;
    logged-out) duet_err "claude CLI installed but not logged in"; bad=1 ;;
  esac
  case "$c_codex" in
    ok)         duet_ok  "codex CLI present and authenticated" ;;
    missing)    duet_err "codex CLI not installed"; bad=1 ;;
    logged-out) duet_err "codex CLI installed but not logged in"; bad=1 ;;
  esac

  if [ "$bad" = "1" ]; then
    duet_say ""
    duet_say "Duet needs both CLIs. It is a two-agent tool: with one agent it is"
    duet_say "just the CLI you already have, and pretending otherwise would be"
    duet_say "worse than stopping here."
    duet_say ""
    duet_say "IMPORTANT: this is the Codex CLI, not the Codex desktop app. The app"
    duet_say "cannot be driven this way, and the resulting failure is baffling."
    duet_say ""
    [ "$c_codex"  = "missing" ]    && duet_say "  install codex : $(duet_install_hint codex)"
    [ "$c_claude" = "missing" ]    && duet_say "  install claude: $(duet_install_hint claude)"
    [ "$c_codex"  = "logged-out" ] && duet_say "  log in  codex : $(duet_login_hint codex)"
    [ "$c_claude" = "logged-out" ] && duet_say "  log in  claude: $(duet_login_hint claude)"
    duet_say ""
    duet_say "Duet can run the install and setup for you from this session."
    duet_say "Say yes and it will do the whole thing, then continue."
    return 1
  fi

  duet_require_claude_host || return 1

  duet_ok "agents: claude $(duet_max_agents_for claude), codex $(duet_max_agents_for codex), ceiling ${DUET_MAX_AGENTS_CEILING}"
  duet_fastmode_report

  # Setup is not a gate, it is a missing answer. Say so once, in one line, and
  # let the caller decide whether to run it before continuing.
  if ! duet_setup_done; then
    duet_warn "this repo is not set up yet. Run /duet:duet-setup, or duet setup."
    return 2
  fi
  return 0
}

# ---------- fast mode -------------------------------------------------------
# Offered once, off by default, remembered per project (issue #29).
#
# This was chosen with both consequences on the table. They are real and Duet
# must never let a user meet them by surprise:
#
#   1. Claude's auto-mode classifier BLOCKS launching agent runners when
#      approvals are disabled. The failure is "Duet does not run", not "Duet is
#      less safe". duet_delegate detects this and reports it in plain language.
#   2. bypassPermissions also disables plan-mode enforcement, so the plan
#      approval gate and the coverage line stop stopping anything. They become
#      information, not a checkpoint.
#
# The reasoning for accepting them anyway is sound: a gate nobody reaches
# because they abandoned the run has not protected anything.

duet_fastmode () { [ "$(duet_cfg permissions.bypass false)" = "true" ] && return 0 || return 1; }

duet_fastmode_report () {
  if duet_fastmode; then
    duet_warn "fast mode ON: permissions bypassed on both CLIs"
    duet_warn "  the plan approval gate does NOT stop anything in this mode"
    duet_warn "  if Claude refuses to launch agents, that is the auto-mode"
    duet_warn "  classifier blocking approval-disabled runners. Duet will say so."
  else
    duet_say  "  fast mode off. Expect approval prompts on file edits."
    duet_say  "  enable with: duet config permissions.bypass true"
  fi
}

duet_fastmode_offer () {
  cat >&2 <<'EOF'

  Fast mode
  ---------
  Without it, a multi-phase run is punctuated by "can I edit this file"
  prompts, which makes long autonomous runs genuinely uncomfortable.

  With it, Duet passes --dangerously-skip-permissions to Claude and
  --sandbox danger-full-access to Codex. Two things you should know:

    - Claude's auto-mode classifier may refuse to launch delegated agents
      at all when approvals are off. Duet detects this and tells you.
    - The plan approval gate stops firing. Phases run unreviewed.

  Enable with : duet config permissions.bypass true
  Disable with: duet config permissions.bypass false
EOF
}
