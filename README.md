# Duet

You ask Claude to add Stripe subscriptions. It writes twenty confident lines
calling a method that was removed two versions ago. The code looks right. It
reviews well. It does not run.

That is not carelessness. **Its training data is older than your
dependencies**, and no amount of "please be careful" fixes a date problem.

Duet's answer: **Codex establishes the facts, then Claude writes the code.**

Codex is put to work reading current documentation, real API surfaces,
dependency versions and compatibility. Its findings are injected into Claude's
system prompt before Claude writes anything. Claude does what it is genuinely
good at, which is structure, logic and design, on top of facts it did not have
to remember.

Then they argue about the result, and you settle it.

---

## What it requires

- **Codex CLI.** Not the Codex desktop app. The app cannot be driven this way,
  and the resulting failure is baffling rather than obvious.
- **Claude Code.**
- Both logged in. Duet refuses to run on one agent, because with one agent it is
  not a degraded Duet, it is the CLI you already had.

## Install

One repo, both hosts. Codex reads Claude Code's plugin manifest format natively,
so there is nothing host-specific to install.

```bash
# Codex
codex plugin marketplace add mikheilkuzmidi/duet
codex plugin add duet@duet

# Claude Code
/plugin marketplace add mikheilkuzmidi/duet
/plugin install duet@duet
```

Then:

```bash
duet doctor     # checks both CLIs, auth, host detection, models, caps
```

## Use

```
/duet:duet  add rate limiting to the API
```

In Codex, reach it through `/skills`. Codex has no custom slash commands, so
onboarding is asymmetric and there is no way around that.

Individual stages work on their own:

| | |
|---|---|
| `duet research` | a Codex fact-finding pass, no code written |
| `duet plan` | generate the phase plan, run nothing |
| `duet build` | execute an approved plan |
| `duet debate` | the review exchange, over any branch, including work you wrote |
| `duet resume` | continue a run that stopped |

`duet debate` on a branch you wrote by hand is probably the fastest way to see
whether this is useful to you.

## How a run goes

**Phases are generated for your task**, not filled into a template. A typical
shape:

1. Claude grills you to a near-complete spec, one question at a time. Codex
   research runs concurrently, so the facts are ready when the spec is.
2. Codex proposes the dependency set and challenges the stack choice.
3. Phases are routed by capability and shown to you for approval.
4. Any phase needing both facts and judgement **splits in two**: a Codex brief,
   then a Claude phase grounded on it.
5. Codex authors the tests.
6. Codex sends a batched list of concerns, Claude answers all of them, Codex
   pushes back once, Claude fixes what was genuinely wrong.
7. Anything still disputed comes to you with both arguments laid out.

Once implementation starts, Duet stops asking about intent. Questions
accumulate into a single final round where **each one arrives with a recommended
answer already selected**, so the project finishes whether you answer all of
them, some, or none.

## Rules, not rails

Duet carries [seven standing rules](reference/standing-rules.md) into every
delegated call. Each states what and why, because a rule you understand adapts
to a situation it never anticipated and a rule you merely obey does not.

**Nothing enforces them.** An agent may depart from any rule when the task calls
for it, but it has to say so, and the departure appears on the plan you approve.
Departing is allowed. Departing silently is not.

## Configuration

```bash
duet config agents.max 3            # parallel agents. Default 3, ceiling 10
duet config budget.warnUsd 5        # warn past this spend
duet config budget.stopUsd 20       # hard stop, checkpointed and resumable
duet config permissions.bypass true # fast mode, see below
```

Global by default, with an optional per-project override. Duet writes nothing
into your repository except the run directory, and it asks before that.

## Limitations

Stated here rather than discovered later, because a tool whose entire premise is
refusing to overstate what it knows cannot have a README that overstates what it
does.

- **Most phases pay an extra Codex hop.** Splitting mixed phases into brief plus
  work is what keeps Claude honest, and it is not free. Briefs are cached within
  a run, and pure-logic phases skip them, but Duet is slower than one agent
  guessing confidently.
- **Spend visibility is partial.** Duet measures its own cost exactly. No
  platform exposes remaining plan budget to a tool, so it cannot see what you
  spent elsewhere, and the agent cap is a blunt instrument for that reason.
- **Onboarding is asymmetric.** Claude Code gets `/duet:*`. Codex does not
  support custom slash commands.
- **Fast mode turns off your safety net.** `permissions.bypass true` passes
  `--dangerously-skip-permissions` to Claude and `danger-full-access` to Codex.
  It removes the constant "can I edit this file" prompts that make long runs
  unpleasant. It also means the plan approval gate stops stopping anything, and
  Claude's auto-mode classifier may refuse to launch delegated agents at all. If
  that happens Duet tells you exactly what happened instead of hanging. Off by
  default, offered once, never enabled silently.
- **Codex to Claude delegation needs a loosened sandbox.** Codex's sandbox kills
  DNS to `api.anthropic.com`, so Codex-orchestrates mode requires
  `danger-full-access`. Duet explains this rather than enabling it quietly.
  Claude-orchestrates, the default, works unmodified.
- **Version 0.1.0.** The core loop works. It has not been run by anyone but its
  author.

## Design notes

Every decision behind this, and the research that produced it, is in the
[issue tracker](https://github.com/mikheilkuzmidi/duet/issues?q=is%3Aissue).
[Issue #1](https://github.com/mikheilkuzmidi/duet/issues/1) is the map: what was
decided, why, and what was ruled out. The dead ends are recorded too, including
the ones that cost the most time.

## Credit

The decision-mapping approach that produced this repo was inspired by the
`wayfinder` skill from [mattpocock/skills](https://github.com/mattpocock/skills)
(MIT). Duet's mechanics are its own, but the idea of charting an effort as
decision tickets with a fog frontier came from there, and it deserves saying.

## Licence

MIT. See [LICENSE](LICENSE).
