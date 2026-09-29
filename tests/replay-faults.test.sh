#!/usr/bin/env bash
# Tests for replay-faults.sh (with replay-faults.mjs) and land.sh's fault replays.
#
# Every case runs in a temporary git repository whose "check" is a small fake: check.sh
# runs checks/greeting.sh (PASS when app.sh prints hello) and checks/other.sh (PASS when
# other.txt says content), one PASS or FAIL line each; with --only NAME it runs only that
# one. The parallel cases use a second fake (new_pool) whose checks can be held until the
# test lets them finish, through named pipes (FIFOs). No case sleeps: the only time limit
# is `read -t 10` on those pipes, which runs out only when the code under test is broken.
# Nothing touches GitHub and no API call is made. Prints one PASS or FAIL line per case
# and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/plugins/harness-kit/scripts"
REPLAY="$SCRIPTS/replay-faults.sh"
LAND="$SCRIPTS/land.sh"
# The real path: git prints resolved paths, and macOS's temp folder is behind a symlink.
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
# replay-faults.sh makes its worktrees and results under TMPDIR; a case can then see
# whether any worktree folder was left behind.
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"
failures=0

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
# A replay of this repository runs this file with its own settings; the cases set their own.
unset HARNESS_KIT_EVAL CLAUDE_PROJECT_DIR HARNESS_KIT_REPLAY HARNESS_KIT_REPLAY_JOBS HARNESS_KIT_REPLAY_CPUS \
  HARNESS_KIT_REPLAY_LIMIT_MULTIPLE HARNESS_KIT_REPLAY_LIMIT_FLOOR_SECONDS HARNESS_KIT_REPLAY_BASELINE_FALLBACK_SECONDS \
  HARNESS_KIT_REPLAY_SESSION_SECONDS HARNESS_KIT_REPLAY_BASELINE_FROM HARNESS_KIT_REPLAY_GRACE_SECONDS
# HARNESS_KIT_REPLAY_OUTER is kept: when a replay of this repository runs this file, its
# replays of the fake projects are replays inside a replay, and run one check at a time.
# The cases that need a pool say how big (HARNESS_KIT_REPLAY_CPUS).

result() {
  local label="$1" ok="$2" detail="$3"
  if [ "$ok" = yes ]; then
    echo "PASS $label"
  else
    echo "FAIL $label"
    sed 's/^/    /' <<<"$detail"
    failures=$((failures + 1))
  fi
}

describe() { printf 'exit %s\nstdout: %s\nstderr: %s' "$STATUS" "$OUT" "$ERR"; }

# new_project NAME MUTATIONS: a repository on main with the fake check and
# .harness/mutations.tsv holding MUTATIONS (printf-style, \t between fields). Prints its path.
new_project() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.harness" "$dir/checks"
  git -C "$dir" init -q -b main
  printf '# the greeting\necho hello\n' >"$dir/app.sh"
  printf 'content\n' >"$dir/other.txt"
  cat >"$dir/checks/greeting.sh" <<'CHECK'
if [ "$(sh app.sh)" = hello ]; then echo "PASS  greeting"; else echo "FAIL  greeting  (exit 1)"; exit 1; fi
CHECK
  cat >"$dir/checks/other.sh" <<'CHECK'
if [ "$(cat other.txt 2>/dev/null)" = content ]; then echo "PASS other"; else echo "FAIL other: other.txt changed"; exit 1; fi
CHECK
  cat >"$dir/check.sh" <<'CHECK'
case " $* " in *" --skip-reviewed "*) ;; *) echo "FAIL check.sh: no --skip-reviewed"; exit 1 ;; esac
[ -z "${REPLAY_ENV_LOG:-}" ] || echo "HARNESS_KIT_REPLAY=${HARNESS_KIT_REPLAY:-unset}" >>"$REPLAY_ENV_LOG"
only=""
while [ $# -gt 0 ]; do [ "$1" != --only ] || { only="$2"; shift; }; shift; done
status=0
[ -n "$only" ] && [ "$only" != greeting ] || sh checks/greeting.sh || status=1
[ -n "$only" ] && [ "$only" != other ] || sh checks/other.sh || status=1
exit $status
CHECK
  printf 'sh check.sh --skip-reviewed\n' >"$dir/.harness/check-command"
  printf "# id\tfile\tfind\treplacement\tcheck\n$2" >"$dir/.harness/mutations.tsv"
  git -C "$dir" add -A && git -C "$dir" commit -q -m "main: initial"
  echo "$dir"
}

# run_in DIR CMD...: sets OUT, ERR, STATUS.
run_in() {
  local dir="$1"
  shift
  OUT="$(cd "$dir" && "$@" 2>"$WORK/stderr")"
  STATUS=$?
  ERR="$(cat "$WORK/stderr")"
}

# clean DIR: no worktree but the main one, and no worktree folder left under TMPDIR.
clean() {
  [ "$(git -C "$1" worktree list --porcelain | grep -c '^worktree ')" -eq 1 ] &&
    [ -z "$(find "$TMPDIR" -maxdepth 1 -name 'harness-kit-replay-wt.*' -print)" ]
}

M_KILLED='m-killed\tapp.sh\techo hello\techo goodbye\tgreeting\n'
M_SURVIVED='m-survived\tapp.sh\t# the greeting\t# a salutation\tgreeting\n'
M_ERROR='m-error\tapp.sh\techo bonjour\techo hi\tgreeting\n'
M_TWICE='m-twice\tapp.sh\te\tE\tgreeting\n'
M_OTHER='m-other\tother.txt\tcontent\tchanged\tother\n'
M_WRONG='m-wrong\tapp.sh\techo hello\techo goodbye\tgreetings\n'
M_ALSO='m-also\tapp.sh\techo hello\techo hi\tgreeting\n'
dir="$(new_project replay "$M_KILLED$M_SURVIVED$M_ERROR$M_TWICE$M_OTHER$M_WRONG$M_ALSO")"

# ---------------------------------------------------------------------------------------
# replay-faults.sh
# ---------------------------------------------------------------------------------------

# 1. KILLED: the check catches the fault; exit 0, and the project itself is untouched.
# Every check run (the baseline and the entry's) has HARNESS_KIT_REPLAY=1, which
# check-commits.mjs needs to exempt the snapshot commit.
REPLAY_ENV_LOG="$WORK/replay-env" run_in "$dir" bash "$REPLAY" m-killed
if [ "$STATUS" -eq 0 ] && grep -q '^KILLED m-killed: "greeting" failed with the fault in app.sh$' <<<"$OUT" &&
  [ "$(cat "$WORK/replay-env" 2>/dev/null)" = "$(printf 'HARNESS_KIT_REPLAY=1\nHARNESS_KIT_REPLAY=1')" ] &&
  grep -qx 'replay-faults: 1 replayed: 1 KILLED, 0 SURVIVED, 0 TIMEOUT, 0 ERROR' <<<"$OUT" &&
  grep -q 'echo hello' "$dir/app.sh" && [ -z "$(git -C "$dir" status --porcelain)" ] && clean "$dir"; then
  result "replay-faults: a fault its check catches is KILLED, exit 0, the project untouched" yes ""
else
  result "replay-faults: a fault its check catches is KILLED, exit 0, the project untouched" no "$(describe)
check environment: $(cat "$WORK/replay-env" 2>/dev/null)"
fi

# 2. SURVIVED: a change the check does not notice; exit 1.
run_in "$dir" bash "$REPLAY" m-survived
if [ "$STATUS" -eq 1 ] && grep -q '^SURVIVED m-survived: "greeting" did not fail with the fault in place' <<<"$OUT" &&
  grep -qx 'replay-faults: 1 replayed: 0 KILLED, 1 SURVIVED, 0 TIMEOUT, 0 ERROR' <<<"$OUT" && clean "$dir"; then
  result "replay-faults: a SURVIVED fault exits non-zero" yes ""
else
  result "replay-faults: a SURVIVED fault exits non-zero" no "$(describe)"
fi

# 3. ERROR: the text to find is missing, or there more than once; exit 1, and the next
# entry still runs.
run_in "$dir" bash "$REPLAY" m-error m-twice m-killed
if [ "$STATUS" -eq 1 ] && grep -q '^ERROR m-error: the text to find is not in app.sh$' <<<"$OUT" &&
  grep -q '^ERROR m-twice: the text to find is in app.sh [0-9]* times, not once' <<<"$OUT" &&
  grep -q '^KILLED m-killed' <<<"$OUT" &&
  grep -qx 'replay-faults: 3 replayed: 1 KILLED, 0 SURVIVED, 0 TIMEOUT, 2 ERROR' <<<"$OUT" && clean "$dir"; then
  result "replay-faults: text to find missing or repeated is an ERROR, exit non-zero, the rest still run" yes ""
else
  result "replay-faults: text to find missing or repeated is an ERROR, exit non-zero, the rest still run" no "$(describe)"
fi

# 4. The baseline: a check name the check command never prints, and a check that already
# fails without the fault, are ERRORs, not KILLED.
printf 'edited\n' >"$dir/other.txt"
run_in "$dir" bash "$REPLAY" m-wrong m-other
git -C "$dir" checkout -q -- other.txt
if [ "$STATUS" -eq 1 ] && grep -q '^ERROR m-wrong: without the fault the check command printed no PASS line for "greetings"' <<<"$OUT" &&
  grep -q '^ERROR m-other: the check "other" already fails without the fault' <<<"$OUT" &&
  ! grep -q '^KILLED' <<<"$OUT" && clean "$dir"; then
  result "replay-faults: a wrong check name, or a check already failing, is an ERROR" yes ""
else
  result "replay-faults: a wrong check name, or a check already failing, is an ERROR" no "$(describe)"
fi

# 5. The replays judge the working tree as it is: an uncommitted change that weakens the
# check makes the fault survive. The project's index and files are left as they were.
printf 'echo "PASS  greeting"\n' >"$dir/checks/greeting.sh"
run_in "$dir" bash "$REPLAY" m-killed
status_after="$(git -C "$dir" status --porcelain)"
git -C "$dir" checkout -q -- checks/greeting.sh
if [ "$STATUS" -eq 1 ] && grep -q '^SURVIVED m-killed' <<<"$OUT" && [ "$status_after" = " M checks/greeting.sh" ] && clean "$dir"; then
  result "replay-faults: replays run on the working tree, uncommitted changes included" yes ""
else
  result "replay-faults: replays run on the working tree, uncommitted changes included" no "$(describe)
status after: $status_after"
fi

# 7. Refusals, exit 2, before any worktree: no --skip-reviewed in the check command, an
# unknown id, and a malformed line.
printf 'sh check.sh\n' >"$dir/.harness/check-command"
run_in "$dir" bash "$REPLAY" m-killed
out1="$OUT$ERR" s1=$STATUS
git -C "$dir" checkout -q -- .harness/check-command
run_in "$dir" bash "$REPLAY" no-such-id
out2="$OUT$ERR" s2=$STATUS
printf 'broken\tapp.sh\tonly three\n' >>"$dir/.harness/mutations.tsv"
run_in "$dir" bash "$REPLAY"
out3="$OUT$ERR" s3=$STATUS
git -C "$dir" checkout -q -- .harness/mutations.tsv
if [ "$s1" -eq 2 ] && grep -q 'does not pass --skip-reviewed' <<<"$out1" &&
  [ "$s2" -eq 2 ] && grep -q 'no entry with the id "no-such-id"' <<<"$out2" &&
  [ "$s3" -eq 2 ] && grep -q 'line 9 has 3 tab-separated fields, not 5' <<<"$out3" &&
  grep -q 'Nothing was replayed' <<<"$out1$out2$out3" && ! grep -q replayed: <<<"$out1$out2$out3" && clean "$dir"; then
  result "replay-faults: no --skip-reviewed, an unknown id or a malformed line: exit 2, nothing replayed" yes ""
else
  result "replay-faults: no --skip-reviewed, an unknown id or a malformed line: exit 2, nothing replayed" no "1: exit $s1 $out1
2: exit $s2 $out2
3: exit $s3 $out3"
fi

# 7b. The event log: each run that reached its totals line (cases 1-5) left one REPLAYED
# line with its counts, its baseline's seconds (compared apart: they vary) and the ids asked
# for; the refusals left none (P6 has the interrupted run). A run of every entry says "all".
run_in "$dir" bash "$REPLAY"
logged="$(cut -f2,5-7 "$dir/.git/harness-kit/events.tsv" 2>/dev/null)"
got="$(sed -E 's/,baseline=[0-9]+\.[0-9]{2}s//' <<<"$logged")"
want="$(printf '%s\tREPLAYED\t%s\t%s\n' \
  replay-faults.sh killed=1,survived=0,timeout=0,error=0 "ids: m-killed" \
  replay-faults.sh killed=0,survived=1,timeout=0,error=0 "ids: m-survived" \
  replay-faults.sh killed=1,survived=0,timeout=0,error=2 "ids: m-error m-twice m-killed" \
  replay-faults.sh killed=0,survived=0,timeout=0,error=2 "ids: m-wrong m-other" \
  replay-faults.sh killed=0,survived=1,timeout=0,error=0 "ids: m-killed" \
  replay-faults.sh killed=3,survived=1,timeout=0,error=3 all)"
if [ "$STATUS" -eq 1 ] && grep -qx 'replay-faults: 7 replayed: 3 KILLED, 1 SURVIVED, 0 TIMEOUT, 3 ERROR' <<<"$OUT" && [ "$got" = "$want" ] &&
  [ "$(grep -cE ',baseline=[0-9]+\.[0-9]{2}s' <<<"$logged")" = 6 ] &&
  [ -z "$(git -C "$dir" status --porcelain)" ] && clean "$dir"; then
  result "replay-faults: each finished run's counts go to .git/harness-kit/events.tsv; refused and interrupted runs add none" yes ""
else
  result "replay-faults: each finished run's counts go to .git/harness-kit/events.tsv; refused and interrupted runs add none" no "$(describe)
log:
$logged
wanted (without the baseline field, which every line must have):
$want"
fi

# 7c. A fragile entry, whose text to find holds a version or a date, is an ERROR and is not
# replayed; the other entries still run.
frag="$(new_project fragile "${M_KILLED}m-version\tapp.sh\t# the greeting, v1.2.3\t#\tgreeting\nm-date\tapp.sh\t# 2026-09-27 the greeting\t#\tgreeting\n")"
run_in "$frag" bash "$REPLAY"
if [ "$STATUS" -eq 1 ] && grep -q '^ERROR m-version: fragile entry: its text to find holds the version "v1.2.3"' <<<"$OUT" &&
  grep -q '^ERROR m-date: fragile entry: its text to find holds the date "2026-09-27"' <<<"$OUT" &&
  grep -q '^KILLED m-killed' <<<"$OUT" && ! grep -q 'replaying m-version\|replaying m-date' <<<"$ERR" &&
  grep -qx 'replay-faults: 3 replayed: 1 KILLED, 0 SURVIVED, 0 TIMEOUT, 2 ERROR' <<<"$OUT" && clean "$frag"; then
  result "replay-faults: an entry whose find text holds a version or a date is an ERROR, fragile entry" yes ""
else
  result "replay-faults: an entry whose find text holds a version or a date is an ERROR, fragile entry" no "$(describe)"
fi

# 7d. .harness/check-only: without the file, each entry's run is the whole check command,
# as the baseline's is; with it, "<check command> --only <check>", so only the entry's
# check is in its run. The verdicts are the same both ways.
only="$(new_project only "$M_KILLED$M_OTHER")"
run_in "$only" bash "$REPLAY"
whole_out="$OUT" whole_status=$STATUS whole_err="$ERR"
whole="$(sed -n 's/.*each run.s output is in \(.*\) (baseline.log.*/\1/p' <<<"$ERR")"
touch "$only/.harness/check-only"
run_in "$only" bash "$REPLAY"
results="$(sed -n 's/.*each run.s output is in \(.*\) (baseline.log.*/\1/p' <<<"$ERR")"
rm -f "$only/.harness/check-only"
if [ "$whole_status" -eq 0 ] && [ "$STATUS" -eq 0 ] && [ "$OUT" = "$whole_out" ] &&
  grep -qx 'replay-faults: 2 replayed: 2 KILLED, 0 SURVIVED, 0 TIMEOUT, 0 ERROR' <<<"$OUT" &&
  ! grep -q 'check-only' <<<"$whole_err" &&
  grep -q 'greeting' "$whole/m-killed.log" && grep -q 'other' "$whole/m-killed.log" &&
  grep -q 'greeting' "$whole/m-other.log" && grep -q 'other' "$whole/m-other.log" &&
  grep -q "each entry runs only its own check (.harness/check-only): sh check.sh --skip-reviewed --only <check>" <<<"$ERR" &&
  grep -q 'greeting' "$results/m-killed.log" && ! grep -q 'other' "$results/m-killed.log" &&
  grep -q 'other' "$results/m-other.log" && ! grep -q 'greeting' "$results/m-other.log" &&
  grep -q 'greeting' "$results/baseline.log" && grep -q 'other' "$results/baseline.log" && clean "$only"; then
  result "replay-faults: without .harness/check-only every entry runs the whole check; with it, only its own" yes ""
else
  result "replay-faults: without .harness/check-only every entry runs the whole check; with it, only its own" no "without the file: exit $whole_status
$whole_out
$whole_err
with it: $(describe)"
fi

# ---------------------------------------------------------------------------------------
# replay-faults.sh in parallel
# ---------------------------------------------------------------------------------------

# new_pool NAME: a repository whose check.sh prints PASS or FAIL for f1 to f4 (PASS when
# fN.txt says content), with the entries e1 to e4, each changing one of those files. Each
# run first logs "run <what>" to $POOL_LOG, when that is set, where <what> is the changed
# file (f1 to f4) or baseline; with $POOL_OUTER_LOG set, it logs its HARNESS_KIT_REPLAY_OUTER. With $POOL_DIR set, a run is held: it makes the folder
# running.<what> there, writes "start <what> <how many are running> <its pid>" to the pipe
# $POOL_DIR/events, waits for a line from the pipe $POOL_DIR/go.<what>, then removes its
# folder and finishes. Prints the repository's path.
new_pool() {
  local dir="$WORK/$1" n
  mkdir -p "$dir/.harness"
  git -C "$dir" init -q -b main
  for n in 1 2 3 4; do printf 'content\n' >"$dir/f$n.txt"; done
  cat >"$dir/check.sh" <<'CHECK'
case " $* " in *" --skip-reviewed "*) ;; *) echo "FAIL check.sh: no --skip-reviewed"; exit 1 ;; esac
what=baseline
for f in f1 f2 f3 f4; do [ "$(cat $f.txt)" = content ] || what=$f; done
[ -z "${POOL_LOG:-}" ] || echo "run $what" >>"$POOL_LOG"
[ -z "${POOL_OUTER_LOG:-}" ] || echo "${HARNESS_KIT_REPLAY_OUTER:-unset}" >>"$POOL_OUTER_LOG"
if [ -n "${POOL_DIR:-}" ]; then
  mkdir "$POOL_DIR/running.$what"
  echo "start $what $(ls -d "$POOL_DIR"/running.* | wc -l | tr -d ' ') $$" >"$POOL_DIR/events"
  read -r go <"$POOL_DIR/go.$what"
  rmdir "$POOL_DIR/running.$what"
fi
status=0
for f in f1 f2 f3 f4; do
  if [ "$(cat $f.txt)" = content ]; then echo "PASS $f"; else echo "FAIL $f"; status=1; fi
done
exit $status
CHECK
  printf 'sh check.sh --skip-reviewed\n' >"$dir/.harness/check-command"
  printf '# id\tfile\tfind\treplacement\tcheck\n' >"$dir/.harness/mutations.tsv"
  for n in 1 2 3 4; do printf 'e%s\tf%s.txt\tcontent\tchanged\tf%s\n' $n $n $n >>"$dir/.harness/mutations.tsv"; done
  git -C "$dir" add -A && git -C "$dir" commit -q -m "main: initial"
  echo "$dir"
}

# pool_start DIR PIPES [NAME=VALUE...]: starts replay-faults.sh (every entry) in DIR, in
# the background, with those variables and POOL_DIR=PIPES, a fresh folder with the pipes
# events and go.<what>. Its stdout and stderr go to $WORK/pool.out and $WORK/pool.err, its
# pid to PIPES/pid, and "exit <status>" to the events pipe when it ends. File descriptor 3
# holds the events pipe open for reading and writing, so that no open of it ever blocks.
pool_start() {
  local dir="$1" pipes="$2" what
  shift 2
  rm -rf "$pipes" && mkdir -p "$pipes"
  mkfifo "$pipes/events"
  for what in baseline f1 f2 f3 f4; do mkfifo "$pipes/go.$what"; done
  exec 3<>"$pipes/events"
  (
    cd "$dir" || exit 1
    env "$@" POOL_DIR="$pipes" bash "$REPLAY" >"$WORK/pool.out" 2>"$WORK/pool.err" 3>&- &
    echo $! >"$pipes/pid"
    wait $!
    echo "exit $?" >"$pipes/events"
  ) &
}

# release_run PIPES WHAT: lets the held run WHAT finish, through a writer in the background.
# Opening a pipe for writing waits until a reader opens it, and a broken script may have
# ended the run already (a hang of 7 hours 23 minutes, D2, came from that wait), so the
# controller never makes that open itself: it only ever waits in read -t 10. The writers'
# pids go to POOL_WRITERS, and stop_writers ends any still waiting.
POOL_WRITERS=""
release_run() {
  (echo go >"$1/go.$2") &
  POOL_WRITERS="$POOL_WRITERS $!"
}
stop_writers() {
  local w
  for w in $POOL_WRITERS; do kill "$w" 2>/dev/null && wait "$w" 2>/dev/null; done
  POOL_WRITERS=""
}

# pool_serve PIPES JOBS TOTAL: reads the events pipe and lets held runs finish: the last
# waiting one by name (baseline, then f1 to f4), whenever JOBS are waiting at once, or once
# all TOTAL runs have started.
# Sets SERVED (the largest running count a run reported), STARTS and FINISHES (the runs,
# in the order they started and were let finish), POOL_STATUS (the script's exit status)
# and POOL_TIMEOUT=yes if the pipe stayed quiet for 10 seconds, which happens only when
# the script is broken; then every waiting run is let go, and each one that starts after,
# until the script ends or the pipe is quiet again. Closes file descriptor 3.
pool_serve() {
  local pipes="$1" jobs="$2" total="$3" line newest waiting="" started=0 draining=no
  SERVED=0 STARTS="" FINISHES="" POOL_STATUS="" POOL_TIMEOUT=no
  while :; do
    if ! read -r -t 10 line <&3; then
      [ "$draining" = no ] || break
      POOL_TIMEOUT=yes draining=yes line=""
    fi
    set -- $line
    case "${1:-}" in
      exit) POOL_STATUS="$2" && break ;;
      start)
        started=$((started + 1)) STARTS="$STARTS $2" waiting="$waiting $2"
        [ "$3" -le "$SERVED" ] || SERVED="$3"
        ;;
    esac
    while [ -n "$waiting" ] && { [ "$draining" = yes ] || [ "$started" -ge "$total" ] ||
      [ "$(wc -w <<<"$waiting" | tr -d ' ')" -ge "$jobs" ]; }; do
      waiting="$(tr ' ' '\n' <<<"$waiting" | grep . | sort | tr '\n' ' ')"
      waiting=" ${waiting% }" newest="${waiting##* }" waiting="${waiting% *}"
      FINISHES="$FINISHES $newest"
      release_run "$pipes" "$newest"
    done
  done
  exec 3<&-
  stop_writers
}

POOL_KILLED="$(printf 'KILLED e%s: "f%s" failed with the fault in f%s.txt\n' 1 1 1 2 2 2 3 3 3 4 4 4)
replay-faults: 4 replayed: 4 KILLED, 0 SURVIVED, 0 TIMEOUT, 0 ERROR"

# P1. The runs go side by side, never more at once than the CPU count (4 here; the 9 jobs
# asked for are capped, as the script says): the first 4 runs are held until all 4 are
# running, and none reports more than 4 running. They are let finish last name first, so
# they finish in another order than the file's, and the verdicts are still printed in file
# order.
pool="$(new_pool pool)"
pool_start "$pool" "$WORK/pool-pipes" HARNESS_KIT_REPLAY_CPUS=4 HARNESS_KIT_REPLAY_JOBS=9
pool_serve "$WORK/pool-pipes" 4 5
OUT="$(cat "$WORK/pool.out")" ERR="$(cat "$WORK/pool.err")" STATUS="$POOL_STATUS"
if [ "$POOL_TIMEOUT" = no ] && [ "$SERVED" -eq 4 ] && [ "$STATUS" = 0 ] && [ "$OUT" = "$POOL_KILLED" ] &&
  grep -q 'up to 4 checks at once (4 CPUs)' <<<"$ERR" &&
  [ "$(tr ' ' '\n' <<<"$STARTS" | grep . | sort | tr '\n' ' ')" = "baseline f1 f2 f3 f4 " ] &&
  [ "$FINISHES" = " f3 f4 f2 f1 baseline" ] && clean "$pool"; then
  result "replay-faults: entries run in parallel, never more at once than the CPU count, verdicts in file order" yes ""
else
  result "replay-faults: entries run in parallel, never more at once than the CPU count, verdicts in file order" no "$(describe)
most running at once: $SERVED (4 wanted); started:$STARTS; let finish:$FINISHES; the pipe went quiet: $POOL_TIMEOUT"
fi

# P2. The mixed entries, with other.txt changed so that "other" already fails without any
# fault: one job at a time and 4 at once print the same verdict lines and totals, and exit
# the same way, and those are the verdicts a replay gives (m-other's is the baseline's
# ERROR).
printf 'edited\n' >"$dir/other.txt"
HARNESS_KIT_REPLAY_JOBS=1 run_in "$dir" bash "$REPLAY"
serial_out="$OUT" serial_status=$STATUS
HARNESS_KIT_REPLAY_CPUS=4 HARNESS_KIT_REPLAY_JOBS=4 run_in "$dir" bash "$REPLAY"
git -C "$dir" checkout -q -- other.txt
if [ "$serial_status" -eq 1 ] && [ "$STATUS" -eq 1 ] && [ "$OUT" = "$serial_out" ] &&
  grep -q '^KILLED m-killed: ' <<<"$OUT" && grep -q '^SURVIVED m-survived: ' <<<"$OUT" &&
  grep -q '^ERROR m-error: the text to find is not in app.sh$' <<<"$OUT" &&
  grep -q '^ERROR m-other: the check "other" already fails without the fault' <<<"$OUT" &&
  grep -q '^ERROR m-wrong: without the fault the check command printed no PASS line' <<<"$OUT" &&
  grep -qx 'replay-faults: 7 replayed: 2 KILLED, 1 SURVIVED, 0 TIMEOUT, 4 ERROR' <<<"$OUT" && clean "$dir"; then
  result "replay-faults: in parallel, the same verdict lines, totals and exit status as one at a time" yes ""
else
  result "replay-faults: in parallel, the same verdict lines, totals and exit status as one at a time" no "one at a time: exit $serial_status
$serial_out
4 at once: $(describe)"
fi

# P3. One baseline per session: whatever the number of jobs, the check runs once without
# any fault, and once per entry.
rm -f "$WORK/pool-1.log" "$WORK/pool-4.log"
POOL_LOG="$WORK/pool-1.log" HARNESS_KIT_REPLAY_JOBS=1 run_in "$pool" bash "$REPLAY"
out1="$OUT" s1=$STATUS
POOL_LOG="$WORK/pool-4.log" HARNESS_KIT_REPLAY_CPUS=4 HARNESS_KIT_REPLAY_JOBS=4 run_in "$pool" bash "$REPLAY"
runs="run baseline run f1 run f2 run f3 run f4"
if [ "$s1" -eq 0 ] && [ "$STATUS" -eq 0 ] && [ "$out1" = "$POOL_KILLED" ] && [ "$OUT" = "$POOL_KILLED" ] &&
  [ "$(sort "$WORK/pool-1.log" | tr '\n' ' ')" = "$runs " ] && [ "$(sort "$WORK/pool-4.log" | tr '\n' ' ')" = "$runs " ] &&
  clean "$pool"; then
  result "replay-faults: one baseline run per session, whatever the job count" yes ""
else
  result "replay-faults: one baseline run per session, whatever the job count" no "1 job: exit $s1, runs: $(tr '\n' ' ' <"$WORK/pool-1.log" 2>/dev/null)
4 jobs: exit $STATUS, runs: $(tr '\n' ' ' <"$WORK/pool-4.log" 2>/dev/null)"
fi

# N1. A replay inside another replay. Every check run is told it runs inside one
# (HARNESS_KIT_REPLAY_OUTER=1). A replay started with that set takes the CPU count as 1, so
# a project whose check runs replays does not start a pool the size of the machine inside
# each outer run; HARNESS_KIT_REPLAY_CPUS still sets the pool when given.
rm -f "$WORK/outer.log"
run_in "$pool" env -u HARNESS_KIT_REPLAY_OUTER POOL_OUTER_LOG="$WORK/outer.log" bash "$REPLAY"
outer_status=$STATUS outer_err="$ERR"
run_in "$pool" env HARNESS_KIT_REPLAY_OUTER=1 bash "$REPLAY"
inner_status=$STATUS inner_out="$OUT" inner_err="$ERR"
run_in "$pool" env HARNESS_KIT_REPLAY_OUTER=1 HARNESS_KIT_REPLAY_CPUS=3 bash "$REPLAY"
if [ "$outer_status" -eq 0 ] && [ "$(sort -u "$WORK/outer.log" 2>/dev/null)" = 1 ] && [ "$(wc -l <"$WORK/outer.log" | tr -d ' ')" = 5 ] &&
  ! grep -q 'inside another replay' <<<"$outer_err" &&
  [ "$inner_status" -eq 0 ] && [ "$inner_out" = "$POOL_KILLED" ] &&
  grep -q 'up to 1 checks at once (1 CPUs, taken as 1 inside another replay)' <<<"$inner_err" &&
  [ "$STATUS" -eq 0 ] && grep -q 'up to 3 checks at once (3 CPUs)$' <<<"$ERR" && clean "$pool"; then
  result "replay-faults: a replay inside another replay runs one check at a time; its checks are told they run inside one" yes ""
else
  result "replay-faults: a replay inside another replay runs one check at a time; its checks are told they run inside one" no "outer: exit $outer_status; its checks' HARNESS_KIT_REPLAY_OUTER: $(tr '\n' ' ' <"$WORK/outer.log" 2>/dev/null)
$outer_err
inside: exit $inner_status
$inner_err
inside, with HARNESS_KIT_REPLAY_CPUS=3: $(describe)"
fi

# P4. Parts run apart, as harness-kit's CI runs them: the baseline part and shards 1/3,
# 2/3 and 3/3 of the mixed entries, each into its own folder (none prints a verdict). The
# shards between them run every entry once, and --judge on the four folders prints what a
# whole run prints, and exits as it does.
run_in "$dir" bash "$REPLAY"
whole_out="$OUT" whole_status=$STATUS
parts="$WORK/parts"
rm -rf "$parts"
part_status="" part_out=""
for p in baseline 1/3 2/3 3/3; do
  run_in "$dir" bash "$REPLAY" --part "$p" --out "$parts/${p%/3}"
  part_status="$part_status$STATUS" part_out="$part_out$OUT"
done
covered="$(node -e '
  const fs = require("fs"), path = require("path");
  const ids = process.argv.slice(1).flatMap((dir) => fs.readdirSync(dir).filter((n) => n.startsWith("part.")).flatMap((n) => JSON.parse(fs.readFileSync(path.join(dir, n), "utf8")).entries));
  console.log(ids.sort().join(" "));' "$parts/baseline" "$parts/1" "$parts/2" "$parts/3")"
run_in "$dir" bash "$REPLAY" --judge "$parts/baseline" "$parts/1" "$parts/2" "$parts/3"
if [ "$part_status" = 0000 ] && [ -z "$part_out" ] && [ "$covered" = "m-also m-error m-killed m-other m-survived m-twice m-wrong" ] &&
  [ "$STATUS" -eq "$whole_status" ] && [ "$OUT" = "$whole_out" ] && clean "$dir"; then
  result "replay-faults: --part 1/3 to 3/3 cover every entry once, and --judge with the baseline part prints what one whole run prints" yes ""
else
  result "replay-faults: --part 1/3 to 3/3 cover every entry once, and --judge with the baseline part prints what one whole run prints" no "parts: exit $part_status, stdout: $part_out
entries the shards ran: $covered
whole run: exit $whole_status
$whole_out
judged: $(describe)"
fi

# P5. --judge judges only one whole replay of this working tree: a part run before the
# working tree changed is refused (exit 2, nothing judged), and an entry whose shard's
# results are missing (3/3's here) is an ERROR, "no result", not a verdict.
run_in "$dir" bash "$REPLAY" --part baseline --out "$WORK/snap/baseline"
printf 'new\n' >"$dir/untracked.txt"
run_in "$dir" bash "$REPLAY" --part 1/1 --out "$WORK/snap/1"
run_in "$dir" bash "$REPLAY" --judge "$WORK/snap/baseline" "$WORK/snap/1"
rm -f "$dir/untracked.txt"
snap_out="$OUT$ERR" snap_status=$STATUS
run_in "$dir" bash "$REPLAY" --judge "$parts/baseline" "$parts/1" "$parts/2"
if [ "$snap_status" -eq 2 ] && grep -q 'is from another snapshot' <<<"$snap_out" && grep -q 'Nothing was judged' <<<"$snap_out" &&
  ! grep -q 'replayed:' <<<"$snap_out" && [ "$STATUS" -eq 1 ] &&
  grep -qx 'ERROR m-error: no result: no part of the replay ran it (a part.s results are missing)' <<<"$OUT" &&
  grep -q '^KILLED m-killed' <<<"$OUT" && clean "$dir"; then
  result "replay-faults: --judge refuses parts from another snapshot; an entry with no result is an ERROR" yes ""
else
  result "replay-faults: --judge refuses parts from another snapshot; an entry with no result is an ERROR" no "another snapshot: exit $snap_status
$snap_out
a shard missing: $(describe)"
fi

# P6. Interrupted (TERM) while two held runs are going: every check is stopped (none is
# alive after the script ends), every worktree is removed, the exit status is 143 and
# no line is added to the event log. The runs are never let finish.
replayed_before="$(grep -c REPLAYED "$pool/.git/harness-kit/events.tsv" 2>/dev/null)"
pool_start "$pool" "$WORK/int-pipes" HARNESS_KIT_REPLAY_CPUS=2
pids="" started=0 int_timeout=no
while [ "$started" -lt 2 ]; do
  read -r -t 10 line <&3 || { int_timeout=yes && break; }
  set -- $line
  [ "$1" != start ] || { started=$((started + 1)) && pids="$pids $4"; }
done
worktrees_during="$(git -C "$pool" worktree list --porcelain | grep -c '^worktree ')"
kill -TERM "$(cat "$WORK/int-pipes/pid")"
int_status=""
while [ -z "$int_status" ]; do
  read -r -t 10 line <&3 || { int_timeout=yes && break; }
  set -- $line
  [ "$1" != exit ] || int_status="$2"
done
outlived=""
for p in $pids; do ! kill -0 "$p" 2>/dev/null || outlived="$outlived $p"; done
# A broken script leaves checks running, and may wait for them: stop them, so it ends.
for p in $outlived; do kill -TERM "$p" 2>/dev/null; done
while [ -z "$int_status" ]; do
  read -r -t 10 line <&3 || break
  set -- $line
  [ "$1" != exit ] || int_status="$2"
done
exec 3<&-
ERR="$(cat "$WORK/pool.err")"
if [ "$int_timeout" = no ] && [ "$worktrees_during" -eq 3 ] && [ "$int_status" = 143 ] && [ -z "$outlived" ] &&
  grep -q 'interrupted; the checks were stopped and their worktrees removed' <<<"$ERR" &&
  [ "$(grep -c REPLAYED "$pool/.git/harness-kit/events.tsv" 2>/dev/null)" = "$replayed_before" ] && clean "$pool"; then
  result "replay-faults: interrupted with jobs running, it stops every check and removes every worktree" yes ""
else
  result "replay-faults: interrupted with jobs running, it stops every check and removes every worktree" no "exit $int_status (143 wanted); checks alive after it ended:${outlived:- none}
worktrees while two ran: $worktrees_during (3 wanted); the pipe went quiet: $int_timeout
stderr: $ERR"
fi

# ---------------------------------------------------------------------------------------
# replay-faults.sh's time limits (D2)
# ---------------------------------------------------------------------------------------
# These cases wait for real time, for their own tiny limits only (about a second each), as
# the person allowed: at most about 5 seconds in this file.

# new_limits NAME MUTATIONS: a repository whose check.sh prints PASS app when app.txt says
# ok, FAIL app otherwise; when app.txt holds "hang", or the file hang-always exists, it
# logs its pid to $LIMIT_PIDS and hangs (exec sleep 3600) until it is stopped; when it holds
# "deaf", it hangs the same way but ignores SIGTERM. The check command execs check.sh, so
# the run's own process is the one that hangs. Prints its path.
new_limits() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.harness"
  git -C "$dir" init -q -b main
  printf 'ok\n' >"$dir/app.txt"
  cat >"$dir/check.sh" <<'CHECK'
case " $* " in *" --skip-reviewed "*) ;; *) echo "FAIL check.sh: no --skip-reviewed"; exit 1 ;; esac
if grep -q deaf app.txt; then echo "$$" >>"${LIMIT_PIDS:-/dev/null}"; trap '' TERM; exec sleep 3600; fi
if [ -e hang-always ] || grep -q hang app.txt; then echo "$$" >>"${LIMIT_PIDS:-/dev/null}"; exec sleep 3600; fi
if [ "$(cat app.txt)" = ok ]; then echo "PASS app"; else echo "FAIL app"; exit 1; fi
CHECK
  printf 'exec sh check.sh --skip-reviewed\n' >"$dir/.harness/check-command"
  printf "# id\tfile\tfind\treplacement\tcheck\n$2" >"$dir/.harness/mutations.tsv"
  git -C "$dir" add -A && git -C "$dir" commit -q -m "main: initial"
  echo "$dir"
}

# run_guarded DIR [ARGS...]: replay-faults.sh ARGS in DIR, in the background, waited for at
# most 10 seconds (read -t on a pipe written when it ends); stopped (TERM) if it is still
# going then. Variables set before the call reach it. Sets OUT, ERR, STATUS, and GUARDED=no
# when the 10 seconds ran out, which happens only when the script is broken.
run_guarded() {
  local dir="$1" line
  shift
  rm -f "$WORK/guard.pipe" && mkfifo "$WORK/guard.pipe"
  exec 4<>"$WORK/guard.pipe"
  (
    cd "$dir" || exit 1
    bash "$REPLAY" "$@" >"$WORK/guard.out" 2>"$WORK/guard.err" 4>&- &
    echo $! >"$WORK/guard.pid"
    wait $!
    echo "exit $?" >"$WORK/guard.pipe"
  ) &
  GUARDED=yes
  if ! read -r -t 10 line <&4; then
    GUARDED=no
    kill -TERM "$(cat "$WORK/guard.pid")" 2>/dev/null
    read -r -t 10 line <&4
  fi
  exec 4<&-
  STATUS="${line#exit }" OUT="$(cat "$WORK/guard.out")" ERR="$(cat "$WORK/guard.err")"
}

# alive FILE: the pids in FILE that are still running, on one line.
alive() {
  local p found=""
  for p in $(cat "$1" 2>/dev/null); do ! kill -0 "$p" 2>/dev/null || found="$found $p"; done
  echo "$found"
}

# T1 (D2's test). A fault that makes the check hang (and ignore SIGTERM, for T1b) is stopped
# at its run limit (the floor, 1.5 seconds here, as the tiny baseline times 3 is less) and is
# a TIMEOUT; the other entry is still KILLED, the exit status is 1, the hung check is not
# left running, and no worktree is left.
limits="$(new_limits limits 'h-hang\tapp.txt\tok\tdeaf-hang\tapp\nh-ok\tapp.txt\tok\tbad\tapp\n')"
rm -f "$WORK/limit-pids"
LIMIT_PIDS="$WORK/limit-pids" HARNESS_KIT_REPLAY_CPUS=2 HARNESS_KIT_REPLAY_LIMIT_MULTIPLE=3 HARNESS_KIT_REPLAY_GRACE_SECONDS=1 \
  HARNESS_KIT_REPLAY_LIMIT_FLOOR_SECONDS=1.5 HARNESS_KIT_REPLAY_BASELINE_FALLBACK_SECONDS=5 run_guarded "$limits"
left="$(alive "$WORK/limit-pids")"
if [ "$GUARDED" = yes ] && [ "$STATUS" = 1 ] && [ -z "$left" ] && [ -s "$WORK/limit-pids" ] &&
  grep -q '^TIMEOUT h-hang: ran longer than its limit of 1.5 seconds (the floor; 3 times the baseline.s [0-9.]* seconds is less); stopped after [0-9.]* seconds$' <<<"$OUT" &&
  grep -q '^KILLED h-ok: ' <<<"$OUT" && grep -qx 'replay-faults: 2 replayed: 1 KILLED, 0 SURVIVED, 1 TIMEOUT, 0 ERROR' <<<"$OUT" &&
  clean "$limits"; then
  result "replay-faults: a hanging check is stopped at its time limit and reported TIMEOUT; the others still get verdicts" yes ""
else
  result "replay-faults: a hanging check is stopped at its time limit and reported TIMEOUT; the others still get verdicts" no "$(describe)
ended within the guard: $GUARDED; hung checks still running:${left:- none}"
fi

# T1b. The same run: h-hang's check ignores SIGTERM, so it is force-killed (SIGKILL to its
# process group) when the 1-second grace period after its 1.5-second limit ends: stopped
# after about 2.5 seconds (not before 2.3: the grace was given; not after 4), and not left.
stopped="$(sed -n 's/^TIMEOUT h-hang: .*; stopped after \([0-9.]*\) seconds$/\1/p' <<<"$OUT")"
if [ "$GUARDED" = yes ] && [ -n "$stopped" ] && [ -z "$left" ] && awk -v s="$stopped" 'BEGIN { exit !(s >= 2.3 && s <= 4) }'; then
  result "replay-faults: a run that ignores the stop signal is force-killed when its grace period ends" yes ""
else
  result "replay-faults: a run that ignores the stop signal is force-killed when its grace period ends" no "stopped after: ${stopped:-no TIMEOUT line} seconds (2.3 to 4 wanted); hung checks still running:${left:- none}
$(describe)"
fi

# T2. The limits as the script prints them. A first session, with no baseline recorded: the
# baseline's limit is the fallback (5 s), the run limit is set when the baseline ends (the
# floor, 3 s), and the session's limit is the baseline's plus 1 round (2 entries, 2 jobs) of
# the run limit, first with the fallback in place of the run limit (10 s), then with it (8 s).
# Then, after a REPLAYED line recording a 2-second baseline, a baseline part: its limit is 3
# times that (6 s), and its session's is that alone (no fault runs, 0 rounds). A shard given
# that baseline part (--baseline-from) knows its run limit from the start, and its session's
# limit has no baseline in it. No run here comes near its limit: nothing waits.
derive="$(new_limits derive 'd-a\tapp.txt\tok\tbad\tapp\nd-b\tapp.txt\tok\tno\tapp\n')"
export HARNESS_KIT_REPLAY_CPUS=2 HARNESS_KIT_REPLAY_LIMIT_MULTIPLE=3 HARNESS_KIT_REPLAY_LIMIT_FLOOR_SECONDS=3 HARNESS_KIT_REPLAY_BASELINE_FALLBACK_SECONDS=5
run_guarded "$derive"
first="$ERR" first_status=$STATUS
printf '2026-09-29T00:00:00Z\treplay-faults.sh\tmain\tnone\tREPLAYED\tkilled=2,survived=0,timeout=0,error=0,baseline=2.00s\tall\n' >>"$derive/.git/harness-kit/events.tsv"
run_guarded "$derive" --part baseline --out "$WORK/derive-parts/baseline"
second="$ERR" second_status=$STATUS
run_guarded "$derive" --part 1/1 --out "$WORK/derive-parts/1" --baseline-from "$WORK/derive-parts/baseline"
shard="$ERR" shard_status=$STATUS
# For B1, below: a recorded baseline of 0.5 seconds, whose 3 times is under the 3-second floor.
printf '2026-09-29T00:00:01Z\treplay-faults.sh\tmain\tnone\tREPLAYED\tkilled=2,survived=0,timeout=0,error=0,baseline=0.50s\tall\n' >>"$derive/.git/harness-kit/events.tsv"
run_guarded "$derive" --part baseline --out "$WORK/derive-parts/floor"
floored="$ERR" floored_status=$STATUS
unset HARNESS_KIT_REPLAY_CPUS HARNESS_KIT_REPLAY_LIMIT_MULTIPLE HARNESS_KIT_REPLAY_LIMIT_FLOOR_SECONDS HARNESS_KIT_REPLAY_BASELINE_FALLBACK_SECONDS
limit_lines() { grep 'time limit' <<<"$1" | sed -E 's/harness-kit replay-faults.sh: //; s/baseline.s [0-9.]+ seconds is less/baseline'"'"'s B seconds is less/'; }
want_first="time limit for the baseline: 5 seconds (no baseline recorded: the fallback)
time limit per run: set when the baseline ends
time limit for the session: 10 seconds (the baseline's limit of 5 seconds plus 1 round(s) of the run limit of 5 seconds)
time limit per run: 3 seconds (the floor; 3 times the baseline's B seconds is less)
time limit for the session: 8 seconds (the baseline's limit of 5 seconds plus 1 round(s) of the run limit of 3 seconds)"
want_second="time limit for the baseline: 6 seconds (3 times the last recorded baseline's 2 seconds)
time limit for the session: 6 seconds (the baseline's limit of 6 seconds plus 0 round(s) of the run limit of 6 seconds)"
want_shard="time limit per run: 3 seconds (the floor; 3 times the baseline's B seconds is less)
time limit for the session: 3 seconds (1 round(s) of the run limit of 3 seconds)"
if [ "$first_status" = 0 ] && [ "$second_status" = 0 ] && [ "$shard_status" = 0 ] &&
  [ "$(limit_lines "$first")" = "$want_first" ] && [ "$(limit_lines "$second")" = "$want_second" ] &&
  [ "$(limit_lines "$shard")" = "$want_shard" ] && clean "$derive"; then
  result "replay-faults: a run's limit is the multiple of this session's baseline, never under the floor; the baseline's own is the multiple of the last recorded baseline, or the fallback" yes ""
else
  result "replay-faults: a run's limit is the multiple of this session's baseline, never under the floor; the baseline's own is the multiple of the last recorded baseline, or the fallback" no "first session: exit $first_status
$(limit_lines "$first")
wanted:
$want_first
baseline part: exit $second_status
$(limit_lines "$second")
wanted:
$want_second
shard: exit $shard_status
$(limit_lines "$shard")
wanted:
$want_shard"
fi

# B1. The baseline's limit is never below the floor: with a recorded baseline of 0.5 s, 3
# times that (1.5 s) is under the 3-second floor, so the baseline gets 3 seconds.
if [ "$floored_status" = 0 ] &&
  grep -q "time limit for the baseline: 3 seconds (the floor; 3 times the last recorded baseline's 0.5 seconds is less)" <<<"$floored"; then
  result "replay-faults: the baseline's limit is never below the floor" yes ""
else
  result "replay-faults: the baseline's limit is never below the floor" no "exit $floored_status
$(limit_lines "$floored")"
fi

# T3. The session's limit (2 seconds here, set by HARNESS_KIT_REPLAY_SESSION_SECONDS, below
# one run's limit of 5 s) runs out with one job and three hanging entries: the one running
# is stopped and is a TIMEOUT, and so are the two never started.
session="$(new_limits session 'h1\tapp.txt\tok\thang1\tapp\nh2\tapp.txt\tok\thang2\tapp\nh3\tapp.txt\tok\thang3\tapp\n')"
rm -f "$WORK/session-pids"
LIMIT_PIDS="$WORK/session-pids" HARNESS_KIT_REPLAY_JOBS=1 HARNESS_KIT_REPLAY_LIMIT_FLOOR_SECONDS=5 \
  HARNESS_KIT_REPLAY_BASELINE_FALLBACK_SECONDS=5 HARNESS_KIT_REPLAY_SESSION_SECONDS=2 run_guarded "$session"
left="$(alive "$WORK/session-pids")"
if [ "$GUARDED" = yes ] && [ "$STATUS" = 1 ] && [ -z "$left" ] &&
  grep -q '^TIMEOUT h1: still running when the session.s limit of 2 seconds ran out; stopped after [0-9.]* seconds$' <<<"$OUT" &&
  grep -qx "TIMEOUT h2: not started before the session's limit of 2 seconds ran out" <<<"$OUT" &&
  grep -qx "TIMEOUT h3: not started before the session's limit of 2 seconds ran out" <<<"$OUT" &&
  grep -qx 'replay-faults: 3 replayed: 0 KILLED, 0 SURVIVED, 3 TIMEOUT, 0 ERROR' <<<"$OUT" && clean "$session"; then
  result "replay-faults: when the session's limit runs out, every run still going and every entry not started is TIMEOUT" yes ""
else
  result "replay-faults: when the session's limit runs out, every run still going and every entry not started is TIMEOUT" no "$(describe)
ended within the guard: $GUARDED; hung checks still running:${left:- none}"
fi

# T4. A baseline that passes its limit (the 1-second fallback; every run hangs here) stops
# the session at once: every other run is stopped, the exit status is 2, no verdict is
# printed and nothing goes to the event log.
# A fresh project, so that no baseline is recorded and the fallback is the baseline's limit.
stuck="$(new_limits stuck 'h1\tapp.txt\tok\thang1\tapp\nh2\tapp.txt\tok\thang2\tapp\n')"
touch "$stuck/hang-always"
rm -f "$WORK/baseline-pids"
LIMIT_PIDS="$WORK/baseline-pids" HARNESS_KIT_REPLAY_CPUS=2 HARNESS_KIT_REPLAY_LIMIT_MULTIPLE=3 HARNESS_KIT_REPLAY_LIMIT_FLOOR_SECONDS=1 \
  HARNESS_KIT_REPLAY_BASELINE_FALLBACK_SECONDS=1 run_guarded "$stuck"
rm -f "$stuck/hang-always"
left="$(alive "$WORK/baseline-pids")"
if [ "$GUARDED" = yes ] && [ "$STATUS" = 2 ] && [ -z "$left" ] && [ "$(wc -l <"$WORK/baseline-pids" | tr -d ' ')" = 2 ] &&
  grep -q 'the check without any fault ran longer than its limit of 1 seconds, so no verdict can be read; every other run was stopped' <<<"$ERR" &&
  ! grep -q 'replayed:' <<<"$OUT" && [ ! -e "$stuck/.git/harness-kit/events.tsv" ] && clean "$stuck"; then
  result "replay-faults: a baseline that passes its limit stops the session with exit 2 and no verdicts" yes ""
else
  result "replay-faults: a baseline that passes its limit stops the session with exit 2 and no verdicts" no "$(describe)
ended within the guard: $GUARDED; hung checks still running:${left:- none}"
fi

# C1. The pipe controller never blocks on a write: in this file, the one write to a
# go-pipe is release_run's, in the background.
writes="$(grep -nE '>[[:space:]]*"?\$[^ ]*/go\.' "$ROOT/tests/replay-faults.test.sh")"
if [ "$(wc -l <<<"$writes" | tr -d ' ')" = 1 ] && grep -qE '^[0-9]+:  \(echo go >"\$1/go\.\$2"\) &$' <<<"$writes"; then
  result "replay-faults.test.sh: the pipe controller never blocks on a write" yes ""
else
  result "replay-faults.test.sh: the pipe controller never blocks on a write" no "writes to a go-pipe:
$writes"
fi

# ---------------------------------------------------------------------------------------
# tests/validate.sh --only
# ---------------------------------------------------------------------------------------

# V1. validate.sh --only NAME, in a copy with two fake test files: it runs only the test
# file .harness/check-files lists for NAME (not the check's other files, which are not
# tests), and exits with its status; for a name with no test file there, it says so and
# runs the whole check.
vonly="$WORK/vonly"
mkdir -p "$vonly/tests" "$vonly/.harness"
cp "$ROOT/tests/validate.sh" "$vonly/tests/validate.sh"
printf 'echo ran-a >>"$VONLY_LOG"; echo "PASS case a"\n' >"$vonly/tests/a.test.sh"
printf 'echo ran-b >>"$VONLY_LOG"; echo "PASS case b"\n' >"$vonly/tests/b.test.sh"
printf '# check<TAB>path\ncase a\ttests/a.test.sh\ncase a\tsrc/a.sh\ncase b\ttests/b.test.sh\ncase z\tsrc/z.sh\n' >"$vonly/.harness/check-files"
VONLY_LOG="$WORK/vonly-a.log" run_in "$vonly" bash tests/validate.sh --skip-reviewed --only "case a"
a_out="$OUT" a_status=$STATUS
VONLY_LOG="$WORK/vonly-z.log" run_in "$vonly" bash tests/validate.sh --skip-reviewed --only "case z"
if [ "$a_status" -eq 0 ] && [ "$a_out" = "PASS case a" ] && [ "$(cat "$WORK/vonly-a.log" 2>/dev/null)" = ran-a ] &&
  [ "$STATUS" -ne 0 ] && grep -q 'lists no test file for "case z", so the whole check runs' <<<"$ERR" &&
  grep -q '^FAIL tests/stop-gate.test.sh (all cases)' <<<"$OUT" && [ ! -e "$WORK/vonly-z.log" ]; then
  result "validate.sh --only NAME runs only the test file .harness/check-files names for it; a name with none runs the whole check" yes ""
else
  result "validate.sh --only NAME runs only the test file .harness/check-files names for it; a name with none runs the whole check" no "case a: exit $a_status
$a_out
ran: $(cat "$WORK/vonly-a.log" 2>/dev/null)
case z: $(describe)"
fi

# ---------------------------------------------------------------------------------------
# land.sh
# ---------------------------------------------------------------------------------------

# new_land NAME: a project with two entries, m-greet (check greeting) and m-other (check
# other), and .harness/check-files mapping each check to its script. Prints its path.
new_land() {
  local dir
  dir="$(new_project "$1" "${M_KILLED//m-killed/m-greet}$M_OTHER")"
  printf '# check<TAB>file\ngreeting\tchecks/greeting.sh\nother\tchecks/other.sh\n' >"$dir/.harness/check-files"
  printf 'notes\n' >"$dir/README"
  git -C "$dir" add -A && git -C "$dir" commit -q -m "check-files"
  echo "$dir"
}

# make_patch DIR NAME FILE CONTENT: NAME.patch changes FILE to CONTENT; DIR is left clean.
make_patch() {
  printf '%s\n' "$4" >"$1/$3"
  git -C "$1" diff >"$WORK/$2.patch"
  git -C "$1" checkout -q -- "$3"
}

# 8. A patch that changes greeting's check file: only greeting's entry is replayed.
dir="$(new_land land-greet)"
make_patch "$dir" land-greet checks/greeting.sh \
  'if [ "$(sh app.sh)" = hello ]; then echo "PASS  greeting"; else echo "FAIL  greeting  (exit 1)"; exit 1; fi # reworded'
run_in "$dir" bash "$LAND" "$WORK/land-greet.patch"
if [ "$STATUS" -eq 0 ] && grep -q 'so replaying: m-greet $' <<<"$ERR" && grep -q '^KILLED m-greet' <<<"$OUT" &&
  ! grep -q 'm-other' <<<"$OUT$ERR" && grep -qx 'replay-faults: 1 replayed: 1 KILLED, 0 SURVIVED, 0 TIMEOUT, 0 ERROR' <<<"$OUT" &&
  grep -q 'LANDED' <<<"$ERR" && clean "$dir"; then
  result "land.sh: a patch to one check's file replays only that check's entries" yes ""
else
  result "land.sh: a patch to one check's file replays only that check's entries" no "$(describe)"
fi

# 9. A patch that changes no entry's file and no check file: "no replays needed", nothing replayed.
dir="$(new_land land-none)"
make_patch "$dir" land-none README 'more notes'
run_in "$dir" bash "$LAND" "$WORK/land-none.patch"
if [ "$STATUS" -eq 0 ] && grep -q 'no replays needed' <<<"$ERR" && ! grep -q 'replayed:' <<<"$OUT" &&
  [ -z "$(find "$TMPDIR" -maxdepth 1 -newer "$WORK/land-none.patch" -name 'harness-kit-replay.*' -print)" ] &&
  grep -q 'LANDED' <<<"$ERR"; then
  result "land.sh: a patch that changes no entry's file or check file prints \"no replays needed\" and replays nothing" yes ""
else
  result "land.sh: a patch that changes no entry's file or check file prints \"no replays needed\" and replays nothing" no "$(describe)"
fi

# 10. A patch that weakens greeting's check: the check still passes, but the replay
# SURVIVES, so land.sh stops with the patch applied and nothing committed.
dir="$(new_land land-weak)"
head_before="$(git -C "$dir" rev-parse HEAD)"
make_patch "$dir" land-weak checks/greeting.sh 'echo "PASS  greeting"'
run_in "$dir" bash "$LAND" "$WORK/land-weak.patch"
if [ "$STATUS" -eq 1 ] && grep -q '^SURVIVED m-greet' <<<"$OUT" && grep -q 'STOPPED: a fault replay did not pass' <<<"$ERR" &&
  ! grep -q LANDED <<<"$ERR" && [ "$(git -C "$dir" status --porcelain)" = " M checks/greeting.sh" ] &&
  [ "$(git -C "$dir" rev-parse HEAD)" = "$head_before" ] && clean "$dir"; then
  result "land.sh: a patch that weakens a check stops on its SURVIVED replay" yes ""
else
  result "land.sh: a patch that weakens a check stops on its SURVIVED replay" no "$(describe)"
fi

# 11. A patch that changes an entry's own file (the code its fault goes into) replays that
# entry, even though no check file changed.
dir="$(new_land land-code)"
make_patch "$dir" land-code app.sh "$(printf '# the greeting, reworded\necho hello')"
run_in "$dir" bash "$LAND" "$WORK/land-code.patch"
if [ "$STATUS" -eq 0 ] && grep -q 'so replaying: m-greet $' <<<"$ERR" && grep -q '^KILLED m-greet' <<<"$OUT" &&
  ! grep -q 'm-other' <<<"$OUT$ERR" && grep -q 'LANDED' <<<"$ERR" && clean "$dir"; then
  result "land.sh: a patch to an entry's own file replays that entry" yes ""
else
  result "land.sh: a patch to an entry's own file replays that entry" no "$(describe)"
fi

# 12. A patch that rewrites the text an entry finds: the check passes, but the replay is an
# ERROR, so land.sh stops with the patch applied.
dir="$(new_land land-moved)"
make_patch "$dir" land-moved app.sh "$(printf '# the greeting\necho  hello')"
run_in "$dir" bash "$LAND" "$WORK/land-moved.patch"
if [ "$STATUS" -eq 1 ] && grep -q '^ERROR m-greet: the text to find is not in app.sh$' <<<"$OUT" &&
  grep -q 'STOPPED: a fault replay did not pass' <<<"$ERR" && ! grep -q LANDED <<<"$ERR" &&
  [ "$(git -C "$dir" status --porcelain)" = " M app.sh" ] && clean "$dir"; then
  result "land.sh: a patch that moves an entry's text stops on its ERROR replay" yes ""
else
  result "land.sh: a patch that moves an entry's text stops on its ERROR replay" no "$(describe)"
fi

# 13. A patch that adds an entry to .harness/mutations.tsv, or changes one, replays it, even
# though it touches no entry's file or check file; an unchanged entry is not replayed.
dir="$(new_land land-entry)"
printf 'm-new\tother.txt\tcontent\tgone\tother\n' >>"$dir/.harness/mutations.tsv"
git -C "$dir" diff >"$WORK/land-entry.patch"
git -C "$dir" checkout -q -- .harness/mutations.tsv
run_in "$dir" bash "$LAND" "$WORK/land-entry.patch"
added="$(describe)"
added_ok=no
if [ "$STATUS" -eq 0 ] && grep -q 'so replaying: m-new $' <<<"$ERR" && grep -q '^KILLED m-new' <<<"$OUT" &&
  ! grep -q 'm-greet\|m-other' <<<"$OUT" && grep -q LANDED <<<"$ERR"; then
  added_ok=yes
fi
git -C "$dir" commit -q -am "add m-new"
awk -F'\t' -v OFS='\t' '$1 == "m-new" { $4 = "different" } { print }' "$dir/.harness/mutations.tsv" >"$WORK/m.tsv" &&
  cat "$WORK/m.tsv" >"$dir/.harness/mutations.tsv"
git -C "$dir" diff >"$WORK/land-entry2.patch"
git -C "$dir" checkout -q -- .harness/mutations.tsv
run_in "$dir" bash "$LAND" "$WORK/land-entry2.patch"
if [ "$added_ok" = yes ] && [ "$STATUS" -eq 0 ] && grep -q 'so replaying: m-new $' <<<"$ERR" &&
  grep -q '^KILLED m-new' <<<"$OUT" && clean "$dir"; then
  result "land.sh: a patch that adds or changes a mutations.tsv entry replays that entry" yes ""
else
  result "land.sh: a patch that adds or changes a mutations.tsv entry replays that entry" no "added: $added
changed: $(describe)"
fi

[ "$failures" -eq 0 ]
