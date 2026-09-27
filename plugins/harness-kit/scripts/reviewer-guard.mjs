#!/usr/bin/env node
// PreToolUse hook: keep the harness-kit reviewer read-only.
//
// A plugin agent's own `hooks` and `permissionMode` frontmatter are ignored, so its
// `tools` and `disallowedTools` lists are the only restriction the agent file can
// carry. This plugin-level hook is the second layer: it denies every write, shell and
// web tool whenever the hook input's agent_type is the reviewer.
//
// It matches on agent_type ALONE. A subagent call carries agent_id too, but a headless
// `claude -p --agent harness-kit:reviewer` run (what review.sh starts) has no agent_id:
// the reviewer is the main thread there. In both cases agent_type is the plugin-scoped
// name, "harness-kit:reviewer"; with --agent it is that name whether the flag was given
// the scoped or the bare name (observed with Claude Code 2.1.283).
//
// Any other agent_type, or none, is left alone: nothing is printed, so the normal
// permission flow decides.
import { readFileSync } from "node:fs";

const REVIEWER = "harness-kit:reviewer";
const DENIED = new Set(["Write", "Edit", "MultiEdit", "NotebookEdit", "Bash", "WebFetch", "WebSearch"]);

let input;
try {
  input = JSON.parse(readFileSync(0, "utf8"));
} catch (error) {
  // This hook fires for every agent's write, shell and web calls, so a broken input
  // must not block them all. Exit 1 lets the call proceed and shows this line to the
  // person; for the reviewer, its tools and disallowedTools lists still hold.
  process.stderr.write(`harness-kit reviewer-guard: could not read hook input (${error.message}); nothing was checked\n`);
  process.exit(1);
}

if (input?.agent_type !== REVIEWER || !DENIED.has(input?.tool_name)) process.exit(0);

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason:
        `BLOCKED by harness-kit reviewer-guard: the reviewer is read-only, so ${input.tool_name} is not allowed. ` +
        `Use Read, Grep and Glob to gather evidence; if an item cannot be judged without running something, mark it FAILED and say what is missing.`,
    },
  }) + "\n",
);
process.exit(0);
