#!/usr/bin/env bash
# Tests for plugins/harness-kit/scripts/predeploy-gate.mjs and deploy.sh. Each case
# runs against a temporary project folder with a fake check script. The hook is only
# ever handed deploy commands as text in its JSON input, and deploy.sh only ever runs
# a fake deploy script that writes a marker file: nothing is deployed anywhere.
# Prints one PASS or FAIL line per case and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/plugins/harness-kit/scripts/predeploy-gate.mjs"
DEPLOY="$ROOT/plugins/harness-kit/scripts/deploy.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
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

# new_project NAME [CHECK_SCRIPT_BODY [PATTERN]]: make a project folder. With a body,
# it writes scripts/check.sh, points .harness/predeploy-command at it, and writes
# .harness/deploy-pattern. Every check records the folder it ran in to check-ran, so a
# case can tell whether the check ran, and where.
new_project() {
  local dir="$WORK/$1"
  mkdir -p "$dir"
  if [ $# -ge 2 ]; then
    mkdir -p "$dir/.harness" "$dir/scripts"
    printf '#!/bin/sh\npwd -P > check-ran\n%s\n' "$2" >"$dir/scripts/check.sh"
    chmod +x "$dir/scripts/check.sh"
    printf 'scripts/check.sh\n' >"$dir/.harness/predeploy-command"
    printf '%s\n' "${3:-forge\s+deploy\b}" >"$dir/.harness/deploy-pattern"
  fi
  echo "$dir"
}

FAILING_CHECK='i=1; while [ $i -le 50 ]; do echo "check line $i"; i=$((i + 1)); done; exit 1'

# run_gate DIR COMMAND: run the hook from an unrelated folder, as Claude Code would with
# the project in CLAUDE_PROJECT_DIR; sets OUT, ERR, STATUS and REASON.
run_gate() {
  local input
  input="$(node -e 'console.log(JSON.stringify({ hook_event_name: "PreToolUse", tool_name: "Bash", cwd: process.argv[1], tool_input: { command: process.argv[2] } }))' "$1" "$2")"
  OUT="$(cd "$WORK" && CLAUDE_PROJECT_DIR="$1" node "$GATE" <<<"$input" 2>"$WORK/stderr")"
  STATUS=$?
  ERR="$(cat "$WORK/stderr")"
  REASON="$(node -e 'try { console.log(JSON.parse(process.argv[1]).hookSpecificOutput.permissionDecisionReason) } catch {}' "$OUT")"
}

is_deny() { grep -q '"permissionDecision":"deny"' <<<"$1"; }
describe() { printf 'exit %s\nstdout: %s\nstderr: %s' "$STATUS" "$OUT" "$ERR"; }

# 1. No config: allowed, one stderr line, no decision.
dir="$(new_project no-config)"
run_gate "$dir" "forge deploy"
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] &&
  [ "$ERR" = "harness-kit: no .harness/deploy-pattern, so the pre-deploy gate is off" ]; then
  result "no config: allowed, gate off on stderr" yes ""
else
  result "no config: allowed, gate off on stderr" no "$(describe)"
fi

# 2. Unrelated command: allowed silently, and the (failing) check is never run.
dir="$(new_project unrelated "$FAILING_CHECK")"
run_gate "$dir" "ls -la && npm test"
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ] && [ ! -e "$dir/check-ran" ]; then
  result "unrelated command: allowed, check not run" yes ""
else
  result "unrelated command: allowed, check not run" no "$(describe)"
fi

# 3. Matching command, passing check: allowed, the pass said out loud, and the check
# ran in the project root although the hook was started elsewhere.
dir="$(new_project passing 'echo "all good"; exit 0')"
run_gate "$dir" "forge deploy -e production"
if [ "$STATUS" -eq 0 ] && ! is_deny "$OUT" &&
  grep -q '"systemMessage":"harness-kit predeploy-gate: `scripts/check.sh` passed' <<<"$OUT" &&
  [ "$(cat "$dir/check-ran" 2>/dev/null)" = "$(cd "$dir" && pwd -P)" ]; then
  result "matching command, passing check: allowed, check ran in the project root" yes ""
else
  result "matching command, passing check: allowed, check ran in the project root" no "$(describe)"
fi

# 4. Matching command, failing check: denied with exit 0, the check's own output shown,
# last 40 of its 50 lines.
dir="$(new_project failing "$FAILING_CHECK")"
run_gate "$dir" "forge deploy"
if [ "$STATUS" -eq 0 ] && is_deny "$OUT" &&
  grep -q 'result:  FAILED: exit 1' <<<"$REASON" &&
  grep -qx 'check line 50' <<<"$REASON" && grep -qx 'check line 11' <<<"$REASON" &&
  ! grep -qx 'check line 10' <<<"$REASON" && grep -q '10 earlier lines omitted' <<<"$REASON"; then
  result "matching command, failing check: denied with the last 40 lines of output" yes ""
else
  result "matching command, failing check: denied with the last 40 lines of output" no "$(describe)"
fi

# 5. Compound command: the deploy is the second segment.
dir="$(new_project compound "$FAILING_CHECK")"
run_gate "$dir" "npm run build && forge deploy"
if [ "$STATUS" -eq 0 ] && is_deny "$OUT" && grep -q 'deploy:  forge deploy' <<<"$REASON"; then
  result "compound \"npm run build && forge deploy\": matched" yes ""
else
  result "compound \"npm run build && forge deploy\": matched" no "$(describe)"
fi

# 6. Environment assignments before the deploy, one with a quoted space.
dir="$(new_project assignments "$FAILING_CHECK")"
run_gate "$dir" 'NODE_ENV=production NOTE="a b" forge deploy'
if [ "$STATUS" -eq 0 ] && is_deny "$OUT"; then
  result "environment assignments before the deploy: matched" yes ""
else
  result "environment assignments before the deploy: matched" no "$(describe)"
fi

# 7. A heredoc whose body mentions the words, including at the start of a line and
# after a semicolon: not matched, check not run.
dir="$(new_project heredoc "$FAILING_CHECK")"
run_gate "$dir" "cat > notes.md <<'EOF'
Run the build, then forge deploy.
forge deploy; then check the logs
EOF
echo written"
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] && [ ! -e "$dir/check-ran" ]; then
  result "heredoc mentioning \"forge deploy\": not matched" yes ""
else
  result "heredoc mentioning \"forge deploy\": not matched" no "$(describe)"
fi

# 8. An echo whose quoted string mentions the words, after a separator inside the quotes.
dir="$(new_project echo "$FAILING_CHECK")"
run_gate "$dir" 'echo "build first; forge deploy after" && git commit -m '"'"'docs: && forge deploy'"'"
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] && [ ! -e "$dir/check-ran" ]; then
  result "echo and commit message quoting \"forge deploy\": not matched" yes ""
else
  result "echo and commit message quoting \"forge deploy\": not matched" no "$(describe)"
fi

# 9. A check that cannot run is reported as such, and still denies.
dir="$(new_project missing "$FAILING_CHECK")"
printf 'no-such-check-command-harness-kit\n' >"$dir/.harness/predeploy-command"
run_gate "$dir" "forge deploy"
if [ "$STATUS" -eq 0 ] && is_deny "$OUT" &&
  grep -q 'result:  COULD NOT RUN: exit 127 (command not found)' <<<"$REASON"; then
  result "check command not found: denied as COULD NOT RUN, not as FAILED" yes ""
else
  result "check command not found: denied as COULD NOT RUN, not as FAILED" no "$(describe)"
fi

# 10. An invalid pattern denies instead of passing every deploy unchecked.
dir="$(new_project bad-pattern "$FAILING_CHECK" 'forge (deploy')"
run_gate "$dir" "ls"
if [ "$STATUS" -eq 0 ] && is_deny "$OUT" && grep -q 'not a valid regular expression' <<<"$REASON"; then
  result "invalid deploy-pattern: denied, not silently off" yes ""
else
  result "invalid deploy-pattern: denied, not silently off" no "$(describe)"
fi

# deploy.sh. The deploy is a fake script that writes a marker file.
FAKE_DEPLOY="$WORK/fake-deploy.sh"
printf '#!/bin/sh\necho "fake deploy $*"\ntouch "$DEPLOYED_MARKER"\n' >"$FAKE_DEPLOY"
chmod +x "$FAKE_DEPLOY"

# run_deploy DIR: run deploy.sh from a subfolder of DIR; sets OUT (stdout and stderr) and STATUS.
run_deploy() {
  mkdir -p "$1/sub"
  OUT="$(cd "$1/sub" && DEPLOYED_MARKER="$1/deployed" bash "$DEPLOY" "$FAKE_DEPLOY" --env test 2>&1)"
  STATUS=$?
}
describe_deploy() { printf 'exit %s\noutput: %s' "$STATUS" "$OUT"; }

# 11. deploy.sh, passing check: the deploy runs.
dir="$(new_project deploy-pass 'echo "all good"; exit 0')"
run_deploy "$dir"
if [ "$STATUS" -eq 0 ] && [ -e "$dir/deployed" ] && grep -q 'fake deploy --env test' <<<"$OUT" &&
  [ "$(cat "$dir/check-ran" 2>/dev/null)" = "$(cd "$dir" && pwd -P)" ]; then
  result "deploy.sh, passing check: deploy runs" yes ""
else
  result "deploy.sh, passing check: deploy runs" no "$(describe_deploy)"
fi

# 12. deploy.sh, failing check: the deploy does not run, the check's output is shown,
# and the exit is the check's.
dir="$(new_project deploy-fail "$FAILING_CHECK")"
run_deploy "$dir"
if [ "$STATUS" -eq 1 ] && [ ! -e "$dir/deployed" ] && grep -qx 'check line 50' <<<"$OUT" &&
  grep -q 'the check FAILED (exit 1); not deploying' <<<"$OUT"; then
  result "deploy.sh, failing check: deploy does not run" yes ""
else
  result "deploy.sh, failing check: deploy does not run" no "$(describe_deploy)"
fi

# 13. deploy.sh with no config refuses rather than deploying unchecked.
dir="$(new_project deploy-none)"
run_deploy "$dir"
if [ "$STATUS" -eq 2 ] && [ ! -e "$dir/deployed" ] && grep -q 'nothing was checked, so nothing was deployed' <<<"$OUT"; then
  result "deploy.sh, no config: refuses, deploy does not run" yes ""
else
  result "deploy.sh, no config: refuses, deploy does not run" no "$(describe_deploy)"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures predeploy-gate case(s) failed"
  exit 1
fi
