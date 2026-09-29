#!/usr/bin/env bash
# Replay known faults: put each one back, in a throwaway copy of the project, and prove
# the check that should catch it still fails.
#
#   replay-faults.sh [ID...]     run from anywhere inside the project's git repository;
#                                every entry of .harness/mutations.tsv, or only those IDs
#   replay-faults.sh --part PART --out DIR [--baseline-from BDIR] [ID...]
#                                one part of a replay, for parts run apart (harness-kit's own
#                                CI runs its replay as parts): PART is "baseline" (the check
#                                without any fault, only) or "I/N" (shard I of N: the entries
#                                at positions I, I+N, I+2N... of those asked for). Its results
#                                go to the folder DIR, and no verdict is printed. A shard given
#                                the baseline part's results folder BDIR takes its run limit
#                                from that baseline's measured seconds (THE TIME LIMITS).
#   replay-faults.sh --judge DIR...
#                                the verdicts on the parts' results, in the folders DIR (or
#                                one folder they were all copied into): exactly one baseline
#                                part, and parts from this same working tree. It prints what
#                                a whole run prints and exits as it does.
# DIR must be outside the project's working tree, or in a folder git ignores.
#
# LOCAL ONLY. It runs the project's whole check once per entry (plus once without any
# fault), or one check per entry with .harness/check-only (below), so it is for the
# person's terminal and for land.sh. Do not add it to a consumer
# project's CI: a private repository pays for its Actions minutes.
#
# IN PARALLEL. The runs (the baseline and each entry's) go side by side, each in its own
# worktree and with its own time-limit registry (HARNESS_KIT_REGISTRY_DIR, time-limit.mjs),
# with at most as many at once as the machine has CPUs. HARNESS_KIT_REPLAY_JOBS
# (a whole number of 1 or more) lowers that, and never raises it above the CPU count;
# HARNESS_KIT_REPLAY_JOBS=1 runs them one at a time. The verdicts, the totals, the exit
# status and the event-log line do not depend on the number of jobs: the verdicts are
# printed once every run has finished, in file order. replay-faults.mjs has the details.
#
# THE ENTRIES, in .harness/mutations.tsv: one per line, tab-separated, # comments and
# blank lines skipped. No field can hold a tab or a line break.
#   id           letters, digits, ".", "_" or "-"; unique
#   file         the file to change, relative to the project root
#   find         text that must be in the file EXACTLY ONCE, as written (no escapes), and
#                hold no version (v?digits.digits.digits) and no date (YYYY-MM-DD): an
#                entry whose text does is an ERROR, "fragile entry", and is not replayed,
#                as a release or a new date would change the text and break the replay
#   replacement  the text put in its place (may be empty: the text is deleted)
#   check        the name of the check that must FAIL with the fault in place, as the check
#                command prints it after PASS or FAIL
#
# THE TIME LIMITS. Every run has a hard time limit, and so has the whole session; a run
# that passes its limit is stopped and its verdict is TIMEOUT. A fault's run: 3 times the
# baseline's measured seconds, never under 120 seconds. The baseline: 3 times the last
# baseline recorded in the event log (below), or 20 minutes when none is recorded; a
# baseline that passes it stops the session (exit 2). The session: the baseline's limit plus
# the rounds (the faults' runs divided by the job count, rounded up) times the run limit.
# These are harness settings, each overridden by an environment variable:
# HARNESS_KIT_REPLAY_LIMIT_MULTIPLE (3), HARNESS_KIT_REPLAY_LIMIT_FLOOR_SECONDS (120),
# HARNESS_KIT_REPLAY_BASELINE_FALLBACK_SECONDS (1200) and HARNESS_KIT_REPLAY_SESSION_SECONDS
# (unset; when set, the session's limit in seconds). replay-faults.mjs has the details.
#
# THE CHECK is the first line of .harness/check-command, as it is, run with /bin/sh in the
# copy's root. It must carry --skip-reviewed as a word, as land.sh requires (the review
# check reads commits, and a replay is never committed); replay-faults.sh never adds it,
# and without it stops before running anything. A check's result is read from its output
# lines (stdout and stderr together): "PASS <check>" or "FAIL <check>", where the name
# ends the line or is followed by whitespace, ":" or "(" (so "FAIL  lint  (exit 1)" is a
# FAIL of lint, and "FAIL lint-extra" is not).
#
# ONE CHECK PER ENTRY (optional). When the project has a file .harness/check-only (its
# content is not read), each entry's run is the check command with --only and the entry's
# check name added at the end, as one word: `<check command> --only '<check>'`, so only
# the check that must catch the fault runs. The baseline still runs the whole command, as
# it must show a PASS line for every entry's check. The project's check (the last command
# on the line, for a compound one) must then take --only NAME and run just that check,
# printing its PASS or FAIL line as the whole run does. The verdicts are read the same way.
# Without the file, each entry runs the whole command, as the baseline does.
#
# HOW, once per run:
#   1. The copy's content is the working tree AS IT IS: committed or not, untracked files
#      included, ignored files left out. It is a commit made from a temporary index (the
#      project's index, branch and files are not touched), so the replays judge what the
#      person has now, such as a patch land.sh has just applied. Its message starts
#      "harness-kit replay-faults:", and every check run below gets HARNESS_KIT_REPLAY=1,
#      so check-commits.mjs exempts that commit (and only in a replay).
#   2. The runs, side by side, each in a fresh worktree of that commit (detached, git
#      hooks off, with a symlink to each of the main checkout's node_modules folders, as
#      eval-reviewer.sh does; other ignored files, such as build output, are not there):
#      - the baseline: the check with no fault;
#      - each entry that is not fragile (above): the replacement is made (the text missing
#        or found more than once is an ERROR), then the check runs (only the entry's
#        check, with .harness/check-only).
#      Each worktree is removed when its run ends, and every run is stopped and every
#      worktree removed on interruption (Ctrl-C, kill, a hangup or a closed output pipe).
#      After a forced kill (kill -9), what is left is swept by the time-limit helper
#      (time-limit.mjs) when a replay, or any other use of the helper, next starts.
#   3. The verdicts, per entry, in file order: ERROR for a fragile entry; ERROR when the
#      entry's check FAILS in the baseline, or has no PASS line there (a wrong name), as a
#      failure with the fault would prove nothing; ERROR when the fault could not be put in;
#      TIMEOUT when its run passed its time limit, or the session's ran out; KILLED when the
#      run's output has a FAIL line for the entry's check and the check command exited
#      non-zero; SURVIVED otherwise (the check did not catch it).
# Each result is one line on stdout: KILLED, SURVIVED, TIMEOUT or ERROR, the id, and what
# happened. Then a totals line: "replay-faults: N replayed: K KILLED, S SURVIVED, T TIMEOUT,
# E ERROR". Each
# run's output is kept in a folder under the OS temp folder, printed at the end.
#
# THE EVENT LOG. Each run that reaches its totals line (a whole run, or --judge) appends
# one REPLAYED line, with the KILLED, SURVIVED, TIMEOUT and ERROR counts, the baseline's
# seconds ("killed=K,survived=S,timeout=T,error=E,baseline=Bs") and "all" or the ids asked
# for, to the local event log, .git/harness-kit/events.tsv (events.sh has the format). A
# refused or interrupted run, and a --part run, append nothing.
#
# THE TIME (events.sh's harness_timed_event). Next to its REPLAYED line, a run that writes
# one also writes a TIMED line for "replay": the seconds from its start (a whole run's, or a
# --judge run's own) against the replay budget (180 seconds by default; time-limit.mjs's
# BUDGETS). A time over the budget is marked over, with one warning line on stderr; it
# changes no verdict and no exit status.
#
# Exit status: 0 every entry KILLED (--part: every run ended); 1 any SURVIVED, TIMEOUT or
# ERROR; 2 nothing was replayed or judged (usage, no or unusable mutations.tsv, an unknown
# ID, no usable check command, results that are not one whole replay of this working tree,
# a baseline that passed its time limit); 130 or 143 interrupted.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=events.sh
. "$HERE/events.sh"
# shellcheck source=limit-lib.sh
. "$HERE/limit-lib.sh"
NAME="replay-faults.sh"
STARTED="$(harness_clock)"
USAGE="usage: $NAME [ID...] | --part baseline|I/N --out DIR [--baseline-from BDIR] [ID...] | --judge DIR..."
say() { echo "harness-kit $NAME: $*" >&2; }
refuse() { say "$*. Nothing was replayed."; exit 2; }

mode=whole part="" out="" baseline_from=""
case "${1:-}" in
  -h | --help)
    sed -n '2,/^set -u$/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'
    exit 0
    ;;
  --part)
    [ "$#" -ge 4 ] && [ "$3" = --out ] && [ -n "$4" ] || refuse "$USAGE"
    part="$2" out="$4"
    shift 4
    mode=part
    if [ "${1:-}" = --baseline-from ]; then
      [ "$#" -ge 2 ] && [ -n "$2" ] && [ "$part" != baseline ] || refuse "--baseline-from BDIR is for a shard (--part I/N) ($USAGE)"
      [ -d "$2" ] || refuse "$2 is not a folder"
      baseline_from="$(cd "$2" && pwd)"
      shift 2
    fi
    if [ "$part" != baseline ]; then
      [[ "$part" =~ ^([1-9][0-9]*)/([1-9][0-9]*)$ ]] && [ "${BASH_REMATCH[1]}" -le "${BASH_REMATCH[2]}" ] ||
        refuse "the part must be baseline or I/N, shard I of N with 1 <= I <= N, not \"$part\""
    fi
    ;;
  --judge)
    shift
    [ "$#" -ge 1 ] || refuse "$USAGE"
    mode=judge
    ;;
esac
if [ "$mode" != judge ]; then
  for arg in "$@"; do
    case "$arg" in -*) refuse "unknown option $arg ($USAGE)" ;; esac
  done
fi

PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse "not inside a git repository"
cd "$PROJECT" || exit 2
MUTATIONS="$PROJECT/.harness/mutations.tsv"
[ -f "$MUTATIONS" ] || refuse "there is no .harness/mutations.tsv"
if [ "$mode" = judge ]; then
  node "$HERE/replay-faults.mjs" list "$MUTATIONS" >/dev/null || refuse "fix .harness/mutations.tsv (above)"
else
  node "$HERE/replay-faults.mjs" list "$MUTATIONS" "$@" >/dev/null || refuse "fix .harness/mutations.tsv (above)"
fi
git rev-parse -q --verify HEAD >/dev/null || refuse "the repository has no commits yet"

# outside_tree DIR: true when DIR is outside the working tree, or in a folder git ignores,
# so that results kept there do not change the working tree a replay copies.
outside_tree() {
  local abs
  abs="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)/$(basename "$1")" || return 1
  case "$abs/" in
    "$(cd "$PROJECT" && pwd -P)/"*) git -C "$PROJECT" check-ignore -q "$abs" ;;
    *) return 0 ;;
  esac
}

# working_tree INDEX: the tree of the working tree as it is (committed or not, untracked
# files included, ignored files left out), from a temporary index.
working_tree() {
  GIT_INDEX_FILE="$1" git read-tree HEAD && GIT_INDEX_FILE="$1" git add -A . && GIT_INDEX_FILE="$1" git write-tree
}

# judge DIR...: the verdicts, the totals and the event line; exits as a whole run does.
judge() {
  local scratch tree status
  hk_temp scratch -d harness-kit-replay-judge || refuse "cannot make a temporary folder"
  tree="$(working_tree "$scratch/index")" || { rm -rf "$scratch"; refuse "could not read the working tree (above)"; }
  node "$HERE/replay-faults.mjs" judge "$MUTATIONS" "$tree" "$scratch/counts" "$@"
  status=$?
  if [ "$status" -ne 2 ]; then
    harness_event "$NAME" "" REPLAYED "$(sed -n 1p "$scratch/counts")" "$(sed -n 2p "$scratch/counts")"
    harness_timed_event "$NAME" replay "$(harness_seconds_since "$STARTED")" "$(node "$HK_LIMIT_JS" budget replay)"
  fi
  rm -rf "$scratch"
  return "$status"
}

if [ "$mode" = judge ]; then
  for dir in "$@"; do
    outside_tree "$dir" || refuse "$dir is inside the working tree and not ignored, so it is part of what was replayed; keep results outside the project"
  done
  judge "$@"
  exit $?
fi

check="$( { [ -f .harness/check-command ] && head -n 1 .harness/check-command; } | tr -d '\r')"
[ -n "$check" ] || refuse "there is no .harness/check-command (or its first line is empty), so there is no check to replay against"
grep -qE '(^|[[:space:]])--skip-reviewed([[:space:]]|$)' <<<"$check" ||
  refuse "the first line of .harness/check-command does not pass --skip-reviewed, so it would run the review check, which a replay cannot pass. Add the flag where the project's check reads it, as land.sh asks"

if [ "$mode" = part ]; then
  outside_tree "$out" || refuse "$out is inside the working tree and not ignored, so it would become part of what is replayed; keep results outside the project"
  RESULTS="$out"
  mkdir -p "$RESULTS" || refuse "cannot make $RESULTS"
else
  part=all
  RESULTS="$(mktemp -d "${TMPDIR:-/tmp}/harness-kit-replay.XXXXXX")" || refuse "cannot make a temporary folder"
fi
NODE_MODULES="$(find . \( -name .git -o -name node_modules \) -prune -name node_modules -type d -print | sed 's|^\./||')"

# 1. The working tree as a commit, from a temporary index.
hk_temp index harness-kit-replay-index || refuse "cannot make a temporary file"
rm -f "$index"
snapshot="$(
  tree="$(working_tree "$index")" &&
    GIT_AUTHOR_NAME=harness-kit GIT_AUTHOR_EMAIL=harness-kit@localhost \
    GIT_COMMITTER_NAME=harness-kit GIT_COMMITTER_EMAIL=harness-kit@localhost \
    git commit-tree "$tree" -p HEAD -m "harness-kit replay-faults: the working tree"
)" || { rm -f "$index"; refuse "could not copy the working tree into a commit (above)"; }
rm -f "$index"

# 2. The runs. replay-faults.mjs runs in the background so that a signal reaches this
# script at once (an interrupt, a stop signal or a hangup; hk_on_exit's traps); it is passed
# on, and replay-faults.mjs stops every check and removes every worktree before it exits.
RUNNER=""
stop_runner() {
  if [ -n "$RUNNER" ]; then
    kill -TERM "$RUNNER" 2>/dev/null
    wait "$RUNNER"
  fi
  RUNNER=""
}
hk_on_exit stop_runner
HARNESS_KIT_REPLAY_NODE_MODULES="$NODE_MODULES" HARNESS_KIT_REPLAY_BASELINE_FROM="$baseline_from" \
  node "$HERE/replay-faults.mjs" run "$MUTATIONS" "$RESULTS" "$PROJECT" "$snapshot" "$part" "$check" "$@" </dev/null &
RUNNER=$!
wait "$RUNNER"
status=$?
RUNNER=""
[ "$status" -eq 0 ] || refuse "the replay could not run (above; exit $status)"

if [ "$mode" = part ]; then
  say "this part's results are in $RESULTS; judge them with the other parts' with: $NAME --judge <folders>"
  exit 0
fi

# 3. The verdicts.
judge "$RESULTS"
status=$?
say "each run's output is in $RESULTS (baseline.log and <id>.log)"
exit "$status"
