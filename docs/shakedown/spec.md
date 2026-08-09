# duet-release

## [1/8] Idea
A skill that cuts a release: bump the version, write the changelog entry from
what actually changed, commit, tag, and publish a GitHub release. One command
instead of five hand-typed steps that are easy to do in the wrong order.

## [2/8] Triggers
Should fire:  "duet release", "cut a release", "ship a release", "tag and
release this", "publish v0.5.0", "release it"
Must NOT fire: "release the lock", "release notes for last month" (reading, not
cutting), "deploy to production" (that is land-and-deploy, a different thing),
"git push" on its own.

## [3/8] Never do this
- Never push to main. Tag and release only; branch state is the human's call.
- Never invent a version. Derive it from the changelog and the last tag, and
  refuse if they disagree.
- Never write a changelog entry from the diff alone. Entries come from what
  changed for a user, not from what changed in the files.
- Never publish a release from a dirty working tree.
