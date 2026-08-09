# The shakedown

The first end-to-end run of a Duet preset, kept because a tool that refuses to
overstate what it knows should show its working.

`/duet:duet-skill` was run to build `duet-release`, the skill that cuts a
release. Eight stages, real delegations, no staged output. What is in this
directory is what the run actually produced.

| | |
|---|---|
| `spec.md` | stages 1 to 3, the three gates answered |
| `research-briefing.md` | stage 4, Codex against primary sources. 11 VERIFIED, 1 CONTRADICTED, 1 UNVERIFIABLE, every claim with a link |
| `debate-concerns.md` | stage 7, Codex's batched review |
| `debate-rebuttal.md` | stage 7, the answer to it |

The product is `skills/duet-release/SKILL.md`, written by a goal that finished
when its gate command exited zero.

## What it broke, which was the point

Four defects, none of which any amount of reading would have found:

- **The libraries could not be sourced from zsh**, the default shell on macOS
  and the one the orchestrator runs in. The goal path was unreachable from the
  exact shell the skills told it to use.
- **`duet_gate_resolve` looped forever under zsh**, because `BASH_REMATCH[1]`
  holds the whole match there rather than the first group. A hang, which is the
  worst failure shape: no error, no output, and the human kills the run
  believing the model is thinking.
- **A goal objective is capped at 4000 characters.** Undocumented. Found by
  sending 9,237 and reading the error.
- **The trigger test could not tell "phrase absent" from "file missing"**, so it
  would have reported a pass for a skill that was never written. The debate
  stage found this one, which is what the debate stage is for.

The first three are fixed in 0.4.0. The fourth is fixed in the preset itself.

## What it got right

The debate also filed a BLOCKER saying the skill did not exist. It did: written
at 03:30:46, first read by the reviewer at 03:31:00. That concern was refuted
with timestamps rather than conceded, which is standing rule 5 doing its job.
Conceding a point you believe is wrong in order to end an argument is the
failure mode that makes review theatre.
