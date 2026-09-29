#!/usr/bin/env bash
# Review the current branch with the read-only harness-kit reviewer, and record the verdict.
#
#   review.sh            run from anywhere inside the project's git repository
#
# For people, in their own terminal: it spends real money on one headless Claude run.
# Configuration, in the project's .harness/ folder (first line of each unless noted):
#   review-base            the base branch (default main); origin/<base> is used if there
#                          is no local branch of that name
#   review-checklist.md    REQUIRED. One item per line, starting with an ID that ends in a
#                          digit and a colon: "- R1: every new function has a test"
#   check-command          the project's check; its real output goes to the reviewer. When
#                          ship.sh has just run it, ship.sh passes that run's saved output
#                          (HARNESS_KIT_CHECK_SAVED, a folder) and review.sh reuses it
#                          instead of running the check again, if it is for the same
#                          command, HEAD and working tree (review-lib.sh's
#                          review_saved_check); the input's CHECK COMMAND section then
#                          says "reused:"
#   review-reads           optional; one project-relative path per line (# comments and
#                          blank lines skipped), such as a spec, copied in whole
#   brief-optional         optional, and honoured only when committed and listed in
#                          protected-paths (brief-lib.sh's brief_optional); the BRIEF
#                          section says so when the branch has no brief
# Limits, from the environment: REVIEW_MAX_TURNS (default 40), REVIEW_MAX_BUDGET_USD
# (default 3.00) and REVIEW_MAX_INPUT_BYTES (default 250000, the most the reviewer's input
# may hold; review-lib.sh's review_build_input says where the default comes from). And a
# time limit on the reviewer run, REVIEW_MAX_SECONDS (default 900; time-limit.mjs): past
# it, the run is stopped with its whole process group, nothing is appended, and review.sh
# exits 5. The check, when it runs here, has the check limit (540 seconds).
#
# WHAT IS REVIEWED is the committed branch: the diff from the merge-base with the base to
# HEAD, excluding .harness/reviews.tsv. Uncommitted changes are shown to the reviewer as
# `git status` but are not part of the diff or its hash; commit first. In the reviewer's
# input a deleted file is one line, "deleted: <path> (<N> lines)", and a renamed file is
# "renamed: <old> -> <new>" plus any change to its content; added and modified files are
# shown in full.
#
# THE BRIEF. The input's BRIEF section, after the CHECKLIST, holds the branch's brief
# (.reports/<branch>.brief.md, written by the plan skill) and whether its approval matches
# it (brief-lib.sh's brief_review_section): "approval: MATCHES" when
# .reports/<branch>.brief.approved holds the brief's sha256 (approve-brief.sh writes it),
# "approval: DOES NOT MATCH" when the brief changed after it was approved, "approval: NONE"
# when it was never approved, or one "none:" line when there is no brief. The reviewer
# judges the diff's scope against an approved brief. review.sh itself never stops for the
# brief; ship.sh does, before starting the review.
#
# THE RECORD. On a completed review it prints the full review, then appends ONE line to
# .harness/reviews.tsv, tab-separated:
#   date  branch  base-sha  head-sha  diff-hash  verdict  items  cost-usd  duration-s
# base-sha is the merge-base. diff-hash comes from check-reviewed.mjs --hash, the same
# function CI runs, so the two cannot disagree. Commit the line (ship.sh, which runs
# review.sh, commits it itself, whatever the verdict); CI's check-reviewed.mjs passes only
# if the latest line for the branch's current diff hash says PASS.
#
# IT FAILS CLOSED. No checklist, no item IDs in it, a missing review-reads file, an input
# over REVIEW_MAX_INPUT_BYTES (the message names the largest parts; claude is not started),
# a failed or limited-out run, output that is not the expected JSON, a missing or malformed VERDICT
# line, a VERDICT that does not list exactly the checklist's IDs, a PASS with an F, or HEAD
# moving during the run: each exits 1 and appends nothing.
#
# Exit status: 0 PASS, 3 FIX-FIRST, 4 STOP (each appended); 1 nothing appended; 5 the
# reviewer ran longer than its time limit and was stopped (nothing appended); 0 also when
# the branch has no diff against its base (nothing to review, nothing appended). Its
# temporary folder is removed on any exit, a signal included (hk_temp, hk_on_exit).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=review-lib.sh
. "$HERE/review-lib.sh"
# shellcheck source=brief-lib.sh
. "$HERE/brief-lib.sh"

die() {
  echo "harness-kit review.sh: $*; nothing was appended to .harness/reviews.tsv" >&2
  exit 1
}

PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
H="$PROJECT/.harness"
CHECKLIST="$H/review-checklist.md"
cd "$PROJECT" || die "cannot enter $PROJECT"

review_load_checklist "$CHECKLIST" || die "$REVIEW_ERROR"
review_load_reads "$H/review-reads" "$PROJECT"
review_check_reads || die "$REVIEW_ERROR"

state="$(node "$HERE/check-reviewed.mjs" --hash)" || die "could not work out the branch's diff: $state"
IFS=$'\t' read -r base_ref merge_base diff_hash <<<"$state"
if [ "$diff_hash" = "none" ]; then
  echo "harness-kit review.sh: no diff against $base_ref (merge-base ${merge_base:0:12}); nothing to review" >&2
  exit 0
fi
head="$(git rev-parse HEAD)"
branch="$(git symbolic-ref --short -q HEAD || echo "(detached)")"
if [ -n "$(git status --porcelain -- . ':(exclude).harness/reviews.tsv')" ]; then
  echo "harness-kit review.sh: the working tree has uncommitted changes; they are NOT part of the reviewed diff" >&2
fi

hk_on_exit
hk_temp work -d harness-kit-review || die "cannot make a temporary folder"

if review_saved_check "$H" "${HARNESS_KIT_CHECK_SAVED:-}" >"$work/check-section.txt"; then
  echo "harness-kit review.sh: reusing the check output ship.sh saved at this head; not running the check again" >&2
else
  review_check_section "$H" "$work" >"$work/check-section.txt"
fi
brief_review_section "$PROJECT" "$branch" >"$work/brief-section.txt"
REVIEW_BRIEF_SECTION="$work/brief-section.txt"
review_build_input "$work/input.md" "$PROJECT" "$branch" "$base_ref" "$merge_base" "$head" "$CHECKLIST" \
  "$work/check-section.txt" || die "$REVIEW_ERROR"

echo "harness-kit review.sh: reviewing $branch against $base_ref (limits: $REVIEW_TURNS turns, \$$REVIEW_BUDGET, $(hk_limit review) seconds)..." >&2
review_run "$PROJECT" "$work/input.md" "$work/out.json"
run_status=$?
if [ "$run_status" -eq 124 ]; then
  echo "harness-kit review.sh: $REVIEW_ERROR; nothing was appended to .harness/reviews.tsv" >&2
  exit 5
fi
review_parse "$work" "$run_status" "review.sh" || die "$REVIEW_ERROR"

cat "$work/review.txt"
[ "$(git rev-parse HEAD)" = "$head" ] || die "HEAD moved during the review, so the verdict may not match the diff"

IFS=$'\t' read -r verdict items cost duration <"$work/record.tsv"
reviews="$H/reviews.tsv"
if [ -s "$reviews" ] && [ -n "$(tail -c 1 "$reviews")" ]; then echo >>"$reviews"; fi
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$branch" "$merge_base" "$head" "$diff_hash" \
  "$verdict" "$items" "$cost" "$duration" >>"$reviews" || die "could not write $reviews"

echo
echo "harness-kit review.sh: $verdict ($items), \$$cost, ${duration}s; recorded in .harness/reviews.tsv. Commit it." >&2
case "$verdict" in
  PASS) exit 0 ;;
  FIX-FIRST) exit 3 ;;
  *) exit 4 ;;
esac
