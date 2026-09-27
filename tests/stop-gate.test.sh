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
# The gate is off under HARNESS_KIT_EVAL; only case 6 sets it.
unset HARNESS_KIT_EVAL
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

# run_gate DIR SESSION STOP_HOOK_ACTIVE: run the hook; sets OUT, ERR, STATUS.
run_gate() {
  local input
  input=$(printf '{"session_id":"%s","hook_event_name":"Stop","cwd":"%s","stop_hook_active":%s}' "$2" "$1" "$3")
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

if [ "$failures" -ne 0 ]; then
  echo "$failures stop-gate case(s) failed"
  exit 1
fi
