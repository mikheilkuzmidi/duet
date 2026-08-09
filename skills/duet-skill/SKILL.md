---
name: duet-skill
description: Build a new agent skill, in 8 fixed stages. Use when the user says "duet skill", or wants to create a skill, slash command or plugin for Claude Code or Codex.
---

# duet skill

Eight stages, fixed, held in `reference/presets/skill.json`.

```
[1/8] Idea           what it does, one sentence
[2/8] Triggers       what someone says that should make it fire
[3/8] Never do this  what it must refuse or hand back  <- last question
[4/8] Research       Codex checks how the host actually loads skills today
[5/8] Write it       SKILL.md and any reference files
[6/8] Trigger test   it fires when it should and not when it should not
[7/8] Debate         both agents argue once
[8/8] Done           installs, fires, works, refuses what it should
```

## Before anything

Run `duet doctor`. **If it reports the repo is not set up, run the
`duet-setup` skill now, to completion, then carry straight on with what was
asked.** The human asked for something; setup is the questions Duet needs before
it can do it, not a separate errand for them to run.

## Running a stage

Work that writes code goes through a goal, not a prompt. A prompt ends when the
model stops talking; a goal ends when its gate command exits zero.

```bash
duet gate <preset> <n>                       # see the stage's gate command
export DUET_STAGE_LABEL="<n>/<total> <Title>" DUET_GATE_CMD="<the gate>"
duet goal codex  <objective-file> <cwd> <out.jsonl>
duet goal claude <objective-file> <cwd> <out.json> "<gate>"
duet delegate codex <brief> <cwd> <out.jsonl>     # a briefing, not a goal
```

**Call `duet`, never source the shell libraries.** `bin/duet` runs under bash
whatever shell you are in; sourcing `lib/*.sh` from zsh, which is the default on
macOS and what the Bash tool uses, does not work.

The objective is written per `reference/goal-format.md`: one block of prose, no
questions, the gate stated as a command. Read the exit code through
the printed verdict: 75 is a usage limit and must not be retried, 76 wants a
bigger token budget, 77 is blocked and worth reading, 78 hit a time or turn
limit and the work so far stands.

A briefing phase is not a goal. It is one `duet delegate codex` call.

## Stage 2 collects real phrasings

Ask what they would have typed at the moment they wanted this. Real ones,
including lazy ones. Nobody types the canonical phrasing.

Collect the near misses too, the things that must **not** fire it. A skill that
fires too often gets uninstalled faster than one that never fires.

## Stage 3 comes before any of it is written

What must this never do on its own? Anything expensive, destructive, or
outward-facing. Each with its reason, because a rule with a reason survives a
case it did not anticipate.

Doing this before stage 5 rather than after is the difference between a
guardrail and an apology.

## Stage 4 is not optional, even though it feels like it

Skill formats change. You will confidently write frontmatter that was correct
last year. Ask Codex the open questions in the preset: the current required
structure, which fields exist and are required today, the real limits, and how
the description is used to decide when a skill fires.

## Stage 5, the two things that decide whether it is any good

**The description is the trigger.** Write it for matching. Short enough to read
in a list, specific enough to fire on the phrasings from stage 2.

**Instructions state what and why.** A rule with a reason adapts to a case it
never anticipated. A rule without one breaks on the first unusual input. Long
or reference-shaped material goes in a separate file, not in `SKILL.md`.

## Stage 6 actually tests it

Say each should-fire phrase, check it fires. Say each must-not-fire phrase,
check it does not. Failures are fixed in the description, because that is where
triggering is decided, not in the body.
