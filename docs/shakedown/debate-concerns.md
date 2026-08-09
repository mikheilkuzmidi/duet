# Review concerns

Provisional: I would have asked whether the write stage completed in another
checkout. Recommendation: treat the workspace artifact as authoritative and
block the release-skill review until it exists here.

1. BLOCKER: the reviewed skill does not exist.
   - What is wrong: `skills/duet-release/SKILL.md` is absent.
   - Where: workspace-relative path `skills/duet-release/SKILL.md`.
   - Why it matters: The description, rules and procedural claims cannot be
     reviewed. This blocks the intended-trigger, near-miss, rule-reason,
     em-dash and behaviour-to-procedure checks. It also fails the write-stage
     acceptance condition.
   - Source: `test -f skills/duet-release/SKILL.md` exits 1. `run.sh:25`
     requires the file, `name: duet-release`, and `description:`. The recorded
     trigger probe reports all five intended phrases as `MISS` in
     `.duet/runs/shake/phases/6/out.md:2-6`.

2. BLOCKER: the near-miss probe is not evidence of correct non-triggering.
   - What is wrong: It reports `ok` for two near misses while the target
     file is absent.
   - Where: `.duet/runs/shake/phases/6/out.md:8-9`, produced by
     `run.sh:41-42`.
   - Why it matters: A failed `grep` for a missing file follows the same
     branch as a phrase not found. The two `ok` results therefore cannot show
     that the description excludes those near misses. Actual model firing is
     additionally unverified because the documented contract gives no
     deterministic matcher.
   - Source: `run.sh:42` maps any nonzero `grep` result to `ok`; the target
     file is absent per concern 1. `.duet/runs/shake/phases/4/out.md:58`
     records that no deterministic matcher, threshold or invocation guarantee
     is documented.
