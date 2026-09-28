#!/usr/bin/env bash
# Check, push, wait for CI, fast-forward the base branch and push it with a tag: the last
# step for a repository whose branches are not reviewed through ship.sh, such as
# harness-kit's own.
#
#   release.sh <tag>     e.g. release.sh v0.13.0; run from anywhere inside the project's git
#                        repository, on the branch to release
#
# For people, in their own terminal: this pushes. In order, stopping at the first failure
# with a message saying what to do:
#   1. Refuse on the base branch (.harness/review-base, first line, default main), on a
#      detached HEAD, with uncommitted changes to tracked files, with a tag name git does
#      not accept, or when <tag> already exists (locally or on origin) at another commit
#      than the branch's head.
#   2. Run the project's check: the first line of .harness/check-command, as it is, in the
#      project root (in harness-kit, bash tests/validate.sh --skip-reviewed). With no
#      check-command it stops: a release is never made unchecked.
#   3. Push the branch to origin.
#   4. Wait for CI (ci-lib.sh's ci_wait): the runs for the pushed head commit, waiting up to
#      SHIP_CI_APPEAR_SECONDS (default 180) for the first to appear, each until it
#      finishes; anything but "success" stops, printing the run's URL. With
#      .harness/ci-workflow, only that workflow's runs.
#   5. Fast-forward the base to the branch's head: origin/<base> and <base> must both be in
#      the branch; `git fetch . <head>:<base>` moves the local base (fast-forward only).
#      Make the tag at the head (a lightweight tag, as harness-kit's earlier ones are),
#      unless it is there already, then push the base and the tag together
#      (git push --atomic), with HARNESS_KIT_SHIP=1 set: the pre-push hook from
#      install-hooks.sh lets that push of the base through. Then switch to the base.
# It never forces a push, never rewrites history, never moves an existing tag, and never
# deletes the branch.
#
# RESUMABLE. Re-running with the same tag after a stop continues where it stopped: the
# check runs again (it is cheap next to a release), pushing a pushed branch does nothing, a
# finished CI run is read, not re-run, a base already fast-forwarded and a tag already at
# the head are kept.
#
# THE NOTIFICATION. On macOS, each STOPPED and the RELEASED also show a notification, as a
# release waits minutes for CI (ci-lib.sh's ci_notify). Refusals come at once, so they do
# not.
#
# THE EVENT LOG. Each stop and each refusal (event STOPPED, with a short reason; a
# refusal's starts "refused-"), and each RELEASED (what: the tag), is appended to the local
# event log, .git/harness-kit/events.tsv (events.sh has the format).
#
# Exit status: 0 released; 1 stopped (re-run after doing what the message says); 2 refused.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE=origin

# shellcheck source=events.sh
. "$HERE/events.sh"
# shellcheck source=ci-lib.sh
. "$HERE/ci-lib.sh"
CI_TOOL=release.sh CI_APPEAR="${SHIP_CI_APPEAR_SECONDS:-180}" CI_POLL="${SHIP_POLL_SECONDS:-10}"

say() { echo "harness-kit release.sh: $*" >&2; }
refuse() { harness_event release.sh "${branch:-}" STOPPED "$1" "REFUSED: $2"; say "REFUSED: $2"; exit 2; }
stop() { harness_event release.sh "${branch:-}" STOPPED "$1" "$2"; say "STOPPED: $2"; ci_notify "STOPPED: $2"; exit 1; }

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "usage: release.sh <tag>   (for example: release.sh v0.13.0)" >&2
  exit 2
fi
tag="$1"

PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse refused-not-a-repository "not inside a git repository"
cd "$PROJECT" || exit 2
base="$( { [ -f .harness/review-base ] && head -n 1 .harness/review-base; } | tr -d '\r' | tr -d '[:space:]')"
base="${base:-main}"

# ---------------------------------------------------------------------------------------
# 1. Where we are.
# ---------------------------------------------------------------------------------------
branch="$(git symbolic-ref --short -q HEAD)" || refuse refused-detached "HEAD is detached; check out the branch to release"
[ "$branch" != "$base" ] || refuse refused-on-base "you are on $base; check out the branch to release"
[ -z "$(git status --porcelain --untracked-files=no)" ] || refuse refused-uncommitted "there are uncommitted changes (git status); commit or stash them first"
git check-ref-format "refs/tags/$tag" || refuse refused-bad-tag "\"$tag\" is not a tag name git accepts"
head="$(git rev-parse HEAD)"
local_tag="$(git rev-parse -q --verify "refs/tags/$tag^{commit}")"
[ -z "$local_tag" ] || [ "$local_tag" = "$head" ] ||
  refuse refused-tag-exists "the tag $tag already exists here at $(git rev-parse --short "$local_tag"), not at $branch's head $(git rev-parse --short "$head"). Choose another tag; release.sh never moves one."
remote_tag="$(git ls-remote --tags "$REMOTE" "refs/tags/$tag^{}" "refs/tags/$tag" | awk 'END { print $1 }')"
[ -z "$remote_tag" ] || [ "$remote_tag" = "$head" ] ||
  refuse refused-tag-exists "the tag $tag already exists on $REMOTE at ${remote_tag:0:7}, not at $branch's head $(git rev-parse --short "$head"). Choose another tag; release.sh never moves one."

# ---------------------------------------------------------------------------------------
# 2. The check.
# ---------------------------------------------------------------------------------------
check="$( { [ -f .harness/check-command ] && head -n 1 .harness/check-command; } | tr -d '\r')"
[ -n "$check" ] || stop no-check-command "there is no .harness/check-command (or its first line is empty), so there is no check to release with. Nothing was pushed."
say "running the check: $check"
/bin/sh -c "$check" </dev/null >&2
status=$?
[ "$status" -eq 0 ] || stop check-failed "the check failed (exit $status, above): $check. Nothing was pushed. Fix what it reports, commit, then re-run release.sh $tag."

# ---------------------------------------------------------------------------------------
# 3. Push the branch.
# ---------------------------------------------------------------------------------------
git push -q -u "$REMOTE" "$branch" || stop push-branch-failed "pushing $branch to $REMOTE failed (above). Fix the cause, then re-run release.sh $tag."
say "pushed $branch ($(git rev-parse --short "$head")) to $REMOTE"

# ---------------------------------------------------------------------------------------
# 4. CI for the pushed head.
# ---------------------------------------------------------------------------------------
ci_wait "$head" "$branch"

# ---------------------------------------------------------------------------------------
# 5. Fast-forward the base, tag, push both, switch to the base.
# ---------------------------------------------------------------------------------------
git fetch -q "$REMOTE" "$base" || stop fetch-failed "could not fetch $base from $REMOTE (above). Re-run release.sh $tag."
for ref in "refs/remotes/$REMOTE/$base" "refs/heads/$base"; do
  if git rev-parse -q --verify "$ref" >/dev/null && ! git merge-base --is-ancestor "$ref" "$head"; then
    stop base-not-fast-forward "${ref#refs/*/} has commits that $branch does not, so $base cannot fast-forward. Bring $branch up to date with $base, then re-run release.sh $tag."
  fi
done
git fetch -q . "$head:refs/heads/$base" ||
  stop base-not-updated "could not fast-forward $base to $branch (above; is $base checked out in another worktree?). Nothing was pushed to it. Fix the cause, then re-run release.sh $tag."
if [ -z "$local_tag" ]; then
  git tag "$tag" "$head" || stop tag-failed "could not make the tag $tag (above). $base is fast-forwarded locally; nothing was pushed to it. Re-run release.sh $tag."
fi
# HARNESS_KIT_SHIP=1: the pre-push hook (install-hooks.sh) lets this push of the base through.
HARNESS_KIT_SHIP=1 git push -q --atomic "$REMOTE" "refs/heads/$base:refs/heads/$base" "refs/tags/$tag:refs/tags/$tag" ||
  stop push-base-failed "pushing $base and $tag to $REMOTE failed (above); neither was pushed (--atomic). $base is fast-forwarded locally and $tag made. Fix the cause, then re-run release.sh $tag."
git checkout -q "$base" || stop checkout-failed "$base and $tag are pushed, but switching to $base failed (above). Switch to $base yourself."
harness_event release.sh "$branch" RELEASED "$tag" "fast-forwarded $base to $(git rev-parse --short "$head") and pushed it with $tag"
say "RELEASED: $branch ($(git rev-parse --short "$head")) is $base on $REMOTE, tagged $tag. You are on $base."
ci_notify "RELEASED: $tag ($branch) is pushed as $base."
exit 0
