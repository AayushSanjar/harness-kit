#!/usr/bin/env bash
# Measure the harness-kit reviewer on historical cases: does it catch known defects, and
# does it leave clean changes alone?
#
#   eval-reviewer.sh [--repeat N]        run from anywhere inside the project's git repository
#   eval-reviewer.sh --regrade FOLDER    grade a finished evaluation's saved runs again
#
# For people, in their own terminal: every run spends real money on one headless Claude run,
# within review.sh's limits (REVIEW_MAX_TURNS, default 40; REVIEW_MAX_BUDGET_USD, default
# 3.00, per run). --regrade makes no Claude call and costs nothing.
#
# THE CASES, in .harness/reviewer-eval/cases.tsv: one per line, tab-separated, # comments and
# blank lines skipped; "-" stands for an empty field. The last three fields are optional
# (a file of 6 or 7 fields is still valid); to give a later one, write "-" for those before.
#   id  kind  base  head  file-regex  keyword-regex  [spec-replacement]  [na_items]  [expected_item]
#   kind              defect (head holds a known defect) or control (head is clean)
#   base, head        commits; the reviewer judges the diff from their merge-base to head
#   file-regex        defect only: the file the defect is in, such as src/auth\.js
#   keyword-regex     defect only: words that name the defect, such as expir|stale
#   spec-replacement  optional; a file (project-relative or absolute) used in place of the
#                     FIRST path in .harness/review-reads, so a case can hide traces of its
#                     later fix. It is also copied over that file in the worktree.
#   na_items          optional; checklist item IDs, comma-separated, such as C4,C7, that
#                     cannot be judged in this case. The input says "EVAL MODE: mark C4,C7
#                     NA", and a FAIL on those items is never a false alarm.
#   expected_item     optional, defect only; one checklist item ID, the item the defect
#                     breaks. That item FAILED with text matching the keyword regex is a catch.
# A review-reads file missing at a case's head (added later than that commit) is not an
# error here, unlike in review.sh: its READ section says "<path>: not present at this commit".
# Both regexes are JavaScript regular expressions, matched without regard to case.
#
# EACH RUN checks out head in a temporary git worktree (detached, with git hooks off) and
# builds the reviewer's input exactly as review.sh does, with the project's CURRENT checklist
# and review-reads list (the reviewer setup being measured) over the files at head, except
# that the check command is not run: its section says "EVAL MODE: historical case, no check
# output; mark the checks item NA" (and the na_items line, if any). Once the input is built
# (so its GIT STATUS shows head as it was), the worktree gets:
#   - the CURRENT checklist, copied to .harness/review-checklist.md, the path the input
#     names, and the spec replacement copied over the first review-reads file: the reviewer
#     never needs to Read outside the worktree;
#   - a symlink to every node_modules folder of the main checkout, at the same relative
#     path, where that path's parent folder exists in the worktree. VERSION MISMATCH RISK:
#     the links hold the packages installed for the main checkout TODAY, not those head's
#     package.json and lockfile asked for. If a dependency changed since head, the reviewer
#     reads the wrong version's code and types, and may judge head against an API it did
#     not have. Nothing checks this; keep it in mind for old cases. The links are removed
#     with the worktree; the folders they point at are not touched.
# The reviewer runs with HARNESS_KIT_EVAL=1 in its environment, which a hook process
# inherits, so harness-kit's Stop hook lets it finish without running the checks. The
# worktree is removed afterwards, also on failure or interruption. Nothing is written to
# .harness/reviews.tsv; results go to a folder under the OS temp folder, printed at the
# end: results.tsv, and runs/<id>.<run>/ with each run's input.md, its full stream-json
# transcript (transcript.jsonl), the result event (out.json) and the review (review.txt).
#
# GRADING, per run (rule A: both regexes must match inside ONE text, never across two):
#   defect   CAUGHT if the verdict is not PASS and either the file regex and the keyword
#            regex both match inside ONE FAILED item's text or ONE finding's text, or the
#            expected_item FAILED and its text matches the keyword regex; otherwise MISSED.
#            An item's text is its line and the lines below it, without the leading
#            "C1 — FAIL —": the status word is never taken for the keyword.
#   control  CLEAN if the verdict is PASS, or if every FAILED item is in na_items and there
#            is no finding; otherwise FALSE ALARM
#   ERROR    the run did not complete (limits, a failed run, a malformed VERDICT line). It
#            counts against the reviewer: as not caught for a defect, as a false alarm for a
#            control.
# The review graded is the final message of the run, the result event's text.
# Then the totals: catch rate, false-alarm rate, total cost and total time (the reviewer's
# own duration, summed). With --repeat N, each case runs N times, and also:
#   pass@N  the share of cases the reviewer got right in at least one of N runs.
#   pass^N  the share of cases the reviewer got right in all N runs.
#
# --regrade FOLDER grades the saved reviews in a results folder again, with this grader and
# the CURRENT cases.tsv (kind, regexes, na_items, expected_item; commits are not checked),
# and prints the same table. It writes FOLDER/regraded.tsv and leaves results.tsv alone. A
# run that was an ERROR stays one; a run whose case is gone from cases.tsv is left out.
#
# The reviewer can Read outside its worktree, so it is not strictly blind to cases.tsv.
#
# Exit status: 0 when every run was graded; 1 when a run was an ERROR, or the cases or the
# setup were unusable (then nothing was run).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=review-lib.sh
. "$HERE/review-lib.sh"

NAME="eval-reviewer.sh"
EVAL_LINE="EVAL MODE: historical case, no check output; mark the checks item NA"

die() {
  echo "harness-kit $NAME: $*" >&2
  exit 1
}

repeat=1
regrade=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repeat)
      [ "$#" -ge 2 ] || die "--repeat needs a number"
      repeat="$2"
      shift 2
      ;;
    --repeat=*)
      repeat="${1#--repeat=}"
      shift
      ;;
    --regrade)
      [ "$#" -ge 2 ] || die "--regrade needs a results folder"
      regrade="$2"
      shift 2
      ;;
    --regrade=*)
      regrade="${1#--regrade=}"
      shift
      ;;
    -h | --help)
      sed -n '2,/^set -u$/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'
      exit 0
      ;;
    *) die "unknown argument: $1 (usage: $NAME [--repeat N] | --regrade FOLDER)" ;;
  esac
done
case "$repeat" in "" | *[!0-9]* | 0*) die "--repeat takes a whole number of 1 or more, not \"$repeat\"" ;; esac
if [ -n "$regrade" ]; then
  [ -f "$regrade/results.tsv" ] || die "--regrade: $regrade has no results.tsv; give the folder an evaluation printed at its end"
  regrade="$(cd "$regrade" && pwd)"
fi

PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
H="$PROJECT/.harness"
CHECKLIST="$H/review-checklist.md"
CASES="$H/reviewer-eval/cases.tsv"
cd "$PROJECT" || die "cannot enter $PROJECT"

review_load_checklist "$CHECKLIST" || die "$REVIEW_ERROR"
review_load_reads "$H/review-reads" "$PROJECT"
[ -s "$CASES" ] || die "no .harness/reviewer-eval/cases.tsv (or it is empty): there is nothing to evaluate"

# Check every case before running any, so a typo costs nothing. Prints the cases one per
# line, tab-separated, with every empty field as "-" and the replacement as an absolute path.
cases="$(node "$HERE/eval-reviewer.mjs" cases "$CASES" "$PROJECT" "${#REVIEW_READS[@]}" "$REVIEW_ID_LIST")" ||
  die "fix .harness/reviewer-eval/cases.tsv; nothing was run"

if [ -n "$regrade" ]; then
  node "$HERE/eval-reviewer.mjs" regrade "$regrade" <<<"$cases"
  status=$?
  echo "harness-kit $NAME: regraded $regrade with the current grader and cases.tsv, no Claude call; written to its regraded.tsv" >&2
  exit "$status"
fi

while IFS=$'\t' read -r id kind base head _; do
  for rev in "$base" "$head"; do
    git rev-parse --verify --quiet "$rev^{commit}" >/dev/null ||
      die "case $id: \"$rev\" is not a commit in this repository; nothing was run"
  done
done <<<"$cases"

# The main checkout's node_modules folders, project-relative, found once: each run links
# them into its worktree (see the header for the version mismatch risk).
NODE_MODULES="$(find . \( -name .git -o -name node_modules \) -prune -name node_modules -type d -print | sed 's|^\./||')"

RESULTS="$(mktemp -d "${TMPDIR:-/tmp}/harness-kit-eval.XXXXXX")" || die "cannot make a temporary folder"
printf 'id\trun\tkind\tverdict\toutcome\tcost-usd\tduration-s\n' >"$RESULTS/results.tsv"

# The worktree of the run in progress, if any. remove_worktree is safe to call twice.
WORKTREE=""
remove_worktree() {
  [ -n "$WORKTREE" ] || return 0
  git -C "$PROJECT" worktree remove --force "$WORKTREE" >/dev/null 2>&1
  rm -rf "$WORKTREE"
  git -C "$PROJECT" worktree prune
  WORKTREE=""
}
trap remove_worktree EXIT
trap 'remove_worktree; trap - EXIT; exit 130' INT
trap 'remove_worktree; trap - EXIT; exit 143' TERM

# link_node_modules WORKTREE: symlinks each of NODE_MODULES into WORKTREE at the same
# path, when its parent folder exists there and nothing is at the path already.
link_node_modules() {
  local rel
  while IFS= read -r rel; do
    [ -n "$rel" ] && [ -d "$1/$(dirname "$rel")" ] || continue
    if [ -e "$1/$rel" ] || [ -L "$1/$rel" ]; then continue; fi
    ln -s "$PROJECT/$rel" "$1/$rel" || return 1
  done <<<"$NODE_MODULES"
}

# run_case ID RUN KIND BASE HEAD FILE_RE KEYWORD_RE SPEC NA EXPECTED: one run, graded;
# appends one line to results.tsv. Any failure makes the run an ERROR, with the reason on
# stderr.
run_case() {
  local id="$1" n="$2" kind="$3" base="$4" head="$5" file_re="$6" keyword_re="$7" spec="$8" na="$9" expected="${10}"
  local run="$RESULTS/runs/$id.$n" head_sha merge_base branch status verdict=- outcome=ERROR cost=0.0000 duration=0.0 why=""
  local wt_checklist
  mkdir -p "$run"
  head_sha="$(git rev-parse "$head^{commit}")"
  merge_base="$(git merge-base "$base" "$head_sha")" || why="no merge-base between $base and $head"

  if [ -z "$why" ]; then
    WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/harness-kit-eval-wt.XXXXXX")" || why="cannot make a temporary folder"
  fi
  if [ -z "$why" ]; then
    git -C "$PROJECT" -c core.hooksPath=/dev/null worktree add --detach --quiet "$WORKTREE" "$head_sha" >"$run/worktree.log" 2>&1 ||
      why="could not create the worktree: $(cat "$run/worktree.log")"
  fi
  if [ -z "$why" ]; then
    review_load_reads "$H/review-reads" "$WORKTREE"
    [ "$spec" = - ] || REVIEW_READ_SOURCES[0]="$spec"
    printf '%s\n' "$EVAL_LINE" >"$run/check-section.txt"
    [ "$na" = - ] || printf 'EVAL MODE: mark %s NA\n' "$na" >>"$run/check-section.txt"
    branch="$(git -C "$WORKTREE" symbolic-ref --short -q HEAD || echo "(detached)")"
    wt_checklist="$WORKTREE/.harness/review-checklist.md"
    { review_check_reads --missing-ok && review_build_input "$run/input.md" "$WORKTREE" "$branch" "$base" "$merge_base" \
      "$head_sha" "$CHECKLIST" "$run/check-section.txt" "$wt_checklist"; } || why="$REVIEW_ERROR"
  fi
  if [ -z "$why" ]; then
    # The copies and links come after the input is built, so its GIT STATUS shows head as it
    # was: a Read of the spec must not find the text the replacement hides.
    { mkdir -p "$WORKTREE/.harness" && cp "$CHECKLIST" "$wt_checklist"; } || why="could not copy the checklist into the worktree"
  fi
  if [ -z "$why" ]; then
    [ "$spec" = - ] || cp "$spec" "$WORKTREE/${REVIEW_READS[0]}" || why="could not copy the spec replacement"
  fi
  if [ -z "$why" ]; then
    link_node_modules "$WORKTREE" || why="could not link node_modules into the worktree"
  fi
  if [ -z "$why" ]; then
    echo "harness-kit $NAME: $id run $n of $repeat ($kind, head ${head_sha:0:12})..." >&2
    HARNESS_KIT_EVAL=1 review_run "$WORKTREE" "$run/input.md" "$run/transcript.jsonl" --stream
    status=$?
    node "$HERE/eval-reviewer.mjs" result "$run/transcript.jsonl" "$run/out.json"
    if review_parse "$run" "$status" "$NAME"; then
      IFS=$'\t' read -r verdict _ cost duration <"$run/record.tsv"
      outcome="$(node "$HERE/eval-reviewer.mjs" grade "$run/review.txt" "$kind" "$file_re" "$keyword_re" \
        "$verdict" "$(cut -f2 "$run/record.tsv")" "$na" "$expected")" || { outcome=ERROR why="could not grade the review"; }
    else
      why="$REVIEW_ERROR"
      # A run that failed still spent money; count it.
      read -r cost duration < <(node "$HERE/eval-reviewer.mjs" cost "$run/out.json")
    fi
  fi
  remove_worktree
  [ -z "$why" ] || echo "harness-kit $NAME: $id run $n is an ERROR: $why" >&2
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$n" "$kind" "$verdict" "$outcome" "$cost" "$duration" >>"$RESULTS/results.tsv"
}

while IFS=$'\t' read -r id kind base head file_re keyword_re spec na expected; do
  n=1
  while [ "$n" -le "$repeat" ]; do
    run_case "$id" "$n" "$kind" "$base" "$head" "$file_re" "$keyword_re" "$spec" "$na" "$expected" </dev/null
    n=$((n + 1))
  done
done <<<"$cases"

node "$HERE/eval-reviewer.mjs" summary "$RESULTS/results.tsv" "$repeat"

echo "harness-kit $NAME: results in $RESULTS (results.tsv, and runs/<id>.<run>/ with each input, transcript and review); nothing was written to .harness/reviews.tsv" >&2
! grep -q $'\tERROR\t' "$RESULTS/results.tsv"
