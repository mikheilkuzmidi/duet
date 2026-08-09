#!/usr/bin/env bash
# Per-repo, per-device setup.
#
# Every knob Duet has was already configurable in 0.1.0 and nobody configured
# any of them, because a knob you have to know exists is a knob nobody turns.
# So the questions get asked once, in plain language, the first time Duet runs
# in a repository.
#
# WHERE IT LIVES: .duet/config.json inside the repo, which duet_cfg already
# prefers over the global file. That makes it per-repo AND per-device, because
# .duet/ is added to .git/info/exclude and never travels. Two people on the same
# project can disagree about grilling depth without a merge conflict.
#
# WHY .git/info/exclude AND NOT .gitignore: .gitignore is a tracked file, so
# writing to it puts a diff in the human's working tree that they did not ask
# for and will have to explain in a commit. info/exclude is local, untracked,
# and does the same job. Standing rule 6: this is the smallest write that
# achieves the thing.
#
# The questions themselves are asked by the duet-setup SKILL, conversationally.
# This file is the non-interactive half: it validates, writes, and reports.
# `read` from a prompt would hang, because Duet's own Bash calls do not have an
# interactive stdin, and a setup that hangs is worse than no setup.

# shellcheck source=duet-common.sh
. "$(dirname "${BASH_SOURCE[0]}")/duet-common.sh"

DUET_SETUP_VERSION=1

# ---------- schema ----------------------------------------------------------
# key|default|validator|one-line plain-English question
# The question text is here rather than in the skill so the CLI and the skill
# can never drift apart on what was actually asked.

duet_setup_schema () {
  cat <<'EOF'
voice|plain|plain,technical|How should I talk to you: plain English, or straight technical?
grill.depth|normal|off,normal,hard|Should I question you about the plan before building, or take the request as written?
autonomy|product|full,product,off|How autonomous should I be?
safety.alwaysAsk|push-to-main,production-data,delete-outside-tree|list:push-to-main,production-data,delete-outside-tree,global-install,paid-api,rewrite-history,none|What should I never do without asking?
safety.mode|ask-now|ask-now,defer-to-final|When I hit one of those, stop and ask, or queue it for the end?
git.mode|branch|none,commit,branch,pr|Should I commit as I go?
agents.claude.max|2|1-10|How many Claude agents may run at once?
agents.codex.max|2|1-10|How many Codex agents may run at once?
progress.mode|heartbeat|off,heartbeat,digest,window|Do you want to see progress while it works?
permissions.bypass|true|true,false|Skip the "can I edit this file" prompts?
budget.warnUsd|5|num|Warn me once a run passes this spend, in dollars.
budget.stopUsd|0|num|Stop the run at this spend, in dollars. 0 means no hard stop.
done.coverageMin|80|0-100|Test coverage floor before anything counts as done.
EOF
}

duet_setup_validate () {   # <key> <value> ; echoes ok or the reason it is not
  local key="$1" val="$2" rule line
  rule="$(duet_setup_schema | awk -F'|' -v k="$key" '$1==k{print $3}')"
  [ -z "$rule" ] && { printf 'unknown key'; return 1; }
  case "$rule" in
    list:*)
      # A comma separated subset. Every element must be allowed, because a typo
      # in a safety list silently removes a guard rather than failing.
      local allowed="${rule#list:}" item
      IFS=',' read -ra _items <<< "$val"
      for item in "${_items[@]}"; do
        [ -z "$item" ] && continue
        case ",$allowed," in *",$item,"*) : ;;
          *) printf 'unknown item "%s". Allowed: %s' "$item" "$allowed"; return 1 ;;
        esac
      done ;;
    num) case "$val" in ''|*[!0-9.]*) printf 'expected a number'; return 1 ;; esac ;;
    # The range pattern must require DIGITS either side. Plain *-* also matches
    # an enum like "ask-now,defer-to-final", which then fails as "expected a
    # whole number" and aborts the whole setup. That bug shipped for about ten
    # minutes and silently left max allowance without its defer-to-final.
    [0-9]*-[0-9]*)
         local lo="${rule%%-*}" hi="${rule##*-}"
         case "$val" in ''|*[!0-9]*) printf 'expected a whole number'; return 1 ;; esac
         if [ "$val" -lt "$lo" ] || [ "$val" -gt "$hi" ]; then
           printf 'expected %s to %s' "$lo" "$hi"; return 1
         fi ;;
    *,*) case ",$rule," in *",$val,"*) : ;; *) printf 'expected one of %s' "$rule"; return 1 ;; esac ;;
  esac
  printf 'ok'
}

# ---------- max allowance ---------------------------------------------------
# The express path, for people who read diffs.
#
# The disclaimer is not decoration. This mode hands both agents the ability to
# edit, delete, install, migrate and spend without a prompt, and it removes the
# plan approval gate. Anyone enabling it should meet that sentence before it is
# true rather than afterwards.
#
# It keeps three items on the stop-list and sets safety.mode=defer-to-final, so
# the run is NEVER interrupted, and the three things a diff cannot undo still
# take one deliberate yes at the end. A mode that stops is not max. A mode that
# force pushes unasked is not defensible.

DUET_MAX_PHRASE="max allowance"

duet_setup_max_disclaimer () {
  cat >&2 <<'EOF'

  duet: max allowance

    permissions.bypass   true              no edit prompts, plan gate stops gating
    autonomy             full              one final round, nothing else asked
    safety.mode          defer-to-final    never stops, queues the irreversible
    safety.alwaysAsk     3 items           push to main, production data,
                                           deleting outside the working tree
    git.mode             branch            commits per stage, on a branch
    agents               4 claude, 4 codex
    grill.depth          normal
    progress.mode        heartbeat

  Both agents may edit, delete, install, migrate and spend without asking.
  Nothing stops until the end. For people who read diffs.

  Confirm with: duet setup --max --confirm "max allowance"
EOF
}

duet_setup_max () {   # <confirmation phrase>
  if [ "${1:-}" != "$DUET_MAX_PHRASE" ]; then
    duet_setup_max_disclaimer
    return 1
  fi
  duet_setup_apply \
    voice=technical \
    grill.depth=normal \
    autonomy=full \
    safety.alwaysAsk=push-to-main,production-data,delete-outside-tree \
    safety.mode=defer-to-final \
    git.mode=branch \
    agents.claude.max=4 \
    agents.codex.max=4 \
    progress.mode=heartbeat \
    permissions.bypass=true \
    budget.warnUsd=25 \
    budget.stopUsd=0 \
    done.coverageMin=80 || return 1
  duet_warn "max allowance is on. Nothing will stop until the final round."
}

# ---------- state -----------------------------------------------------------

duet_setup_done () { [ -f "$(duet_config_local)" ] && [ "$(duet_cfg setup.version 0)" -ge 1 ] 2>/dev/null; }

# ---------- ignore ----------------------------------------------------------
# What is ignored: Duet's own working state. What is NOT, deliberately: the
# documents Duet generates for the project. CLAUDE.md, AGENTS.md and docs/ are
# the thing that stops the next agent drifting, and an anti-drift document that
# only exists on one laptop has failed.

duet_setup_ignore () {
  local root ex
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    duet_warn "not a git repository, so nothing to ignore. .duet/ stays local anyway."
    return 0
  }
  ex="$root/.git/info/exclude"
  mkdir -p "$(dirname "$ex")"; [ -f "$ex" ] || : > "$ex"
  local added=0 entry
  for entry in '.duet/' '*.err'; do
    grep -qxF "$entry" "$ex" 2>/dev/null || { printf '%s\n' "$entry" >> "$ex"; added=1; }
  done
  [ "$added" = "1" ] && duet_ok "ignored .duet/ locally, no repo diff (.git/info/exclude)"
  return 0
}

# ---------- apply -----------------------------------------------------------
# duet_setup_apply key=value ...   ; unlisted keys take the schema default

duet_setup_apply () {
  local pair key val why bad=0
  for pair in "$@"; do
    case "$pair" in
      *=*) key="${pair%%=*}"; val="${pair#*=}" ;;
      *)   duet_err "expected key=value, got: $pair"; bad=1; continue ;;
    esac
    why="$(duet_setup_validate "$key" "$val")" || { duet_err "$key: $why"; bad=1; continue; }
    duet_cfg_set "$key" "$val" local
  done
  [ "$bad" = "1" ] && return 1

  # Fill anything not answered with its default, so the file is complete and a
  # later read never depends on a default that has since changed underneath it.
  local line k d
  while IFS='|' read -r k d _ _; do
    [ -z "$k" ] && continue
    [ "$(duet_cfg "$k" "__unset__")" = "__unset__" ] && duet_cfg_set "$k" "$d" local
  done <<EOF
$(duet_setup_schema)
EOF

  # The visible-window mode predates the progress setting and reads its own key.
  # Keep them in agreement here rather than teaching two things to disagree.
  case "$(duet_cfg progress.mode heartbeat)" in
    window) duet_cfg_set window.visible true  local ;;
    *)      duet_cfg_set window.visible false local ;;
  esac

  duet_cfg_set setup.version "$DUET_SETUP_VERSION" local
  duet_cfg_set setup.completedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" local
  duet_setup_ignore
  duet_ok "setup written to $(duet_config_local)"
}

# ---------- report ----------------------------------------------------------

duet_setup_report () {
  local k d q
  duet_step "Duet setup for $(basename "${DUET_PROJECT:-$PWD}")"
  while IFS='|' read -r k d _ q; do
    [ -z "$k" ] && continue
    printf '  %-22s %-10s %s\n' "$k" "$(duet_cfg "$k" "$d")" "$q" >&2
  done <<EOF
$(duet_setup_schema)
EOF
  duet_say ""
  duet_say "  change one: duet config <key> <value> local"
}
