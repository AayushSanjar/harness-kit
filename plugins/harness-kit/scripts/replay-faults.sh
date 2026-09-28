#!/usr/bin/env bash
# Replay known faults: put each one back, in a throwaway copy of the project, and prove
# the check that should catch it still fails.
#
#   replay-faults.sh [ID...]     run from anywhere inside the project's git repository;
#                                every entry of .harness/mutations.tsv, or only those IDs
#
# LOCAL ONLY. It runs the project's whole check once per entry (plus once without any
# fault), so it is for the person's terminal and for land.sh. Do not add it to a consumer
# project's CI: a private repository pays for its Actions minutes.
#
# THE ENTRIES, in .harness/mutations.tsv: one per line, tab-separated, # comments and
# blank lines skipped. No field can hold a tab or a line break.
#   id           letters, digits, ".", "_" or "-"; unique
#   file         the file to change, relative to the project root
#   find         text that must be in the file EXACTLY ONCE, as written (no escapes)
#   replacement  the text put in its place (may be empty: the text is deleted)
#   check        the name of the check that must FAIL with the fault in place, as the check
#                command prints it after PASS or FAIL
#
# THE CHECK is the first line of .harness/check-command, as it is, run with /bin/sh in the
# copy's root. It must carry --skip-reviewed as a word, as land.sh requires (the review
# check reads commits, and a replay is never committed); replay-faults.sh never adds it,
# and without it stops before running anything. A check's result is read from its output
# lines (stdout and stderr together): "PASS <check>" or "FAIL <check>", where the name
# ends the line or is followed by whitespace, ":" or "(" (so "FAIL  lint  (exit 1)" is a
# FAIL of lint, and "FAIL lint-extra" is not).
#
# HOW, once per run:
#   1. The copy's content is the working tree AS IT IS: committed or not, untracked files
#      included, ignored files left out. It is a commit made from a temporary index (the
#      project's index, branch and files are not touched), so the replays judge what the
#      person has now, such as a patch land.sh has just applied.
#   2. The baseline: in a fresh worktree of that commit, the check runs with no fault. An
#      entry whose check already FAILS there, or has no PASS line there (a wrong name), is
#      an ERROR: a failure with the fault would prove nothing.
# Then per entry, in a fresh worktree of the same commit (detached, git hooks off, with a
# symlink to each of the main checkout's node_modules folders, as eval-reviewer.sh does;
# other ignored files, such as build output, are not there):
#   3. The replacement is made. The text missing, or found more than once: ERROR.
#   4. The check runs. KILLED when its output has a FAIL line for the entry's check and the
#      check command exited non-zero; SURVIVED otherwise (the check did not catch it).
#   5. The worktree is removed, also on failure or interruption (Ctrl-C, kill).
# Each result is one line on stdout: KILLED, SURVIVED or ERROR, the id, and what happened.
# Then a totals line: "replay-faults: N replayed: K KILLED, S SURVIVED, E ERROR". Each
# run's output is kept in a folder under the OS temp folder, printed at the end.
#
# THE EVENT LOG. Each run that reaches its totals line appends one REPLAYED line, with the
# KILLED, SURVIVED and ERROR counts and "all" or the ids asked for, to the local event log,
# .git/harness-kit/events.tsv (events.sh has the format). A refused or interrupted run
# appends nothing.
#
# Exit status: 0 every entry KILLED; 1 any SURVIVED or ERROR; 2 nothing was replayed (usage,
# no or unusable mutations.tsv, an unknown ID, no usable check command).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=events.sh
. "$HERE/events.sh"
NAME="replay-faults.sh"
say() { echo "harness-kit $NAME: $*" >&2; }
refuse() { say "$*. Nothing was replayed."; exit 2; }

case "${1:-}" in
  -h | --help)
    sed -n '2,/^set -u$/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'
    exit 0
    ;;
  -*) refuse "unknown option $1 (usage: $NAME [ID...])" ;;
esac

PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse "not inside a git repository"
cd "$PROJECT" || exit 2
MUTATIONS="$PROJECT/.harness/mutations.tsv"
[ -f "$MUTATIONS" ] || refuse "there is no .harness/mutations.tsv"
entries="$(node "$HERE/replay-faults.mjs" list "$MUTATIONS" "$@")" || refuse "fix .harness/mutations.tsv (above)"

check="$( { [ -f .harness/check-command ] && head -n 1 .harness/check-command; } | tr -d '\r')"
[ -n "$check" ] || refuse "there is no .harness/check-command (or its first line is empty), so there is no check to replay against"
grep -qE '(^|[[:space:]])--skip-reviewed([[:space:]]|$)' <<<"$check" ||
  refuse "the first line of .harness/check-command does not pass --skip-reviewed, so it would run the review check, which a replay cannot pass. Add the flag where the project's check reads it, as land.sh asks"
git rev-parse -q --verify HEAD >/dev/null || refuse "the repository has no commits yet"

RESULTS="$(mktemp -d "${TMPDIR:-/tmp}/harness-kit-replay.XXXXXX")" || refuse "cannot make a temporary folder"
NODE_MODULES="$(find . \( -name .git -o -name node_modules \) -prune -name node_modules -type d -print | sed 's|^\./||')"

# The worktree in use, if any. remove_worktree is safe to call twice.
WORKTREE=""
remove_worktree() {
  [ -n "$WORKTREE" ] || return 0
  git -C "$PROJECT" worktree remove --force "$WORKTREE" >/dev/null 2>&1
  rm -rf "$WORKTREE"
  git -C "$PROJECT" worktree prune
  WORKTREE=""
}
trap remove_worktree EXIT
trap 'remove_worktree; trap - EXIT; say "interrupted; the worktree was removed"; exit 130' INT
trap 'remove_worktree; trap - EXIT; say "interrupted; the worktree was removed"; exit 143' TERM

# 1. The working tree as a commit, from a temporary index.
index="$RESULTS/index"
snapshot="$(
  export GIT_INDEX_FILE="$index"
  git read-tree HEAD && git add -A . && tree="$(git write-tree)" &&
    GIT_AUTHOR_NAME=harness-kit GIT_AUTHOR_EMAIL=harness-kit@localhost \
    GIT_COMMITTER_NAME=harness-kit GIT_COMMITTER_EMAIL=harness-kit@localhost \
    git commit-tree "$tree" -p HEAD -m "harness-kit replay-faults: the working tree"
)" || refuse "could not copy the working tree into a commit (above)"
rm -f "$index"

# new_worktree: a fresh worktree of the snapshot in WORKTREE, with node_modules linked.
new_worktree() {
  local rel
  WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/harness-kit-replay-wt.XXXXXX")" || return 1
  git -C "$PROJECT" -c core.hooksPath=/dev/null worktree add --detach --quiet "$WORKTREE" "$snapshot" >"$RESULTS/worktree.log" 2>&1 || return 1
  while IFS= read -r rel; do
    [ -n "$rel" ] && [ -d "$WORKTREE/$(dirname "$rel")" ] || continue
    if [ -e "$WORKTREE/$rel" ] || [ -L "$WORKTREE/$rel" ]; then continue; fi
    ln -s "$PROJECT/$rel" "$WORKTREE/$rel" || return 1
  done <<<"$NODE_MODULES"
}

# run_check LOG: the check in WORKTREE; sets STATUS.
run_check() {
  (cd "$WORKTREE" && /bin/sh -c "$check") </dev/null >"$1" 2>&1
  STATUS=$?
}

killed=0 survived=0 errors=0 total=0
report() {
  echo "$1 $2: $3"
  case "$1" in KILLED) killed=$((killed + 1)) ;; SURVIVED) survived=$((survived + 1)) ;; *) errors=$((errors + 1)) ;; esac
  total=$((total + 1))
}

# 2. The baseline.
say "running the check without any fault: $check"
new_worktree || refuse "could not create a worktree: $(cat "$RESULTS/worktree.log" 2>/dev/null)"
run_check "$RESULTS/baseline.log"
BASELINE_STATUS=$STATUS
remove_worktree

count="$(wc -l <<<"$entries" | tr -d ' ')"
n=0
while IFS=$'\t' read -r id file name; do
  n=$((n + 1))
  if ! why="$(node "$HERE/replay-faults.mjs" baseline "$name" "$RESULTS/baseline.log" "$BASELINE_STATUS")"; then
    report ERROR "$id" "$why"
    continue
  fi
  say "replaying $id ($n of $count): $file, which \"$name\" must catch"
  if ! new_worktree; then
    report ERROR "$id" "could not create a worktree: $(cat "$RESULTS/worktree.log")"
    remove_worktree
    continue
  fi
  if ! why="$(node "$HERE/replay-faults.mjs" apply "$MUTATIONS" "$id" "$WORKTREE")"; then
    report ERROR "$id" "$why"
    remove_worktree
    continue
  fi
  run_check "$RESULTS/$id.log"
  remove_worktree
  verdict="$(node "$HERE/replay-faults.mjs" verdict "$name" "$RESULTS/$id.log" "$STATUS")"
  if [ "$verdict" = KILLED ]; then
    report KILLED "$id" "\"$name\" failed with the fault in $file"
  else
    report SURVIVED "$id" "$(cut -f2- <<<"$verdict")"
  fi
done <<<"$entries"

echo "replay-faults: $total replayed: $killed KILLED, $survived SURVIVED, $errors ERROR"
if [ "$#" -eq 0 ]; then asked=all; else asked="ids: $*"; fi
harness_event "$NAME" "" REPLAYED "killed=$killed,survived=$survived,error=$errors" "$asked"
say "each run's output is in $RESULTS (baseline.log and <id>.log)"
[ "$survived" -eq 0 ] && [ "$errors" -eq 0 ]
