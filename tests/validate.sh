#!/usr/bin/env bash
# Repository-level checks for harness-kit. Prints one PASS or FAIL line per
# check and exits non-zero if any check fails.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$ROOT/plugins/harness-kit"
failures=0

check() {
  local label="$1" log="$2" status="$3"
  if [ "$status" -eq 0 ]; then
    echo "PASS $label"
  else
    echo "FAIL $label"
    sed 's/^/    /' <<<"$log"
    failures=$((failures + 1))
  fi
}

# (a) Marketplace and plugin validation. A marketplace run does not open the
# plugin's hook, skill, agent or command files, so the plugin folder is
# validated separately.
out="$(claude plugin validate "$ROOT" --strict 2>&1)"
check "claude plugin validate --strict (marketplace: repository root)" "$out" $?

out="$(claude plugin validate "$PLUGIN" --strict 2>&1)"
check "claude plugin validate --strict (plugin: plugins/harness-kit)" "$out" $?

# (b) The SessionStart script prints exactly the expected line and exits 0.
expected="harness-kit 0.1.0 loaded"
out="$(node "$PLUGIN/scripts/session-start.mjs" 2>&1)"
status=$?
if [ "$status" -eq 0 ] && [ "$out" = "$expected" ]; then
  check "session-start.mjs prints \"$expected\"" "" 0
else
  check "session-start.mjs prints \"$expected\"" \
    "exit $status; got: $out" 1
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
