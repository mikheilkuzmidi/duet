# Changelog

## 0.3.1

Models pinned to what was asked for, and three bugs that pinning exposed.

- **Codex runs `gpt-5.6-terra` at `xhigh`.** The slug is verified against the
  live catalog on every call: `models.codex.prefer` is used only if the catalog
  still lists it, and a preference that has disappeared degrades to discovery
  and says so, rather than passing a dead model name to the CLI.
- **Claude runs `opus` at `xhigh`.** The previous default, `best`, does not mean
  Opus. Verified by running it: `best` resolves to `claude-fable-5`, while
  `opus` resolves to `claude-opus-5`. Duet had been selecting a different model
  from the one it described.
- **`ultracode` is not a model and not a level above `xhigh`.** It resolves to
  `xhigh` and adds dynamic-workflow orchestration to an interactive session,
  which a delegated `-p` call has nothing to do with. `max` is the real level
  above `xhigh`; set `models.claude.effort=max` if you want it.

### Fixed

- **Duet never passed `--effort`.** It computed a level, printed it, and invoked
  Claude without it. Every delegated call ran at the account default while the
  transcript claimed otherwise.
- **`CLAUDE_CODE_EFFORT_LEVEL` silently overrides `--effort`.** It is now
  cleared for delegated children. Verified: with `CLAUDE_CODE_EFFORT_LEVEL=low`
  set in the parent environment, the delegated agent reports `xhigh`.
- **The served-model check failed almost every healthy phase.** Claude Code runs
  housekeeping on Haiku alongside the working model, so `modelUsage` legitimately
  holds two entries, and any second entry was being reported as a mid-run model
  switch and refused. Auxiliary tiers are now ignored; two substantive models is
  still a genuine switch and still refused.

### Changed

- The Credit section says what is actually true. Nothing from
  `mattpocock/skills` ships in Duet: no code, no prose, no file. An audit found
  zero six-word runs shared with upstream anywhere in the repo or its history,
  and the MIT notice condition never attaches because no portion of that
  software is distributed here. The credit now records that Duet was *planned*
  with the wayfinder skill, which is why the issue tracker carries `wayfinder:*`
  labels, and drops both the retired "decision-mapping" name and the "(MIT)"
  parenthetical that implied a licence relationship.
- One branch. The OQ-1 prototype harness moved onto `main` under
  `prototypes/oq1-codex-remote-attach/`, so the README's evidence citation
  resolves to a directory rather than a deleted branch.

## 0.3.0

Goals, onboarding, and autonomy that is a setting rather than a promise.

**Work is delegated as a goal, not a prompt.** A prompt ends when the model
stops talking. A goal ends when a command exits zero. Codex's `goals` feature is
first-party and stable, and Duet now drives it over the app-server protocol:
`thread/goal/set` with an objective and a token budget, status running from
`active` to `complete`, and `usageLimited` treated as a state to resume from
rather than a failure. Claude has no goal API, so its side is the same property
built from verified parts: run, check the gate, resume the session, repeat.

**Every stage ends in a command.** All 42 stages across the four presets carry a
`gate_cmd`. A stage is done when its command exits zero, not when an agent says
so. Unresolvable gates fail loudly and name the missing key rather than passing
because there was nothing to run.

**Commands are detected, not interrogated.** `duet detect` reads `package.json`,
the lockfile, `Makefile`, `pyproject.toml`, `Cargo.toml`, CI workflows and any
deploy config, and shows every guess with the evidence behind it. This fills the
generated document templates and makes the deployed leg of the done check real.

**First run introduces itself** before asking anything, offers the command list,
says how many questions are coming, and checks both CLIs first.

**Autonomy is a dial**: `full`, `product`, or `off`, split by kind of decision
rather than by frontend and backend, because the line that matters is what the
user ends up seeing.

**A stop-list, and two ways to honour it.** `safety.alwaysAsk` holds the things
a diff cannot undo: pushing to `main`, touching production data, deleting
outside the working tree. `safety.mode` is either `ask-now` or
`defer-to-final`, where the run is never interrupted and the action queues for
the final round with its exact command.

**`duet setup --max`**, an express path that is wide open and honest about it.
It sets `defer-to-final`, so nothing stops mid-run and nothing irreversible
happens without one deliberate yes at the end.

**`reference/persona.md` and `reference/grilling.md`**: a stated disposition
(senior, curious) and the question archetypes that actually find holes.

Also: real rate-limit visibility through `account/rateLimits/read`, a heartbeat
on the goal path, and four new gate questions covering existing accounts,
personal data, what must not be touched, and the autonomy confirmation.

### Fixed

- **Codex spend recorded as zero on every phase.** The ledger read tokens from
  `params.usage.total_tokens`; the real path is
  `params.tokenUsage.total.totalTokens`.
- **`test -s {{out}}` passed when no output path was supplied.** With an empty
  substitution it becomes `test -s`, a one-argument string test, which is true.
  The gate passed because there was nothing to check.
- **The setup validator rejected `safety.mode`.** Its numeric-range pattern
  `*-*` also matched the enum `ask-now,defer-to-final`, which aborted setup
  before it wrote the ignore rule, and silently left max allowance without its
  `defer-to-final`.
- **The progress heartbeat reported MCP startup chatter as the agent's work.**
  Rewritten against event names verified from a live stream.

## 0.2.0

Claude leads, presets, and considerably less talking.

- **Claude always orchestrates.** Codex-orchestrates mode is removed, along with
  the `danger-full-access` requirement it carried and a class of host-detection
  bugs. Started from Codex, Duet says so in one line and stops.
- **Four preset stage machines**, held as data: build an app (13 stages), repair
  an app that works badly (11), add a feature (8), build a skill (8). Fixed
  stages, so both agents can say where they are and nothing is quietly skipped.
- **Per-repo, per-device setup.** Answers live in `.duet/config.json`, and
  `.duet/` goes into `.git/info/exclude`, so nothing travels and the repository
  shows no diff for having been set up.
- **Output discipline.** `reference/output-format.md`, injected everywhere: six
  lines per turn outside a gate, findings rather than prose about findings, no
  em dashes.
- **Briefs that cannot be agreed with.** `reference/briefing-codex.md` and
  standing rule 8. `duet_brief_check` warns on leading phrasings before a brief
  is sent. Every claim comes back VERIFIED, CONTRADICTED or UNVERIFIABLE with a
  source.
- **A shared definition of done.** Zero outstanding issues locally, in tests,
  and deployed. A check that cannot be run is recorded as outstanding, never
  skipped quietly.
- **Standing rules 8, 9 and 10**: brief without the answer, repair the defect
  rather than the feature, say less.
- **Split ownership.** Claude owns everything the user sees and every word they
  read. Codex owns everything underneath and files wording concerns rather than
  editing them.
- **Progress modes**: `off`, `heartbeat`, `digest`, `window`.
- **Separate agent pools** for Claude and Codex, since the accounts rate limit
  independently.
- Twelve commands with one-line descriptions, plus `duet setup`, `duet status`
  and `duet presets`.

## 0.1.0

Claude and Codex as one build pipeline. Codex establishes the facts, Claude
writes the code, and they argue about the result.
