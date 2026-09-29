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
#   4. .harness/check-command       the first line, as it is, run in the project, under the
#                                   time-limit helper's check limit (time-limit.mjs, 540
#                                   seconds by default): past it, the check is stopped with
#                                   its whole process group and land.sh stops, check-timeout.
#   5. Fault replays                optional; when .harness/mutations.tsv has entries that
#                                   the patch may have broken, or that the patch adds or
#                                   changes, replay-faults.sh runs those entries (and
#                                   only those) on the patched working tree; a SURVIVED
#                                   or ERROR stops here. Otherwise it prints "no
#                                   replays needed".
# It never commits and never pushes; on success it prints what to do next.
#
# THE EVENT LOG. Each STOPPED, with a short reason (no-check-command, no-skip-reviewed,
# patch-does-not-apply, temp-file, apply-failed, approval-failed, check-failed,
# check-timeout, mutations-unusable, replay-failed) and its message, and each LANDED, is appended to the
# local event log, .git/harness-kit/events.tsv (events.sh has the format). Usage errors
# (exit 2) are not recorded. The check's result in step 4 (its output, stdout and stderr
# together, is shown and saved) goes to events.sh's harness_check_event, which appends a
# CHECKED line when it differs from the branch's last recorded result.
#
# WHICH REPLAYS (step 5). The files the patch changes (git apply --numstat, before it is
# applied, plus the old name of each renamed file) are compared with .harness/check-files,
# which maps a check to its files: one "name<TAB>path" per line, # comments and blank lines
# skipped, a name on as many lines as it has files, a path ending in "/" meaning everything
# under that folder. An entry of .harness/mutations.tsv is replayed when the patch changes
# its own file (its second field: the code the fault goes into, where the text to find may
# have changed), or a path check-files lists for its check (the name in its last field:
# the check that must catch it, which the patch may have weakened). A check with no
# check-files line starts a replay only through its entries' own files; land.sh names it
# in a note. An entry the patch adds to .harness/mutations.tsv, or changes (any field, id
# kept), is replayed too: a new or edited entry is proved before it lands. Replays run the
# check once per entry plus once without a fault, in parallel up to the CPU count, locally,
# never in CI (replay-faults.sh).
#
# CLEANUP. Its temporary files are removed on any exit, a signal included (limit-lib.sh's
# hk_temp and hk_on_exit); after a forced kill, the time-limit helper's next start sweeps them.
#
# Exit status: 0 landed and checked; 1 stopped (the message says whether the patch is
# applied); 2 usage.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=events.sh
. "$HERE/events.sh"
# shellcheck source=limit-lib.sh
. "$HERE/limit-lib.sh"
say() { echo "harness-kit land.sh: $*" >&2; }
# stopped REASON MESSAGE: record the stop in the event log, then print it.
stopped() {
  harness_event land.sh "" STOPPED "$1" "$2"
  say "STOPPED: $2"
}

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
  stopped no-check-command "no .harness/check-command (or its first line is empty), so there is nothing to check the patch with. Nothing was changed."
  say "Next: put the project's check on the first line of .harness/check-command, with --skip-reviewed, then run land.sh again."
  exit 1
fi
if ! grep -qE '(^|[[:space:]])--skip-reviewed([[:space:]]|$)' <<<"$check"; then
  stopped no-skip-reviewed ".harness/check-command does not pass --skip-reviewed, so it would run the review check, which belongs to ship.sh (nothing is committed yet). Nothing was changed."
  say "Next: add the flag where the project's check reads it, and make the check skip check-reviewed.mjs when given it. For a single command, the first line becomes:"
  say "    $(sed -E 's/[[:space:]]+$//' <<<"$check") --skip-reviewed"
  say "Then run land.sh again. CI still runs the whole check, without the flag."
  exit 1
fi

# 1-2. The patch.
if ! git apply --check "$patch"; then
  stopped patch-does-not-apply "the patch does not apply cleanly (git apply --check failed, above). Nothing was changed."
  say "Next: update the branch or regenerate the patch, then run land.sh again."
  exit 1
fi
# The paths the patch changes, for step 5: new names from --numstat, old names of renames
# from the patch's own "rename from" lines.
hk_on_exit
hk_temp work -d harness-kit-land || { stopped temp-file "cannot make a temporary folder. Nothing was changed."; exit 1; }
changed="$work/changed"
before="$work/mutations-before"
check_out="$work/check-output"
{ git apply --numstat -z "$patch" | tr '\0' '\n' | cut -f3-; sed -n 's/^rename from //p' "$patch"; } >"$changed"
# .harness/mutations.tsv before the patch, so step 5 can tell which entries it adds or changes.
: >"$before"
[ ! -f "$H/mutations.tsv" ] || cp "$H/mutations.tsv" "$before" || { stopped temp-file "cannot copy .harness/mutations.tsv. Nothing was changed."; exit 1; }
if ! git apply "$patch"; then
  stopped apply-failed "git apply failed after --check passed. Look at 'git status' before doing anything else."
  exit 1
fi
say "applied $patch"

# 3. Approval, if the project has one.
approve="$(first_line "$H/approve-command")"
if [ -n "$approve" ]; then
  say "running the approval command: $approve"
  # no-limit: the approval command waits for the person, who answers in this terminal
  /bin/sh -c "$approve"
  status=$?
  if [ "$status" -ne 0 ]; then
    stopped approval-failed "the approval command failed or was declined (exit $status). The patch IS applied and nothing was committed. $UNDO"
    exit 1
  fi
fi

# 4. The check, with --skip-reviewed (step 0).
say "running the check: $check"
{ hk_limited --merge check land.sh /bin/sh -c "$check" </dev/null 2>&1; echo $? >"$check_out.status"; } | tee "$check_out"
status="$(cat "$check_out.status")"
if [ "$status" -eq 124 ]; then
  limit="$(hk_limit check)"
  harness_check_event land.sh "" "timeout ${limit}s" <"$check_out"
  stopped check-timeout "the check did not finish within its limit of $limit seconds (TIMEOUT, above): $check. It was stopped. The patch IS applied and nothing was committed."
  say "Next: find what hangs or runs slowly and fix it, then run the check again, or: git apply -R '$patch'"
  exit 1
fi
harness_check_event land.sh "" "$status" <"$check_out"
if [ "$status" -ne 0 ]; then
  stopped check-failed "the check failed (exit $status): $check. The patch IS applied and nothing was committed."
  say "Next: fix what the check reports and run it again, or: git apply -R '$patch'"
  exit 1
fi

# 5. Fault replays for the checks the patch touched.
if [ ! -f "$H/mutations.tsv" ]; then
  say "no replays needed: there is no .harness/mutations.tsv"
else
  ids="$(node "$HERE/replay-faults.mjs" select "$H/mutations.tsv" "$H/check-files" "$changed" "$before")" || {
    stopped mutations-unusable ".harness/mutations.tsv is unusable (above), so land.sh cannot tell which faults to replay. The patch IS applied and nothing was committed."
    say "Next: fix .harness/mutations.tsv, then run replay-faults.sh, or: git apply -R '$patch'"
    exit 1
  }
  if [ -z "$ids" ]; then
    say "no replays needed: the patch changes no entry's file in .harness/mutations.tsv, no file that .harness/check-files lists for their checks, and no entry"
  else
    say "the patch changes a replayed fault's file, its check's files or its entry, so replaying: $(tr '\n' ' ' <<<"$ids")"
    # shellcheck disable=SC2086 # the ids are words: letters, digits, ".", "_" and "-"
    bash "$HERE/replay-faults.sh" $ids </dev/null
    status=$?
    if [ "$status" -ne 0 ]; then
      stopped replay-failed "a fault replay did not pass (replay-faults.sh exit $status, above): a check no longer catches a fault it caught before, or the replay could not run (its text to find may have changed). The patch IS applied and nothing was committed."
      say "Next: make the check catch the fault again (SURVIVED) or fix the entry (ERROR), then run replay-faults.sh with those ids, or: git apply -R '$patch'"
      exit 1
    fi
  fi
fi

harness_event land.sh "" LANDED - "$patch"
say "LANDED: the patch applied, the check passed and any replays needed were KILLED. Nothing was committed or pushed."
say "Next: read 'git diff', commit it on this branch, then run ship.sh to review, push, wait for CI and merge."
exit 0
