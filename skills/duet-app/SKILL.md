---
name: duet-app
description: Build a new app from an idea, in 13 fixed stages. Use when the user says "duet app", wants to build an app, site or product from scratch, or has an idea and no code yet.
---

# duet app

Thirteen stages, fixed, held in `reference/presets/app.json`. Print
`duet_preset_banner app <n>` on every transition, so the human always knows
where they are and what is left.

Preflight first. If the repo is not set up, run `duet-setup`, then continue.

```
[1/13] Idea                 what you are making, in your words
[2/13] Users                who uses it, what they do first
[3/13] Budget and scale     money per month, how many people, by when
[4/13] Grill                questions until the spec has no holes
[5/13] Research             Codex finds what is actually current
[6/13] Architecture choice  you pick, in plain English      <- last question
[7/13] Documents            the files that stop agents drifting
[8/13] Scaffold             current official template, stripped
[9/13] Build                Claude the surface, Codex underneath
[10/13] Tests               to the coverage floor
[11/13] Debate              both agents argue once
[12/13] Polish              reads like a person wrote it
[13/13] Done                zero outstanding, three places
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

## Talk to a person, not a developer

Stages 1 to 3 use no technical words. Not "what's your stack", "what are you
making". Not "what are the personas", "who uses it". Somebody who has never
opened a terminal must be able to answer every question in the first six stages.

One question per turn. Wait for the answer.

## Research starts at stage 4, not stage 5

Send Codex the research brief the moment stage 3 finishes, so it runs while
grilling happens. The facts are then waiting when the architecture stage needs
them instead of being the thing everyone waits for.

Write the brief per `reference/briefing-codex.md`: open questions, no
hypothesis, verdict vocabulary required. The questions are listed in the preset
under `brief_must_ask`.

## Stage 6 is the last question about intent

Present one to three architectures. For each: what it is in one sentence, what
it costs per month, what it is good at, what it is bad at, what it stops you
doing later. Recommend one, say why. Offer a single option when there genuinely
is one good answer, and say that is why.

Every option must be grounded in the research briefing. An option you remember
is not an option, it is a guess.

**After the human chooses, stop asking about intent.** Questions accumulate
with `duet_question_add`, each carrying what you would do and why, and the run
proceeds on that recommendation with the work marked provisional. They all
arrive together at the end, already answered, so the project finishes whether
the human replies to all of them, some, or none.

Two exceptions, both of which reshape the project: a dependency violates the
researched safety standard, or the repository moved underneath a resumed run.

## Stage 7 documents get committed

Eight files from `reference/doc-templates/`, filled in properly, no placeholder
left behind. These are the anti-drift core and they belong in the repository.
Everything Duet uses to run belongs in `.duet/`, which is excluded.

## Stage 9 ownership is not negotiable

Claude builds everything the user sees and every word they read. Codex builds
everything underneath. Codex may raise a wording or interface concern by filing
it with the exact string and the reason; it does not edit it. Claude decides,
and an intentional choice stands.

This exists because a backend model asked to touch the interface writes four
paragraphs where the button needed two words.

## Stage 13 is not a formality

`reference/definition-of-done.md`. Zero outstanding locally, in tests, and
deployed. A check that cannot be run is recorded as outstanding, never skipped.
The fix loop is autonomous and may not finish by deleting the thing that failed.

## Output

Six lines or fewer per turn outside a gate. The banner, what is running, what
came back. Not a description of what you are about to do.
