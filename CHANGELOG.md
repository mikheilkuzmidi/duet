# Changelog

## 0.4.0

Closing the gap between what Duet said and what Duet did. Auditing 0.3.1 before
calling it finished turned up three defects with one shape: the documentation
described more than the code performed, which is the exact failure standing rule
7 forbids and the one this repo can least afford.

- **The skills now reach for the goal machinery.** `duet_work_codex`,
  `duet_work_claude` and `reference/goal-format.md` were built, verified and
  then mentioned by no skill at all, so the headline feature of 0.3.0 was
  unreachable in practice. The orchestrator skill, the build skill and all four
  presets now name the runner, resolve the stage gate first, and read the exit
  code through `duet_goal_explain`.
- **The run context reaches the agent.** `autonomy`, `voice`, the coverage
  floor, the safety mode and the detected project commands were written to
  `.duet/config.json` at setup and then told to nobody. A delegated agent under
  `autonomy=full` was never informed it must not stop to ask. Every call now
  opens with a generated "This run" block, ahead of the static reference files,
  because rules are the same everywhere and settings are what make this run
  different.
- **`digest` is implemented rather than described.** It condenses the agent's
  own words every `progress.digestEverySec` with a deliberately cheap Haiku
  call. Setup's warning that it uses extra quota is now true.
- **Setup runs itself.** First use in a repo asks the questions and then carries
  straight on with what was actually asked, instead of warning and stopping.
- **Claude moves to `opus[1m]` at `xhigh`**, for the rescue preset where a large
  codebase must be in view at once, and for long goals where mid-run compaction
  is what loses the plot.

### Verified

0.4.0 is the first version that has been run end to end. `/duet:duet-skill` was
run to completion to build `duet-release`, the skill that cuts a release, and
the artifacts are kept in `docs/shakedown/`. It found four defects that reading
would never have surfaced: the zsh sourcing failure, the zsh infinite loop in
gate resolution, the undocumented 4000-character objective cap, and a trigger
test that could not tell a missing file from an absent phrase. The first three
are fixed here; the fourth is fixed in the skill preset.

### Added

- `skills/duet-release/`, written by the pipeline during the shakedown rather
  than by hand, and kept because it is genuinely useful.
- `docs/shakedown/`, the run's real output: the spec, the research briefing with
  its sourced verdicts, the debate concerns and the answer to them.

### Fixed

- **The libraries could not be sourced from zsh**, which is the default shell on
  macOS and the one Claude Code's Bash tool runs. `${BASH_SOURCE[0]}` is empty
  there, so every sibling `source` resolved to `./duet-x.sh` and failed. The
  goal path was therefore unreachable from the exact shell the skills told the
  orchestrator to use, and it survived every test that happened to run under
  `bash -c`. Libraries now locate each other through `DUET_ROOT`, and the skills
  call `duet` subcommands instead of sourcing anything.
- **`duet_gate_resolve` looped forever under zsh.** It read `${BASH_REMATCH[1]}`
  expecting the first capture group; zsh puts the whole match there, so the
  placeholder was never consumed. A hang is the worst failure shape available:
  no error, no output, and the human kills the run believing the model is
  thinking. It now substitutes by iterating known keys, with no regex at all.
- **A goal objective is capped at 4000 characters**, which is in no
  documentation this repo could find and was discovered by sending 9,237 and
  reading the error. Duet now refuses an over-long objective with a message
  naming the limit, rather than truncating: the exit gate lives at the end of
  the block, so truncation would silently discard the line that decides when the
  work is finished. Briefings belong in developer instructions, which have no
  such cap, and `duet goal codex` takes one as its fourth argument.

### Added

- `duet delegate`, `duet goal` and `duet context` subcommands, so nothing has to
  source a shell library to drive a phase.

### Fixed

- **`duet_progress_excerpt` found nothing in a real stream**, so digest was
  calling it, receiving an empty string and silently returning. Agent text
  arrives as `params.delta` on `item/agentMessage/delta` and has to be
  reassembled per item, which it now does.
- **The progress parser knew only one of Codex's two stream shapes.** The
  app-server uses slashed names with the payload under `params`; `exec --json`
  uses dotted names with the payload at top level. Briefing phases therefore
  reported "35 events" instead of what the agent was doing. Both shapes are
  documented at the top of `duet-progress.sh` and one parser serves both.
- The heartbeat's cumulative figure is labelled `ctx`, not `tok`. It counts
  context processed including cached input, and printing 125.0k next to a goal
  reporting 20,038 read as a contradiction.

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
