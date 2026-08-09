---
name: duet-release
description: Cut a GitHub release from the repository changelog. Use for "duet release", "cut a release", "ship a release", "tag and release this", or "publish v0.5.0" when the request means to commit a verified version bump, tag it, and publish with gh. Do not use for unlocking a resource, retrospective release notes, or deployment to production.
---

# Duet release

Cut a release from an explicit CHANGELOG entry.
Do not infer its scope from the diff.

## Rules

Never push to `main`.
The release must not alter the main branch, because branch state is the
human's decision. Push only the release tag required to publish the release.

Never invent a version.
The CHANGELOG names the release, and Git establishes the released baseline.
Guessing a patch, minor, or major bump makes a published compatibility promise
without evidence.

Never write release notes from the diff alone.
Use the matching CHANGELOG section, because a diff reports file changes rather
than the user-facing change being released.

Never release from a dirty working tree.
Unrelated changes can be committed, tagged, or published by accident.

## Preconditions

1. Read the repository release documentation and identify every authoritative
   version file. If the version source cannot be identified, refuse to release.
2. Confirm GitHub CLI authentication and the target repository:

   ```bash
   gh auth status
   gh repo view --json nameWithOwner
   ```

3. Require a clean starting tree:

   ```bash
   test -z "$(git status --porcelain=v1)"
   ```

   Refuse on any output. Do not stash, reset, or clean another person's work.
4. Fetch release tags without changing a branch:

   ```bash
   git fetch --tags origin
   last_tag=$(git describe --tags --abbrev=0)
   ```

   Refuse if there is no previous release tag. A first release needs an
   explicit repository convention and must not be guessed.

## Determine the version and notes

1. Locate the top release heading in `CHANGELOG` or `CHANGELOG.md`.
   Extract its semantic version as `next_version`, accepting one optional
   leading `v`. A top `Unreleased` heading is not a version.
2. Normalize the version in `last_tag` as `last_tag_version` and compare it
   with `next_version`.
   The proposed version must be a valid successor to the last tag under the
   repository's documented release convention. Refuse when the changelog and
   tag disagree, when either is ambiguous, or when the proposed tag already
   exists locally or on `origin`.
3. Confirm every authoritative version file already names `next_version`, or
   update only those files. Do not derive a replacement version from the tag.
4. Extract exactly the `next_version` section, from its heading to the next
   heading at the same level. Start with `notes_file=$(mktemp)` and write only
   that section to it. Do not use `git diff`, `git log`, or generated notes as
   its source.
5. Review the staged version bump and notes source:

   ```bash
   git diff --check
   git diff -- <authoritative-version-files> <changed-changelog-file>
   ```

   Refuse if the changelog section and version files do not identify the same
   normalized version.

## Commit, tag, and publish

1. Stage only the authoritative version files and CHANGELOG when it changed.
   Commit the version bump with the target version in the commit message:

   ```bash
   git add -- <authoritative-version-files> <changed-changelog-file>
   git commit -m "chore(release): $next_tag"
   ```
2. Recheck the index and working tree. After the commit, require a clean tree
   before tagging:

   ```bash
   test -z "$(git status --porcelain=v1)"
   ```

3. Create an annotated tag. Preserve the prefix used by `last_tag`, then
   confirm that the tag points at the release commit:

   ```bash
   tag_prefix="${last_tag%"$last_tag_version"}"
   next_tag="${tag_prefix}${next_version}"
   git tag -a "$next_tag" -m "Release $next_tag"
   test "$(git rev-list -n 1 "$next_tag")" = "$(git rev-parse HEAD)"
   ```

4. Push only the tag. Never push `HEAD`, the current branch, or `main`:

   ```bash
   git push origin "$next_tag"
   ```

5. Publish using the saved CHANGELOG section and require the pushed tag:

   ```bash
   gh release create "$next_tag" \
     --verify-tag \
     --title "$next_tag" \
     --notes-file "$notes_file"
   ```

6. Verify the published release targets the expected tag:

   ```bash
   gh release view "$next_tag" --json tagName,targetCommitish,url
   ```

Report the tag, commit, and release URL. Report a refusal with the failed
check and leave repository state unchanged where possible.
