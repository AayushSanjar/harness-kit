#!/usr/bin/env bash
# Tests for plugins/harness-kit/scripts/stop-gate.mjs. Each case runs the hook
# against a temporary project folder with fake hook input and a fake check
# command. Prints one PASS or FAIL line per case and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/plugins/harness-kit/scripts/stop-gate.mjs"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# The hook keeps its block count in the OS temp folder; point that at WORK so
# runs never see each other's counts.
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"
# The helper's registry follows this test's TMPDIR, not a replay run's own registry.
unset HARNESS_KIT_REGISTRY_DIR
# The gate is off under HARNESS_KIT_EVAL; only case 6 sets it.
unset HARNESS_KIT_EVAL
# The budget and the pass record's age limit are the defaults unless a case sets them.
unset HARNESS_KIT_BUDGET_CHECK_SECONDS HARNESS_KIT_STOP_GATE_PASS_HOURS HARNESS_KIT_LIMIT_CHECK_SECONDS
failures=0

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

# new_project NAME [CHECK_SCRIPT_BODY]: make a project folder. With a body, it
# writes scripts/check.sh and points .harness/check-command at it.
new_project() {
  local dir="$WORK/$1"
  mkdir -p "$dir"
  if [ $# -ge 2 ]; then
    mkdir -p "$dir/.harness" "$dir/scripts"
    printf '#!/bin/sh\n%s\n' "$2" >"$dir/scripts/check.sh"
    chmod +x "$dir/scripts/check.sh"
    printf 'scripts/check.sh\n' >"$dir/.harness/check-command"
  fi
  echo "$dir"
}

# run_gate DIR SESSION STOP_HOOK_ACTIVE [AGENT_TYPE]: run the hook; sets OUT, ERR, STATUS.
run_gate() {
  local input agent=""
  [ $# -ge 4 ] && agent=$(printf ',"agent_type":"%s"' "$4")
  input=$(printf '{"session_id":"%s","hook_event_name":"Stop","cwd":"%s","stop_hook_active":%s%s}' "$2" "$1" "$3" "$agent")
  OUT="$(CLAUDE_PROJECT_DIR="$1" node "$GATE" <<<"$input" 2>"$WORK/stderr")"
  STATUS=$?
  ERR="$(cat "$WORK/stderr")"
}

is_block() { grep -q '"decision":"block"' <<<"$1"; }
describe() { printf 'exit %s\nstdout: %s\nstderr: %s' "$STATUS" "$OUT" "$ERR"; }

# 1. No config file: exit 0, one stderr line, no decision.
dir="$(new_project no-config)"
run_gate "$dir" s-none false
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] &&
  [ "$ERR" = "harness-kit: no .harness/check-command, so the stop gate is off" ]; then
  result "no .harness/check-command: exit 0, gate off" yes ""
else
  result "no .harness/check-command: exit 0, gate off" no "$(describe)"
fi

# 2. Passing command: exit 0 silently.
dir="$(new_project passing 'echo "PASS everything"; exit 0')"
run_gate "$dir" s-pass false
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
  result "passing check: exit 0 silently" yes ""
else
  result "passing check: exit 0 silently" no "$(describe)"
fi

# 3. Failing command: block, with the FAIL line and the instruction in the reason.
dir="$(new_project failing 'echo "PASS lint"; echo "FAIL unit tests: 2 failed"; exit 1')"
run_gate "$dir" s-fail false
reason="$(node -e 'try { console.log(JSON.parse(process.argv[1]).reason) } catch {}' "$OUT")"
if [ "$STATUS" -eq 0 ] && is_block "$OUT" &&
  grep -q '^FAIL unit tests: 2 failed$' <<<"$reason" &&
  ! grep -q 'PASS lint' <<<"$reason" &&
  grep -q 'Fix the failing checks before finishing. Do not edit protected files' <<<"$reason"; then
  result "failing check: blocks with the FAIL line as feedback" yes ""
else
  result "failing check: blocks with the FAIL line as feedback" no "$(describe)"
fi

# 4. Four failures in a row in one session: blocks 1-3, the 4th allows and
# tells the person. Calls 2-4 are continuations, as Claude Code marks them.
dir="$(new_project budget 'echo "FAIL still broken"; exit 1')"
log=""
ok=yes
for i in 1 2 3 4; do
  active=true
  [ "$i" -eq 1 ] && active=false
  run_gate "$dir" s-budget "$active"
  log="$log"$'\n'"call $i: $(describe)"
  if [ "$i" -le 3 ]; then
    is_block "$OUT" || ok=no
  else
    budget="harness-kit: checks still failing after 3 attempts — the person must look"
    if is_block "$OUT" || [ "$STATUS" -ne 0 ] ||
      ! grep -qF "\"systemMessage\":\"$budget\"" <<<"$OUT"; then
      ok=no
    fi
  fi
done
result "4 failures in a row: 4th allows the stop and prints the budget line" "$ok" "$log"

# 5. Pass after fail resets the count: 3 blocks, a pass, then a failing
# continuation blocks again instead of hitting the budget.
dir="$(new_project reset 'echo "FAIL broken"; exit 1')"
log=""
ok=yes
for i in 1 2 3; do
  active=true
  [ "$i" -eq 1 ] && active=false
  run_gate "$dir" s-reset "$active"
  log="$log"$'\n'"fail $i: $(describe)"
  is_block "$OUT" || ok=no
done
printf '#!/bin/sh\nexit 0\n' >"$dir/scripts/check.sh"
run_gate "$dir" s-reset true
log="$log"$'\n'"pass: $(describe)"
{ [ "$STATUS" -eq 0 ] && [ -z "$OUT" ]; } || ok=no
printf '#!/bin/sh\necho "FAIL broken again"\nexit 1\n' >"$dir/scripts/check.sh"
run_gate "$dir" s-reset true
log="$log"$'\n'"fail after pass: $(describe)"
{ is_block "$OUT" && grep -q 'block 1 of 3' <<<"$OUT"; } || ok=no
result "pass after fail resets the count" "$ok" "$log"

# 6. Under HARNESS_KIT_EVAL=1 (a reviewer evaluation) a failing check does not block: the
# stop is allowed silently and the check does not even run. The same project without the
# variable still blocks.
dir="$(new_project eval-mode "touch \"$WORK/eval-mode.ran\"; echo \"FAIL broken\"; exit 1")"
HARNESS_KIT_EVAL=1 run_gate "$dir" s-eval false
eval_log="with HARNESS_KIT_EVAL=1: $(describe)"
ok=no
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ] && [ ! -e "$WORK/eval-mode.ran" ]; then
  run_gate "$dir" s-eval false
  if is_block "$OUT" && [ -e "$WORK/eval-mode.ran" ]; then ok=yes; fi
fi
result "HARNESS_KIT_EVAL=1: the stop is allowed silently; without it the same failure blocks" "$ok" "$eval_log
without it: $(describe)"

# 7. The reviewer (agent_type harness-kit:reviewer, as `claude --agent` reports it): a
# failing check does not block; the stop is allowed silently and the check does not run.
dir="$(new_project reviewer "touch \"$WORK/reviewer.ran\"; echo \"FAIL broken\"; exit 1")"
run_gate "$dir" s-reviewer false harness-kit:reviewer
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ] && [ ! -e "$WORK/reviewer.ran" ]; then
  result "agent_type harness-kit:reviewer: the stop is allowed silently and the check is not run" yes ""
else
  result "agent_type harness-kit:reviewer: the stop is allowed silently and the check is not run" no "$(describe)"
fi

# 8. Any other agent: the same failing check still blocks.
run_gate "$dir" s-other-agent false Explore
if [ "$STATUS" -eq 0 ] && is_block "$OUT" && [ -e "$WORK/reviewer.ran" ]; then
  result "agent_type Explore: the same failing check still blocks" yes ""
else
  result "agent_type Explore: the same failing check still blocks" no "$(describe)"
fi

# THE EVENT LOG. Cases 9-11 run in git repositories (new_git_project), where the hook
# records its check results in .git/harness-kit/events.tsv through events.sh.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

# new_git_project NAME CHECK_SCRIPT_BODY: new_project, as a git repository on "feat" with
# one commit.
new_git_project() {
  local dir
  dir="$(new_project "$1" "$2")"
  git init -q -b feat "$dir"
  git -C "$dir" add -A && git -C "$dir" commit -q -m initial
  echo "$dir"
}
# set_check DIR BODY: replace DIR's check script.
set_check() { printf '#!/bin/sh\n%s\n' "$2" >"$1/scripts/check.sh"; }
# checked DIR: DIR's CHECKED lines as "tool branch event what detail" lines.
checked() { awk -F'\t' '$5 == "CHECKED"' "$1/.git/harness-kit/events.tsv" 2>/dev/null | cut -f2,3,5-; }
# timed DIR: DIR's TIMED lines as "what detail" lines.
timed() { awk -F'\t' '$5 == "TIMED"' "$1/.git/harness-kit/events.tsv" 2>/dev/null | cut -f6,7; }

# 9. A failing check is recorded as FAIL with its FAIL lines' names (not its PASS lines), a
# passing one as PASS, on the branch, with HEAD.
dir="$(new_git_project records 'echo "PASS lint"; echo "FAIL unit tests: 2 failed"; echo "  FAIL e2e (exit 1)"; exit 1')"
run_gate "$dir" s-records false
first="$(describe)"
set_check "$dir" 'echo "PASS everything"; exit 0'
run_gate "$dir" s-records true
want="$(printf 'stop-gate.mjs\tfeat\tCHECKED\tFAIL\texit 1: unit tests: 2 failed; e2e (exit 1)\nstop-gate.mjs\tfeat\tCHECKED\tPASS\t-')"
if [ "$(checked "$dir")" = "$want" ] && [ "$(cut -f4 "$dir/.git/harness-kit/events.tsv" | sort -u)" = "$(git -C "$dir" rev-parse HEAD)" ] &&
  [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
  result "stop-gate: records a check in the event log: FAIL with the failing checks' names, or PASS" yes ""
else
  result "stop-gate: records a check in the event log: FAIL with the failing checks' names, or PASS" no "log:
$(checked "$dir")
first run: $first
second run: $(describe)"
fi

# 10. Only a changed result is recorded: the same failing set again (in another order, with
# another exit status) adds nothing; a different set, PASS after FAIL and FAIL after PASS
# each add one; PASS again adds nothing.
dir="$(new_git_project changes 'echo "FAIL a"; echo "FAIL b"; exit 1')"
run_gate "$dir" s-changes false
set_check "$dir" 'echo "FAIL b"; echo "FAIL a"; exit 2'
run_gate "$dir" s-changes false
set_check "$dir" 'echo "FAIL a"; exit 1'
run_gate "$dir" s-changes false
set_check "$dir" 'exit 0'
run_gate "$dir" s-changes false
run_gate "$dir" s-changes false
set_check "$dir" 'echo "FAIL a"; exit 1'
run_gate "$dir" s-changes false
want="$(printf '%s\n' "FAIL	exit 1: a; b" "FAIL	exit 1: a" "PASS	-" "FAIL	exit 1: a")"
if [ "$(checked "$dir" | cut -f4,5)" = "$want" ]; then
  result "stop-gate: records only a changed result: the same result again adds no line; PASS after FAIL, FAIL after PASS, or a different set of failing checks adds one" yes ""
else
  result "stop-gate: records only a changed result: the same result again adds no line; PASS after FAIL, FAIL after PASS, or a different set of failing checks adds one" no \
    "log:
$(checked "$dir")"
fi

# 11. A log that cannot be written (.git/harness-kit is a file) changes nothing but a note:
# the same block, with the same reason. With HARNESS_KIT_EVAL, or for the reviewer, the
# gate is off and nothing is recorded.
dir="$(new_git_project no-log 'echo "FAIL broken"; exit 1')"
: >"$dir/.git/harness-kit"
run_gate "$dir" s-no-log false
reason="$(node -e 'try { console.log(JSON.parse(process.argv[1]).reason) } catch {}' "$OUT")"
no_log="$(describe)"
no_log_ok=no
if [ "$STATUS" -eq 0 ] && is_block "$OUT" && grep -q '^FAIL broken$' <<<"$reason" && grep -q 'block 1 of 3' <<<"$reason" &&
  grep -q '^harness-kit stop-gate.mjs: note: could not append to .*/no-log/.git/harness-kit/events.tsv$' <<<"$ERR"; then
  no_log_ok=yes
fi
off="$(new_git_project off 'echo "FAIL broken"; exit 1')"
HARNESS_KIT_EVAL=1 run_gate "$off" s-off false
run_gate "$off" s-off-reviewer false harness-kit:reviewer
if [ "$no_log_ok" = yes ] && [ ! -e "$off/.git/harness-kit/events.tsv" ]; then
  result "stop-gate: a failed recording does not change the decision; the reviewer and HARNESS_KIT_EVAL record nothing" yes ""
else
  result "stop-gate: a failed recording does not change the decision; the reviewer and HARNESS_KIT_EVAL record nothing" no \
    "unwritable log: $no_log
off: $(checked "$off")"
fi

# 12. IT FAILS CLOSED ON TIME. A check that hangs (and ignores SIGTERM, with a child in its
# group) is stopped at its limit, 1 second here with a 1-second grace period, and the stop
# is BLOCKED with the TIMEOUT message, counted as block 1 of 3; it is recorded as a FAIL with
# "timeout 1s", and nothing of its process group is left.
dir="$(new_git_project hangs "echo \"PASS lint\"; trap '' TERM; sleep 30 & echo \$! >\"$WORK/hangs.child\"; echo \$\$ >\"$WORK/hangs.pid\"; wait")"
began=$SECONDS
HARNESS_KIT_LIMIT_CHECK_SECONDS=1 HARNESS_KIT_LIMIT_GRACE_SECONDS=1 run_gate "$dir" s-hangs false
took=$((SECONDS - began))
reason="$(node -e 'try { console.log(JSON.parse(process.argv[1]).reason) } catch {}' "$OUT")"
left=""
for f in "$WORK/hangs.child" "$WORK/hangs.pid"; do
  [ -f "$f" ] && kill -0 "$(cat "$f")" 2>/dev/null && left="$left $(cat "$f")"
done
if [ "$STATUS" -eq 0 ] && is_block "$OUT" && [ -z "$left" ] && [ "$took" -le 5 ] &&
  [ "$(head -n 1 <<<"$reason")" = 'harness-kit stop gate: `scripts/check.sh` did not finish within 1 seconds (TIMEOUT); it was stopped. Block 1 of 3.' ] &&
  grep -qx 'Find what hangs or runs slowly and fix it before finishing.' <<<"$reason" &&
  [ "$(checked "$dir" | cut -f4,5)" = "$(printf 'FAIL\ttimeout 1s: no FAIL lines')" ]; then
  result "stop-gate: a check that runs past its limit blocks the stop with TIMEOUT, and its process group is gone" yes ""
else
  result "stop-gate: a check that runs past its limit blocks the stop with TIMEOUT, and its process group is gone" no \
    "$(describe)
took ${took}s; still running:${left:- none}
log: $(checked "$dir")"
fi

# ---------------------------------------------------------------------------------------
# THE SKIP. Each project below is a git repository whose check counts its runs in
# $WORK/<name>.runs, so "ran" and "skipped" are read from the count, never from timing. It
# has a tracked app.txt and a .gitignore for ignored/.
# ---------------------------------------------------------------------------------------
# counted_project NAME BODY [IGNORED]: that project, its check running BODY after counting;
# IGNORED, when given, is one more line for its .gitignore. Prints its path.
counted_project() {
  local name="$1" dir
  dir="$(new_project "$name" "echo run >>\"$WORK/$name.runs\"; $2")"
  printf 'v1\n' >"$dir/app.txt"
  printf 'ignored/\n%s\n' "${3:-}" >"$dir/.gitignore"
  git init -q -b feat "$dir"
  git -C "$dir" add -A && git -C "$dir" commit -q -m initial
  echo "$dir"
}
# runs NAME: how many times NAME's check ran.
runs() { if [ -f "$WORK/$1.runs" ]; then wc -l <"$WORK/$1.runs" | tr -d ' '; else echo 0; fi; }
# pass_record DIR: DIR's pass record.
pass_record() { echo "$1/.git/harness-kit/stop-gate-pass"; }
# edit_record DIR JS: change DIR's pass record with JS, run on the parsed record as r.
edit_record() {
  node -e '
    const fs = require("fs");
    const [file, js] = process.argv.slice(1);
    const r = JSON.parse(fs.readFileSync(file, "utf8"));
    new Function("r", js)(r);
    fs.writeFileSync(file, JSON.stringify(r) + "\n");
  ' "$(pass_record "$1")" "$2"
}
PASSING='echo "PASS everything"; exit 0'

# 13. A pass, then nothing changed: the second stop does not run the check; stderr says so.
dir="$(counted_project skip "$PASSING")"
run_gate "$dir" s-skip false
first="$(describe)"
run_gate "$dir" s-skip false
if [ "$(runs skip)" = 1 ] && [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] && [ -f "$(pass_record "$dir")" ] &&
  grep -qx 'harness-kit stop gate: nothing changed since the check passed at [0-9T:.Z-]*; the check was not run' <<<"$ERR"; then
  result "stop-gate skip: after a pass with nothing changed, the next stop does not run the check" yes ""
else
  result "stop-gate skip: after a pass with nothing changed, the next stop does not run the check" no "runs: $(runs skip)
first: $first
second: $(describe)"
fi

# 14. A pass, then an edit to a tracked file: the check runs.
dir="$(counted_project edit "$PASSING")"
run_gate "$dir" s-edit false
printf 'v2\n' >"$dir/app.txt"
run_gate "$dir" s-edit false
if [ "$(runs edit)" = 2 ]; then
  result "stop-gate skip: an edit to a tracked file runs the check" yes ""
else
  result "stop-gate skip: an edit to a tracked file runs the check" no "runs: $(runs edit)
$(describe)"
fi

# 14b. git's racy-index case, made certain with fixed times: app.txt, its index entry and the
# index itself all have one time, so the entry is "racy" and git must re-read the file. Then
# a same-size edit in place, with app.txt's time set back: only a copy of the index that
# keeps the real index's time sees it. ctime is not trusted, because setting a time changes
# it. A third stop with nothing changed still skips.
# fixed_time FILE: set FILE's time to 1700000000 (November 2023; a time of 0 means unknown to git).
fixed_time() { node -e 'require("fs").utimesSync(process.argv[1], 1700000000, 1700000000)' "$1"; }
dir="$(counted_project racy "$PASSING")"
git -C "$dir" config core.trustctime false
fixed_time "$dir/app.txt"
git -C "$dir" update-index -q --refresh
fixed_time "$dir/.git/index"
run_gate "$dir" s-racy false
first_runs="$(runs racy)"
printf 'v2\n' >"$dir/app.txt"
fixed_time "$dir/app.txt"
run_gate "$dir" s-racy false
edit_runs="$(runs racy)"
second="$(describe)"
run_gate "$dir" s-racy false
if [ "$first_runs" = 1 ] && [ "$edit_runs" = 2 ] && [ "$(runs racy)" = 2 ]; then
  result "stop-gate skip: a same-size edit in the second the index was written runs the check" yes ""
else
  result "stop-gate skip: a same-size edit in the second the index was written runs the check" no "runs after the first stop: $first_runs; after the edit: $edit_runs; after no change: $(runs racy)
second stop: $second"
fi

# 15. A pass, then a new untracked file: the check runs. Then a new ignored file: skipped.
dir="$(counted_project untracked "$PASSING")"
run_gate "$dir" s-untracked false
printf 'new\n' >"$dir/new.txt"
run_gate "$dir" s-untracked false
after_new="$(runs untracked)"
mkdir -p "$dir/ignored" && printf 'x\n' >"$dir/ignored/x.txt"
run_gate "$dir" s-untracked false
if [ "$after_new" = 2 ] && [ "$(runs untracked)" = 2 ]; then
  result "stop-gate skip: a new untracked file runs the check; a new ignored file does not" yes ""
else
  result "stop-gate skip: a new untracked file runs the check; a new ignored file does not" no "runs after the untracked file: $after_new
runs after the ignored file: $(runs untracked)"
fi

# 16. A pass, then another check command: the check runs. The check-command file is ignored
# here, so that only the command field can see the change.
dir="$(counted_project command "$PASSING" .harness/check-command)"
run_gate "$dir" s-command false
printf 'scripts/check.sh --another\n' >"$dir/.harness/check-command"
run_gate "$dir" s-command false
if [ "$(runs command)" = 2 ] && [ -z "$(git -C "$dir" status --porcelain)" ]; then
  result "stop-gate skip: another check command runs the check" yes ""
else
  result "stop-gate skip: another check command runs the check" no "runs: $(runs command)
status: $(git -C "$dir" status --porcelain)"
fi

# 17. A pass, then a new commit with the same tree: the check runs. Then a new branch: the
# check runs.
dir="$(counted_project refs "$PASSING")"
run_gate "$dir" s-refs false
git -C "$dir" commit -q --allow-empty -m empty
run_gate "$dir" s-refs false
after_commit="$(runs refs)"
git -C "$dir" branch other
run_gate "$dir" s-refs false
if [ "$after_commit" = 2 ] && [ "$(runs refs)" = 3 ]; then
  result "stop-gate skip: a new commit, or a new ref, runs the check" yes ""
else
  result "stop-gate skip: a new commit, or a new ref, runs the check" no "runs after the commit: $after_commit
runs after the branch: $(runs refs)"
fi

# 18. A pass, then a copy of the gate whose plugin.json has another version: the check runs.
dir="$(counted_project version "$PASSING")"
run_gate "$dir" s-version false
mkdir -p "$WORK/other-plugin/.claude-plugin"
cp -R "$ROOT/plugins/harness-kit/scripts" "$WORK/other-plugin/scripts"
printf '{ "name": "harness-kit", "version": "99.0.0" }\n' >"$WORK/other-plugin/.claude-plugin/plugin.json"
real_gate="$GATE"
GATE="$WORK/other-plugin/scripts/stop-gate.mjs"
run_gate "$dir" s-version false
GATE="$real_gate"
if [ "$(runs version)" = 2 ]; then
  result "stop-gate skip: another plugin version runs the check" yes ""
else
  result "stop-gate skip: another plugin version runs the check" no "runs: $(runs version)
$(describe)"
fi

# 19. A failing check, then nothing changed: the check runs again and blocks again, and no
# pass record is left.
dir="$(counted_project failing-twice 'echo "FAIL unit"; exit 1')"
run_gate "$dir" s-failing-twice false
first="$(describe)"
run_gate "$dir" s-failing-twice true
if [ "$(runs failing-twice)" = 2 ] && is_block "$OUT" && grep -q 'block 2 of 3' <<<"$OUT" && [ ! -e "$(pass_record "$dir")" ]; then
  result "stop-gate skip: a failing check leaves no pass record; the next stop runs it again" yes ""
else
  result "stop-gate skip: a failing check leaves no pass record; the next stop runs it again" no "runs: $(runs failing-twice)
first: $first
second: $(describe)"
fi

# 20. A check stopped at its limit leaves no pass record, even one that exits 0 when stopped:
# while $WORK/timeout.hang exists, the check hangs and exits 0 on SIGTERM. The next stop, with
# nothing changed but the hang gone, runs the check. Both stops use the same 1-second limit,
# as the limit is a field.
dir="$(counted_project timeout "if [ -e \"$WORK/timeout.hang\" ]; then trap 'exit 0' TERM; echo \"PASS lint\"; sleep 30 & wait; fi; $PASSING")"
printf 'exec scripts/check.sh\n' >"$dir/.harness/check-command"
git -C "$dir" commit -q -am "exec the check"
: >"$WORK/timeout.hang"
HARNESS_KIT_LIMIT_CHECK_SECONDS=1 HARNESS_KIT_LIMIT_GRACE_SECONDS=1 run_gate "$dir" s-timeout false
first="$(describe)"
first_block=no
is_block "$OUT" && grep -q 'TIMEOUT' <<<"$OUT" && first_block=yes
record_after_timeout=no
[ -e "$(pass_record "$dir")" ] && record_after_timeout=yes
rm -f "$WORK/timeout.hang"
HARNESS_KIT_LIMIT_CHECK_SECONDS=1 HARNESS_KIT_LIMIT_GRACE_SECONDS=1 run_gate "$dir" s-timeout true
if [ "$first_block" = yes ] && [ "$record_after_timeout" = no ] && [ "$(runs timeout)" = 2 ] && [ -z "$OUT" ]; then
  result "stop-gate skip: a check stopped at its limit leaves no pass record, even when it exits 0; the next stop runs it" yes ""
else
  result "stop-gate skip: a check stopped at its limit leaves no pass record, even when it exits 0; the next stop runs it" no "runs: $(runs timeout); record after the timeout: $record_after_timeout
first: $first
second: $(describe)"
fi

# 21. A field that cannot be computed runs the check, and leaves no record: after a pass, a
# git whose write-tree fails (first on PATH); and a project that is not a git repository.
dir="$(counted_project no-tree "$PASSING")"
run_gate "$dir" s-no-tree false
mkdir -p "$WORK/broken-git"
cat >"$WORK/broken-git/git" <<FAKE
#!/bin/sh
for arg in "\$@"; do
  if [ "\$arg" = write-tree ]; then echo "fake git: write-tree fails" >&2; exit 1; fi
done
exec "$(command -v git)" "\$@"
FAKE
chmod +x "$WORK/broken-git/git"
PATH="$WORK/broken-git:$PATH" run_gate "$dir" s-no-tree false
broken_runs="$(runs no-tree)"
broken_record=no
[ -e "$(pass_record "$dir")" ] && broken_record=yes
plain="$(new_project no-git "echo run >>\"$WORK/no-git.runs\"; $PASSING")"
run_gate "$plain" s-no-git false
run_gate "$plain" s-no-git false
if [ "$broken_runs" = 2 ] && [ "$broken_record" = no ] && [ "$(runs no-git)" = 2 ]; then
  result "stop-gate skip: a field that cannot be computed runs the check and leaves no record" yes ""
else
  result "stop-gate skip: a field that cannot be computed runs the check and leaves no record" no "runs with the broken git: $broken_runs; record left: $broken_record
runs outside git: $(runs no-git)"
fi

# 22. A record that cannot be used runs the check: not JSON, a field missing, an extra field,
# a field that is not text, no time, a time in the future. Each stop passes and writes a new
# record, which the next one spoils.
dir="$(counted_project garbled "$PASSING")"
run_gate "$dir" s-garbled false
log=""
want=1
for spoil in 'not json' 'delete r.command' 'r.extra = "x"' 'r.limit = Number(r.limit)' 'delete r.time' \
  'r.time = new Date(Date.now() + 3600e3).toISOString()'; do
  if [ "$spoil" = 'not json' ]; then printf 'not json\n' >"$(pass_record "$dir")"; else edit_record "$dir" "$spoil"; fi
  run_gate "$dir" s-garbled false
  want=$((want + 1))
  log="$log"$'\n'"$spoil: runs $(runs garbled) (want $want)"
done
if [ "$(runs garbled)" = 7 ]; then
  result "stop-gate skip: a pass record that cannot be used runs the check" yes ""
else
  result "stop-gate skip: a pass record that cannot be used runs the check" no "${log#?}"
fi

# 23. A pass is reused for less than 24 hours: a record 25 hours old runs the check, one 23
# hours old does not.
dir="$(counted_project age "$PASSING")"
run_gate "$dir" s-age false
edit_record "$dir" 'r.time = new Date(Date.now() - 25 * 3600e3).toISOString()'
run_gate "$dir" s-age false
old_runs="$(runs age)"
edit_record "$dir" 'r.time = new Date(Date.now() - 23 * 3600e3).toISOString()'
run_gate "$dir" s-age false
if [ "$old_runs" = 2 ] && [ "$(runs age)" = 2 ]; then
  result "stop-gate skip: a pass 24 hours old or older runs the check; a younger one is reused" yes ""
else
  result "stop-gate skip: a pass 24 hours old or older runs the check; a younger one is reused" no "runs after 25 hours: $old_runs
runs after 23 hours: $(runs age)"
fi

# 24. A passing check that edits a tracked file while it runs leaves no record: the next stop
# runs it.
dir="$(counted_project busy "echo more >>app.txt; $PASSING")"
run_gate "$dir" s-busy false
run_gate "$dir" s-busy false
if [ "$(runs busy)" = 2 ] && [ ! -e "$(pass_record "$dir")" ]; then
  result "stop-gate skip: a check that changes a file while it runs leaves no pass record" yes ""
else
  result "stop-gate skip: a check that changes a file while it runs leaves no pass record" no "runs: $(runs busy)"
fi

# ---------------------------------------------------------------------------------------
# THE BUDGET. The check sleeps 0.5 seconds against a budget of 0.2: the first over-budget
# stop of a session tells the person (systemMessage), a later one in the same session does
# not, and another session's does; each is a TIMED line marked over. Within the budget (5
# seconds) there is no warning, and the line says within. app.txt is edited between stops so
# that each one runs the check.
# ---------------------------------------------------------------------------------------
message() { node -e 'try { console.log(JSON.parse(process.argv[1]).systemMessage ?? "") } catch { console.log("") }' "$1"; }
dir="$(counted_project budget-time "sleep 0.5; $PASSING")"
HARNESS_KIT_BUDGET_CHECK_SECONDS=0.2 run_gate "$dir" s-budget-1 false
first="$(message "$OUT")"
printf 'v2\n' >"$dir/app.txt"
HARNESS_KIT_BUDGET_CHECK_SECONDS=0.2 run_gate "$dir" s-budget-1 false
second="$(message "$OUT")"
printf 'v3\n' >"$dir/app.txt"
HARNESS_KIT_BUDGET_CHECK_SECONDS=0.2 run_gate "$dir" s-budget-2 false
other="$(message "$OUT")"
printf 'v4\n' >"$dir/app.txt"
HARNESS_KIT_BUDGET_CHECK_SECONDS=5 run_gate "$dir" s-budget-3 false
within="$(message "$OUT")"
lines="$(timed "$dir" | sed -E 's/seconds=[0-9.]+/seconds=S/')"
want_lines="$(printf 'check\tseconds=S,budget=0.2,over\ncheck\tseconds=S,budget=0.2,over\ncheck\tseconds=S,budget=0.2,over\ncheck\tseconds=S,budget=5,within')"
if grep -q '^harness-kit: the check took [0-9.]* seconds, over its budget of 0.2 seconds (HARNESS_KIT_BUDGET_CHECK_SECONDS); .*once per session' <<<"$first" &&
  [ -z "$second" ] && grep -q '^harness-kit: the check took [0-9.]* seconds, over its budget of 0.2 seconds' <<<"$other" &&
  [ -z "$within" ] && [ "$lines" = "$want_lines" ] && [ "$(runs budget-time)" = 4 ]; then
  result "stop-gate budget: an over-budget check is said once per session and recorded every time" yes ""
else
  result "stop-gate budget: an over-budget check is said once per session and recorded every time" no "first: $first
second: $second
another session: $other
within: $within
TIMED lines:
$lines"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures stop-gate case(s) failed"
  exit 1
fi
