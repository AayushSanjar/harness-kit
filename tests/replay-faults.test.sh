#!/usr/bin/env bash
# Tests for replay-faults.sh (with replay-faults.mjs) and land.sh's fault replays.
#
# Every case runs in a temporary git repository whose "check" is a small fake: check.sh
# runs checks/greeting.sh (PASS when app.sh prints hello) and checks/other.sh (PASS when
# other.txt says content, after sleeping $REPLAY_SLEEP seconds if set), one PASS or FAIL
# line each; with --only NAME it runs only that one. Nothing touches GitHub and no API
# call is made. Prints one PASS or FAIL line per case and exits non-zero if any fail.
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
unset HARNESS_KIT_EVAL CLAUDE_PROJECT_DIR HARNESS_KIT_REPLAY

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
[ -z "${REPLAY_MARK:-}" ] || ! grep -q slow app.sh || { touch "$REPLAY_MARK"; sleep 3; }
status=0
[ -n "$only" ] && [ "$only" != greeting ] || sh checks/greeting.sh || status=1
[ -n "$only" ] && [ "$only" != other ] || { [ -z "${REPLAY_SLEEP:-}" ] || sleep "$REPLAY_SLEEP"; sh checks/other.sh; } || status=1
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
M_SLOW='m-slow\tapp.sh\techo hello\techo slow\tgreeting\n'
dir="$(new_project replay "$M_KILLED$M_SURVIVED$M_ERROR$M_TWICE$M_OTHER$M_WRONG$M_SLOW")"

# ---------------------------------------------------------------------------------------
# replay-faults.sh
# ---------------------------------------------------------------------------------------

# 1. KILLED: the check catches the fault; exit 0, and the project itself is untouched.
# Every check run (the baseline and the entry's) has HARNESS_KIT_REPLAY=1, which
# check-commits.mjs needs to exempt the snapshot commit.
REPLAY_ENV_LOG="$WORK/replay-env" run_in "$dir" bash "$REPLAY" m-killed
if [ "$STATUS" -eq 0 ] && grep -q '^KILLED m-killed: "greeting" failed with the fault in app.sh$' <<<"$OUT" &&
  [ "$(cat "$WORK/replay-env" 2>/dev/null)" = "$(printf 'HARNESS_KIT_REPLAY=1\nHARNESS_KIT_REPLAY=1')" ] &&
  grep -qx 'replay-faults: 1 replayed: 1 KILLED, 0 SURVIVED, 0 ERROR' <<<"$OUT" &&
  grep -q 'echo hello' "$dir/app.sh" && [ -z "$(git -C "$dir" status --porcelain)" ] && clean "$dir"; then
  result "replay-faults: a fault its check catches is KILLED, exit 0, the project untouched" yes ""
else
  result "replay-faults: a fault its check catches is KILLED, exit 0, the project untouched" no "$(describe)
check environment: $(cat "$WORK/replay-env" 2>/dev/null)"
fi

# 2. SURVIVED: a change the check does not notice; exit 1.
run_in "$dir" bash "$REPLAY" m-survived
if [ "$STATUS" -eq 1 ] && grep -q '^SURVIVED m-survived: "greeting" did not fail with the fault in place' <<<"$OUT" &&
  grep -qx 'replay-faults: 1 replayed: 0 KILLED, 1 SURVIVED, 0 ERROR' <<<"$OUT" && clean "$dir"; then
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
  grep -qx 'replay-faults: 3 replayed: 1 KILLED, 0 SURVIVED, 2 ERROR' <<<"$OUT" && clean "$dir"; then
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

# 6. Cleanup on interruption: killed while the check runs with the fault in place, it
# removes the worktree and exits 143.
mark="$WORK/slow-started"
(cd "$dir" && REPLAY_MARK="$mark" exec bash "$REPLAY" m-slow >"$WORK/slow.out" 2>"$WORK/slow.err") &
pid=$!
waited=0
while [ ! -e "$mark" ] && [ "$waited" -lt 300 ]; do sleep 0.1; waited=$((waited + 1)); done
worktrees_during="$(git -C "$dir" worktree list --porcelain | grep -c '^worktree ')"
kill -TERM "$pid" 2>/dev/null
wait "$pid"
STATUS=$? OUT="$(cat "$WORK/slow.out")" ERR="$(cat "$WORK/slow.err")"
if [ -e "$mark" ] && [ "$worktrees_during" -eq 2 ] && [ "$STATUS" -eq 143 ] &&
  grep -q 'interrupted; the worktree was removed' <<<"$ERR" && clean "$dir" && grep -q 'echo hello' "$dir/app.sh"; then
  result "replay-faults: interrupted mid-check, it still removes the worktree" yes ""
else
  result "replay-faults: interrupted mid-check, it still removes the worktree" no "$(describe)
worktrees while the check ran: $worktrees_during"
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
# line with its counts and the ids asked for; the interrupted run and the refusals left
# none. A run of every entry says "all".
run_in "$dir" bash "$REPLAY"
got="$(cut -f2,5-7 "$dir/.git/harness-kit/events.tsv" 2>/dev/null)"
want="$(printf '%s\tREPLAYED\t%s\t%s\n' \
  replay-faults.sh killed=1,survived=0,error=0 "ids: m-killed" \
  replay-faults.sh killed=0,survived=1,error=0 "ids: m-survived" \
  replay-faults.sh killed=1,survived=0,error=2 "ids: m-error m-twice m-killed" \
  replay-faults.sh killed=0,survived=0,error=2 "ids: m-wrong m-other" \
  replay-faults.sh killed=0,survived=1,error=0 "ids: m-killed" \
  replay-faults.sh killed=3,survived=1,error=3 all)"
if [ "$STATUS" -eq 1 ] && grep -qx 'replay-faults: 7 replayed: 3 KILLED, 1 SURVIVED, 3 ERROR' <<<"$OUT" && [ "$got" = "$want" ] &&
  [ -z "$(git -C "$dir" status --porcelain)" ] && clean "$dir"; then
  result "replay-faults: each finished run's counts go to .git/harness-kit/events.tsv; refused and interrupted runs add none" yes ""
else
  result "replay-faults: each finished run's counts go to .git/harness-kit/events.tsv; refused and interrupted runs add none" no "$(describe)
log:
$got
wanted:
$want"
fi

# 7c. A fragile entry, whose text to find holds a version or a date, is an ERROR and is not
# replayed; the other entries still run.
frag="$(new_project fragile "${M_KILLED}m-version\tapp.sh\t# the greeting, v1.2.3\t#\tgreeting\nm-date\tapp.sh\t# 2026-09-27 the greeting\t#\tgreeting\n")"
run_in "$frag" bash "$REPLAY"
if [ "$STATUS" -eq 1 ] && grep -q '^ERROR m-version: fragile entry: its text to find holds the version "v1.2.3"' <<<"$OUT" &&
  grep -q '^ERROR m-date: fragile entry: its text to find holds the date "2026-09-27"' <<<"$OUT" &&
  grep -q '^KILLED m-killed' <<<"$OUT" && ! grep -q 'replaying m-version\|replaying m-date' <<<"$ERR" &&
  grep -qx 'replay-faults: 3 replayed: 1 KILLED, 0 SURVIVED, 2 ERROR' <<<"$OUT" && clean "$frag"; then
  result "replay-faults: an entry whose find text holds a version or a date is an ERROR, fragile entry" yes ""
else
  result "replay-faults: an entry whose find text holds a version or a date is an ERROR, fragile entry" no "$(describe)"
fi

# 7d. With .harness/check-only, each entry runs "<check command> --only <check>": the same
# verdicts, with only the entry's check in its run, and faster, as "other" is slow (1 s)
# and only m-other's run needs it. Both ways are timed.
only="$(new_project only "$M_KILLED$M_OTHER")"
now_ms() { node -p 'Date.now()'; }
start=$(now_ms)
REPLAY_SLEEP=1 run_in "$only" bash "$REPLAY"
whole_ms=$(($(now_ms) - start)) whole_out="$OUT" whole_status=$STATUS
touch "$only/.harness/check-only"
start=$(now_ms)
REPLAY_SLEEP=1 run_in "$only" bash "$REPLAY"
only_ms=$(($(now_ms) - start))
results="$(sed -n 's/.*each run.s output is in \(.*\) (baseline.log.*/\1/p' <<<"$ERR")"
rm -f "$only/.harness/check-only"
if [ "$whole_status" -eq 0 ] && [ "$STATUS" -eq 0 ] && [ "$OUT" = "$whole_out" ] &&
  grep -qx 'replay-faults: 2 replayed: 2 KILLED, 0 SURVIVED, 0 ERROR' <<<"$OUT" &&
  grep -q "each entry runs only its own check (.harness/check-only): sh check.sh --skip-reviewed --only <check>" <<<"$ERR" &&
  grep -q 'greeting' "$results/m-killed.log" && ! grep -q 'other' "$results/m-killed.log" &&
  grep -q 'other' "$results/m-other.log" && ! grep -q 'greeting' "$results/m-other.log" &&
  grep -q 'greeting' "$results/baseline.log" && grep -q 'other' "$results/baseline.log" &&
  [ "$only_ms" -lt $((whole_ms - 500)) ] && clean "$only"; then
  result "replay-faults: with .harness/check-only each entry runs only its check: same verdicts, faster" yes ""
else
  result "replay-faults: with .harness/check-only each entry runs only its check: same verdicts, faster" no "whole: exit $whole_status, ${whole_ms} ms
$whole_out
--only: ${only_ms} ms
$(describe)"
fi
echo "    timing (2 entries, check \"other\" sleeps 1 s): whole command ${whole_ms} ms, --only ${only_ms} ms"

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
  ! grep -q 'm-other' <<<"$OUT$ERR" && grep -qx 'replay-faults: 1 replayed: 1 KILLED, 0 SURVIVED, 0 ERROR' <<<"$OUT" &&
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
