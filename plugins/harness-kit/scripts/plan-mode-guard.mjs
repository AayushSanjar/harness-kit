#!/usr/bin/env node
// PreToolUse hook on EnterPlanMode: Claude never enters Claude Code's plan mode on its own.
// A branch is planned with a brief, written by /harness-kit:brief and approved by the
// person, not with a plan-mode plan. This refuses only Claude's own way in, the
// EnterPlanMode tool: the person's own ways in (the built-in command, Shift+Tab,
// --permission-mode plan) run no hook and stay as they are (.reports/inc-naming.inventory.md,
// section 6).
//
// DENIED: every EnterPlanMode call, with a reason that says what to do instead. Every other
// tool is left alone: nothing is printed, so the normal permission flow decides.
import { readFileSync } from "node:fs";

const REASON =
  "harness-kit: plan mode is not used in this project. To plan a branch, the person runs /harness-kit:brief <goal>; otherwise say what you would do in your reply.";

// Never block because the hook could not read its input: exit 1 lets the call proceed and
// shows the line to the person.
let input;
try {
  input = JSON.parse(readFileSync(0, "utf8"));
} catch (error) {
  process.stderr.write(`harness-kit plan-mode-guard: could not read hook input (${error.message}); nothing was checked\n`);
  process.exit(1);
}

if (input?.tool_name !== "EnterPlanMode") process.exit(0);

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: REASON,
    },
  }) + "\n",
);
