---
name: duet-max
description: Set this repo wide open in one step, for people who read diffs. Use when the user says "max allowance", "duet max", or wants Duet configured for maximum autonomy without answering the setup questions.
---

# duet: max allowance

The express path. One command instead of ten questions, set as open as Duet
goes.

**This is for professionals.** Say so, show what it turns on, and get one
deliberate confirmation before writing anything.

## Show it first

```bash
duet setup --max
```

With no confirmation phrase that prints the disclaimer and writes nothing:

```
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
```

Do not soften that paragraph. Somebody should meet the sentence before it is
true rather than afterwards.

## Then confirm

```bash
duet setup --max --confirm "max allowance"
```

The phrase is deliberate friction, and it is the only friction in this mode.

## Why three things stay on the list

Max mode is not "no guards", it is **no interruptions**. Those are different,
and conflating them is how people lose an afternoon of work to a force push.

Three actions cannot be undone by reading a diff afterwards: pushing to `main`,
touching production data, deleting outside the working tree. In this mode they
do not stop the run and they do not prompt. Duet declines to perform them,
queues each one with its exact command and a recommendation, and carries on with
everything else. They arrive together at the finish, where one yes runs them.

So the run is never interrupted, and the three genuinely unrecoverable things
still take one deliberate yes. A mode that stops is not max. A mode that force
pushes unasked is not defensible.

If somebody wants those queued items gone as well:

```bash
duet config safety.alwaysAsk none local
```

Say plainly what that removes. Do not do it on their behalf.

## Grilling stays on

`grill.depth` remains `normal` even here, because grilling is not an
interruption to the build, it happens before the build, and a fully autonomous
run against a spec full of holes produces a finished implementation of the wrong
thing. That is the most expensive possible outcome and this mode makes it fast.

Anyone who genuinely wants none of it can set `grill.depth=off`, and should know
that Duet will then record its assumptions rather than ask about them.
