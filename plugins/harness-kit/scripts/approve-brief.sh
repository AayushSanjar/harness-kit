#!/usr/bin/env bash
# Approve the current branch's brief: the person's step between /plan and the work.
#
#   approve-brief.sh     run from anywhere inside the project's git repository, on the branch
#
# For people, in their own terminal. The plan skill (/plan <goal>) writes the brief to
# .reports/<branch>.brief.md; this shows it, asks "Approve this brief? [y/N]", and on y
# writes .reports/<branch>.brief.approved holding the brief's sha256 (brief-lib.sh). Any
# later change to the brief, even one character, makes the approval stop matching: ship.sh
# then stops before the review, and review.sh tells the reviewer. Run this again to approve
# the brief as it is now.
#
# It refuses (exit 2), writing nothing, when stdin is not a terminal: the answer must come
# from the person reading the brief, not from a pipe or from Claude's shell. The git-guard
# hook also denies it to Claude. On a detached HEAD there is no branch, so no brief. With no
# brief it stops (exit 1) and says to run /plan. Any answer but y or yes (in any case)
# writes nothing and leaves an earlier approval as it was (exit 1).
#
# Exit status: 0 approved; 1 not approved (no brief, or not y); 2 refused.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=brief-lib.sh
. "$HERE/brief-lib.sh"

say() { echo "harness-kit approve-brief.sh: $*" >&2; }
refuse() { say "REFUSED: $*"; exit 2; }

PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse "not inside a git repository"
branch="$(git symbolic-ref --short -q HEAD)" || refuse "HEAD is detached; check out the branch whose brief you are approving"
brief_load "$PROJECT" "$branch" || refuse "$BRIEF_ERROR"
if [ "$BRIEF_STATE" = missing ]; then
  say "there is no brief for $branch ($BRIEF). In Claude, run /plan <goal> to write it, then run approve-brief.sh again. Nothing was written."
  exit 1
fi
[ -t 0 ] || refuse "stdin is not a terminal, so the answer could not come from you reading the brief. Run it yourself, in your own terminal: $HERE/approve-brief.sh. Nothing was written."

# What is shown is what is approved: a copy, and the copy's sha256, so a change to the
# brief while the person reads it is not approved unseen.
shown="$(mktemp "${TMPDIR:-/tmp}/harness-kit-brief.XXXXXX")" || { say "cannot make a temporary file. Nothing was written."; exit 1; }
trap 'rm -f "$shown"' EXIT
cp "$PROJECT/$BRIEF" "$shown" || { say "cannot read $BRIEF. Nothing was written."; exit 1; }
sha="$(brief_sha256 "$shown")"
echo "=== $BRIEF (sha256 $sha) ==="
cat "$shown"
echo "=== end of $BRIEF ==="
case "$BRIEF_STATE" in
  approved) say "note: this brief is already approved as it is; answering y records the same approval again" ;;
  changed) say "note: the brief changed after it was approved; the earlier approval ($BRIEF_APPROVAL) no longer matches it" ;;
esac
printf 'Approve this brief? [y/N] ' >&2
answer=""
IFS= read -r answer
case "$answer" in
  [yY] | [yY][eE][sS]) ;;
  *)
    say "not approved (answer \"$answer\"). Nothing was written. Ask Claude to change the brief, then run approve-brief.sh again."
    exit 1
    ;;
esac
printf '%s\n' "$sha" >"$PROJECT/$BRIEF_APPROVAL" || { say "could not write $BRIEF_APPROVAL"; exit 1; }
say "APPROVED: $BRIEF_APPROVAL holds the brief's sha256 ($sha). A change to the brief needs a new approval."
exit 0
