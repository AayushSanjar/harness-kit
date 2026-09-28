#!/usr/bin/env node
// PreToolUse hook on Write, Edit, MultiEdit and NotebookEdit: Claude never writes a brief's
// approval. Only approve-brief.sh, run by the person in their own terminal after reading
// the brief, writes .reports/<branch>.brief.approved; git-guard.mjs denies the same files
// to Bash.
//
// DENIED: a call whose file (tool_input.file_path, or notebook_path for NotebookEdit)
// names a brief's approval (a name ending in ".brief.approved", guard-lib.mjs), unless the
// file is in a scratch copy under the OS temp folder (guard-lib.mjs). A relative path is
// taken from the hook input's cwd. Everything else is left alone: nothing is printed, so
// the normal permission flow decides. Reading an approval (the Read tool) is not guarded.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { APPROVAL_REASON, TEMP_ROOTS, isApproval, isScratch } from "./guard-lib.mjs";

const TOOLS = new Set(["Write", "Edit", "MultiEdit", "NotebookEdit"]);

// Never block because the hook could not read its input: exit 1 lets the call proceed and
// shows the line to the person.
let input;
try {
  input = JSON.parse(readFileSync(0, "utf8"));
} catch (error) {
  process.stderr.write(`harness-kit brief-guard: could not read hook input (${error.message}); nothing was checked\n`);
  process.exit(1);
}

const tool = input?.tool_name ?? "";
if (!TOOLS.has(tool)) process.exit(0);
const file = String((tool === "NotebookEdit" ? input?.tool_input?.notebook_path : input?.tool_input?.file_path) ?? "");
if (file === "" || !isApproval(file)) process.exit(0);
const path = resolve(input?.cwd || process.cwd(), file);
if (isScratch(path)) process.exit(0);

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason:
        `BLOCKED by harness-kit brief-guard: ${tool} of ${path}, not a scratch copy under the OS temp folder (${TEMP_ROOTS.join(", ")}): ` +
        APPROVAL_REASON,
    },
  }) + "\n",
);
process.exit(0);
