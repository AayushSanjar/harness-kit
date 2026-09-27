#!/usr/bin/env bash
# Apply a patch to the working tree, then run the project's approval and check.
#
#   land.sh <patch>
#
# For people, in their own terminal, run from anywhere inside the project's git
# repository. In order, stopping at the first failure with a message that says what state
# the tree is in and what to do:
#   0. .harness/check-command       its first line must exist and carry --skip-reviewed as a
#                                   word: the review belongs to ship.sh (review.sh reviews
#                                   commits, and nothing is committed yet), and CI runs the
#                                   whole check. land.sh never adds the flag itself, so it
#                                   never guesses where a compound line takes it; without
#                                   it, land.sh stops here, before applying anything, and
#                                   prints how to add it.
#   1. git apply --check <patch>    the patch must apply cleanly; if not, nothing changes
#   2. git apply <patch>
#   3. .harness/approve-command     optional; first line, run in the project. It may prompt
#                                   the person, so it keeps the terminal's input.
#   4. .harness/check-command       the first line, as it is, run in the project.
# It never commits and never pushes; on success it prints what to do next.
#
# Exit status: 0 landed and checked; 1 stopped (the message says whether the patch is
# applied); 2 usage.
set -u

say() { echo "harness-kit land.sh: $*" >&2; }

if [ $# -ne 1 ]; then
  echo "usage: land.sh <patch>" >&2
  exit 2
fi
case "$1" in /*) patch="$1" ;; *) patch="$PWD/$1" ;; esac
[ -f "$patch" ] || { say "no such patch file: $1"; exit 2; }

PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || { say "not inside a git repository"; exit 2; }
cd "$PROJECT" || exit 2
H="$PROJECT/.harness"
UNDO="To undo it: git apply -R '$patch'"

first_line() { [ -f "$1" ] && head -n 1 "$1" | tr -d '\r'; }

# 0. The check must skip the review check; nothing is applied until it does.
check="$(first_line "$H/check-command")"
if [ -z "$check" ]; then
  say "STOPPED: no .harness/check-command (or its first line is empty), so there is nothing to check the patch with. Nothing was changed."
  say "Next: put the project's check on the first line of .harness/check-command, with --skip-reviewed, then run land.sh again."
  exit 1
fi
if ! grep -qE '(^|[[:space:]])--skip-reviewed([[:space:]]|$)' <<<"$check"; then
  say "STOPPED: .harness/check-command does not pass --skip-reviewed, so it would run the review check, which belongs to ship.sh (nothing is committed yet). Nothing was changed."
  say "Next: add the flag where the project's check reads it, and make the check skip check-reviewed.mjs when given it. For a single command, the first line becomes:"
  say "    $(sed -E 's/[[:space:]]+$//' <<<"$check") --skip-reviewed"
  say "Then run land.sh again. CI still runs the whole check, without the flag."
  exit 1
fi

# 1-2. The patch.
if ! git apply --check "$patch"; then
  say "STOPPED: the patch does not apply cleanly (git apply --check failed, above). Nothing was changed."
  say "Next: update the branch or regenerate the patch, then run land.sh again."
  exit 1
fi
if ! git apply "$patch"; then
  say "STOPPED: git apply failed after --check passed. Look at 'git status' before doing anything else."
  exit 1
fi
say "applied $patch"

# 3. Approval, if the project has one.
approve="$(first_line "$H/approve-command")"
if [ -n "$approve" ]; then
  say "running the approval command: $approve"
  /bin/sh -c "$approve"
  status=$?
  if [ "$status" -ne 0 ]; then
    say "STOPPED: the approval command failed or was declined (exit $status). The patch IS applied and nothing was committed. $UNDO"
    exit 1
  fi
fi

# 4. The check, with --skip-reviewed (step 0).
say "running the check: $check"
/bin/sh -c "$check" </dev/null
status=$?
if [ "$status" -ne 0 ]; then
  say "STOPPED: the check failed (exit $status): $check. The patch IS applied and nothing was committed."
  say "Next: fix what the check reports and run it again, or: git apply -R '$patch'"
  exit 1
fi

say "LANDED: the patch applied and the check passed. Nothing was committed or pushed."
say "Next: read 'git diff', commit it on this branch, then run ship.sh to review, push, wait for CI and merge."
exit 0
