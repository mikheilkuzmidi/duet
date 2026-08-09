#!/usr/bin/env bash
# GitHub projection. (issue #19)
#
# Milestones only, batched. The spec, the approved plan, the final debate
# exchange, and the result. Per-phase chatter stays in the run directory.
#
# Why: the binding limit is 500 CONTENT-GENERATING requests per hour and 80 per
# minute, shared across REST, GraphQL and the web UI. At ~74 writes per run that
# allowed about 3 runs an hour. At 6 to 10 the ceiling stops being a constraint
# at all, and you keep headroom for whatever else you do on GitHub that hour.
#
# Files remain the source of truth. This is a one-way idempotent projection
# keyed by the run id, so republishing never duplicates.

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

duet_gh_ready () {
  duet_has gh || { duet_warn "gh not installed; staying local"; return 1; }
  gh auth status >/dev/null 2>&1 || { duet_warn "gh not authenticated; staying local"; return 1; }
  return 0
}

# Docs mandate at least 1 second between mutative requests, honouring
# retry-after, and warn that ignoring the limits may get an integration banned.
duet_gh_write () { sleep 1; gh "$@"; }

duet_gh_repo_create () {   # <name>
  # Private by DEFAULT. Accidentally publishing someone's work is a one-way
  # door; making a private repo public later is one command.
  duet_gh_ready || return 1
  duet_gh_write repo create "$1" --private --disable-wiki \
    --description "Created by Duet" >/dev/null 2>&1 \
    && duet_ok "created private repo $1"
}

# Idempotent: the run id is embedded in the title, so re-projecting a run
# updates rather than duplicates.
duet_gh_milestone () {   # <run-id> <title> <body-file>
  duet_gh_ready || return 1
  local rid="$1" title="$2" body="$3" existing
  existing="$(gh issue list --search "duet:$rid in:title" --state all \
                --json number,title --jq ".[] | select(.title | contains(\"$title\")) | .number" 2>/dev/null | head -1)"
  if [ -n "$existing" ]; then
    duet_gh_write issue comment "$existing" --body-file "$body" >/dev/null && duet_ok "updated #$existing"
  else
    duet_gh_write issue create --title "$title [duet:$rid]" --body-file "$body" >/dev/null && duet_ok "posted $title"
  fi
}

# Traps worth remembering, all of them silent failures:
#   gh 2.92.0 cannot do sub-issues or dependencies natively; they arrived in
#     2.94.0. Older versions must go through gh api.
#   REST wants the NUMERIC database id, while `gh issue view --json id` returns
#     the GraphQL node id. They look interchangeable and are not.
#   A missing scope on a private repo returns 404, NOT 403. Never report that
#     as "the repo does not exist".
#   Maximum body size is undocumented. Cap client-side and split on a 422.
duet_gh_capabilities () {
  duet_has gh || return 1
  local v; v="$(gh --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  printf 'gh %s' "$v"
  if [ -n "$v" ] && [ "$(printf '%s\n2.94.0\n' "$v" | sort -V | head -1)" = "$v" ] && [ "$v" != "2.94.0" ]; then
    printf ' (sub-issues and dependencies need gh api on this version)'
  fi
  printf '\n'
}
