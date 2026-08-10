---
name: duet-setup
description: Set Duet up for this repo. Asked once, answers stay on this machine. Use when the user says "duet setup", when Duet reports the repo is not set up, or before the first Duet run in a project.
---

# duet setup

Ten questions, once per repo. Answers live in `.duet/config.json`, excluded
locally, so they are per-repo and per-device and never travel to anyone else.

## When this runs by itself

Every other Duet skill runs this one automatically when a repo has no
`.duet/config.json`. In that case the human did not ask to be set up, they asked
for something else, so:

- Say in one line why this is happening: "First time here, so ten quick
  questions before I start."
- Ask them.
- **Then carry straight on with what they originally asked for.** Do not report
  that setup finished and stop. Finishing setup and waiting is the failure mode
  this replaced.

## Before the first question

Somebody running this for the first time has no idea what is about to happen or
how long it takes. Four steps, then start.

**1. Introduce it, in four lines. Not more.**

```
Duet runs Claude and Codex together.
  Claude leads, and writes everything you see and read.
  Codex checks what is currently true, and builds underneath.
They argue about the result at the end, and you settle it.
Nothing is written outside .duet/ until you say so.
```

**2. Offer the map.** "Want the list of what Duet can do first?" On yes, one
line per command from the table in `duet help`. On no, carry on. Do not print it
unasked; somebody who already knows does not need it twice.

**3. Say the cost.** "Ten questions, about two minutes. Every one has a
recommended answer, so you can accept your way through it. Ready?"

No is a real answer. Print the `duet setup --max` line and stop.

**4. Check both CLIs**, with `duet_preflight`. Missing or logged out gets fixed
here, not discovered at question nine.

## The ten questions

One at a time. Wait for each answer. Two pairs travel together, which is what
keeps twelve keys down to ten questions.

| Ask | Key | Default |
|---|---|---|
| How should I talk to you: plain English, or straight technical? | `voice` | `plain` |
| Should I question you about the plan first, or build what you asked? | `grill.depth` | `normal` |
| How autonomous should I be? | `autonomy` | `product` |
| What should I never do without asking? | `safety.alwaysAsk` | three items |
| When I hit one of those, stop and ask, or queue it for the end? | `safety.mode` | `ask-now` |
| Should I commit as I go? | `git.mode` | `branch` |
| How many agents at once, Claude and Codex? | `agents.*.max` | 2 and 2 |
| Want to see progress while I work? | `progress.mode` | `heartbeat` |
| Skip the "can I edit this file" prompts? | `permissions.bypass` | **true** |
| Coverage floor before anything counts as done? | `done.coverageMin` | 80 |

Explain each in the answer text, never in a paragraph after it:

- **voice** changes the wording of every question after this one.
- **grill** `off` builds what you asked. `normal` asks what would change the
  build. `hard` argues with the idea itself, and may conclude you should not
  build it.
- **autonomy** `full` decides everything and brings every question to the
  finish. `product` decides technical things alone and stops when a choice
  changes what someone sees or reads. `off` stops at every decision.
- **safety** the three defaults are the things a diff cannot undo: pushing to
  main, touching production data, deleting outside the working tree. **The list
  is open.** Offer those plus `global-install`, `paid-api` and
  `rewrite-history`, and accept anything else they name in the same shape, like
  `deploy-to-production` or `charge-a-customer`. Most real dangers are specific
  to one project, so a fixed vocabulary would exclude exactly the entries worth
  having. An unfamiliar item is accepted with a warning about spelling, because
  it fires only when an agent names that action by the same name.
- **safety.mode** `ask-now` stops and waits. `defer-to-final` never stops: the
  action does not happen, it queues with its exact command for the end. Pick
  that one if being interrupted is worse than waiting.
- **git** `branch` is the default because a thirteen stage run with no commits
  cannot be reviewed, bisected, or partly kept.
- **progress** `heartbeat` is one line a minute and costs nothing. `digest`
  adds a summary of what Codex found every few minutes, **and that one uses
  extra quota**. `window` opens a second terminal running Codex live.
- **no money question here.** Duet does not ask what it may spend on itself,
  because Codex exposes no dollar figure to the CLI and a ceiling that counts
  only Claude's half would be a number that looks complete and is not. On a
  subscription the real ceiling is the rate limit, and `duet goal status` reads
  it properly. The one money question Duet does ask is the project's monthly
  running cost, and it belongs in the app preset where it is about hosting.
  `budget.warnUsd` and `budget.stopUsd` still work if set by hand.
- **fast mode is recommended on**, and say why in both directions: without it,
  every file edit stops and asks, which makes a long run unusable. With it, the
  plan approval gate also stops gating, and Claude's auto-mode classifier may
  refuse to launch delegated agents, in which case Duet says exactly that rather
  than hanging.

## Then detect the commands

Not a question. Duet reads `package.json`, the lockfile, `Makefile`,
`pyproject.toml`, CI workflows and any deploy config, and shows one block with
the evidence for each guess:

```
Detected in this project
  install    npm ci                  package-lock.json
  test       npm test                package.json scripts.test
  typecheck  npx tsc --noEmit        tsconfig.json, no script
  deploy     vercel --prod           .vercel/project.json

Anything wrong? (enter = all correct)
```

These are load bearing. Every preset stage is finished when a command exits
zero, and those are the commands. They also fill the blanks in the generated
documents and make the deployed leg of the done check real.

An empty project detects nothing, which is correct: the scaffold stage fills
them in from the template it uses.

## Write it

```bash
duet setup voice=plain grill.depth=normal autonomy=product \
  safety.alwaysAsk=push-to-main,production-data,delete-outside-tree \
  safety.mode=ask-now git.mode=branch \
  agents.claude.max=2 agents.codex.max=2 progress.mode=heartbeat \
  permissions.bypass=true done.coverageMin=80
```

Anything not passed takes its default. Values are validated, `.duet/` and
`*.err` go into `.git/info/exclude`, which is local and untracked, and the
detected commands are saved.

**Not ignored, deliberately:** `CLAUDE.md`, `AGENTS.md` and `docs/`. They are
what stop the next agent drifting, and an anti-drift document living on one
laptop has failed at its job.

## Finish in three lines

```
setup written to .duet/config.json (local, not committed)
  plain · grill normal · autonomy product · git branch · claude 2 · codex 2
  change one: duet config <key> <value> local
```

Nothing else. They asked to be set up, not to be taught.
