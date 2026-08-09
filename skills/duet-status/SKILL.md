---
name: duet-status
description: Show which stage the current run is on and what is left. Use when the user says "duet status", asks where a run got to, or asks what is still outstanding.
---

# duet status

Where the run is. Nothing runs, nothing changes.

## Before anything

Run `duet doctor`. **If it reports the repo is not set up, run the
`duet-setup` skill now, to completion, then carry straight on with what was
asked.** The human asked for something; setup is the questions Duet needs before
it can do it, not a separate errand for them to run.

```bash
duet status
```

## What it shows

```
run 20260810T140212Z-a1b2c3d4   preset app
  x [1/13] Idea
  x [2/13] Users
  ...
  > [6/13] Architecture choice   waiting on you
    [7/13] Documents
    ...

  spend so far: $1.84 across 5 phases
  questions waiting: 3
  assumptions made: 2
```

`x` done, `>` current, blank not started. Done means the output file exists,
which is the same test resume uses, because writes are atomic and there is no
half-finished state to disagree about.

## Say what is blocking

If the current stage is a gate, say what it is waiting for, in one line. If a
phase failed, say which and point at the `.err` file. If a run is older than
`resume.researchMaxAgeHours`, say the research will re-run on resume and why.

## Do not

Summarise the work so far. Explain the stages. Recommend anything. They asked
where it is.
