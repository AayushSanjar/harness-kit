#!/usr/bin/env bash
# Tests for plan-mode-guard.mjs, the PreToolUse hook that refuses Claude's EnterPlanMode
# tool (a branch is planned with /harness-kit:brief), and for its line in hooks.json.
#
# Each call is given to the hook as Claude Code gives it (JSON on stdin); nothing is run.
# Prints one PASS or FAIL line per case and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/plugins/harness-kit/scripts/plan-mode-guard.mjs"
HOOKS="$ROOT/plugins/harness-kit/hooks/hooks.json"
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

# call TOOL: runs the hook on a call to TOOL; prints its exit status, then its stdout.
call() {
  local out status
  out="$(node -e 'console.log(JSON.stringify({ hook_event_name: "PreToolUse", tool_name: process.argv[1], tool_input: {}, cwd: "/tmp" }))' "$1" |
    node "$GUARD" 2>/dev/null)"
  status=$?
  echo "$status"
  echo "$out"
}

# (1) EnterPlanMode is denied, with a reason that names the full command.
out="$(call EnterPlanMode)"
got="$(tail -n +2 <<<"$out" | node -e '
  const o = JSON.parse(require("fs").readFileSync(0, "utf8")).hookSpecificOutput ?? {};
  console.log(`${o.hookEventName} ${o.permissionDecision}`);
  console.log(o.permissionDecisionReason ?? "");
' 2>&1)"
if [ "$(head -1 <<<"$out")" = 0 ] && [ "$(head -1 <<<"$got")" = "PreToolUse deny" ] && grep -qF '/harness-kit:brief <goal>' <<<"$got"; then
  result "plan-mode-guard: EnterPlanMode is denied, and the reason names /harness-kit:brief" yes ""
else
  result "plan-mode-guard: EnterPlanMode is denied, and the reason names /harness-kit:brief" no "hook output: $out"
fi

# (2) Every other tool is left alone: exit 0 and nothing printed.
bad=""
for tool in ExitPlanMode Bash Write Edit Read Agent Skill; do
  out="$(call "$tool")"
  [ "$out" = "0" ] || bad="$bad$tool: $out"$'\n'
done
if [ -z "$bad" ]; then
  result "plan-mode-guard: every other tool is left alone" yes ""
else
  result "plan-mode-guard: every other tool is left alone" no "$bad"
fi

# (3) Input it cannot read: exit 1 (the call proceeds), a line on stderr, nothing on stdout.
err="$(printf 'not json' | node "$GUARD" 2>&1 >/dev/null)"
status=$?
out="$(printf 'not json' | node "$GUARD" 2>/dev/null)"
if [ "$status" -eq 1 ] && [ -z "$out" ] && grep -qF 'could not read hook input' <<<"$err"; then
  result "plan-mode-guard: unreadable input exits 1 and lets the call proceed" yes ""
else
  result "plan-mode-guard: unreadable input exits 1 and lets the call proceed" no "exit $status; stdout: $out; stderr: $err"
fi

# (4) hooks.json runs the guard on PreToolUse for EnterPlanMode (a matcher naming it among
# "|"-separated tool names).
out="$(node -e '
  const hooks = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).hooks ?? {};
  const found = (hooks.PreToolUse ?? []).some((m) =>
    String(m.matcher ?? "").split("|").includes("EnterPlanMode") &&
    (m.hooks ?? []).some((h) => (h.args ?? []).some((a) => a.endsWith("/scripts/plan-mode-guard.mjs"))));
  if (!found) { console.log("no PreToolUse matcher naming EnterPlanMode runs scripts/plan-mode-guard.mjs"); process.exit(1); }
' "$HOOKS" 2>&1)"
status=$?
if [ "$status" -eq 0 ]; then
  result "hooks.json runs plan-mode-guard.mjs on PreToolUse for EnterPlanMode" yes ""
else
  result "hooks.json runs plan-mode-guard.mjs on PreToolUse for EnterPlanMode" no "$out"
fi

[ "$failures" -eq 0 ]
