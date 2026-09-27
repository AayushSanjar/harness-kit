#!/usr/bin/env node
// SessionStart hook: announce the plugin and its version, tell Claude where its final
// report goes, remove stale reports, and warn the person when the Stop hook is off.
// The version is read from plugin.json so the two can never disagree.
//
// What reaches whom (code.claude.com/docs/en/hooks):
//   - "For most events, Claude Code writes stdout to the debug log and doesn't show it in
//     the transcript. The exceptions are ... SessionStart ..., where Claude Code adds
//     plain-text stdout as context that Claude can see and act on." So the lines below
//     are plain stdout, one per line.
//   - `systemMessage`: "Warning message shown to the user." Plain stdout is not shown to
//     the person, so the HARNESS_KIT_EVAL warning is printed as JSON: the warning in
//     systemMessage, and every line (the warning too) in hookSpecificOutput.
//     additionalContext, "String added to Claude's context at the start of the
//     conversation". Stdout that "Starts with `{` and ends with `}`" is parsed as JSON.
//
// THE REPORT LINE. report-path.sh --prune, run in the project, deletes stale reports and
// prints the report path for the current branch; this hook tells Claude to write there.
// Outside a git repository there is no report line.
//
// THE REVIEWER. review.sh and eval-reviewer.sh start the reviewer with `claude --agent
// harness-kit:reviewer`, and SessionStart input carries `agent_type`, "present when you
// start Claude Code with claude --agent <name>". For that session this hook prints only
// the version line: the read-only reviewer writes no report, an evaluation's worktree gets
// no .reports/ folder, and HARNESS_KIT_EVAL is expected there, so there is no warning.
//
// THE WARNING. The Stop hook (stop-gate.mjs) is off whenever HARNESS_KIT_EVAL is set to
// anything non-empty, and "A hook process inherits the parent environment". Set in a
// normal session (a leftover export in the person's shell), Claude could finish with the
// checks failing, so the person is told.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const REVIEWER = "harness-kit:reviewer";
const EVAL_WARNING =
  "harness-kit WARNING: HARNESS_KIT_EVAL is set in this session, so the Stop hook is OFF: " +
  "Claude can finish while the project's checks fail. Unset HARNESS_KIT_EVAL and start a new session.";

const manifest = JSON.parse(
  readFileSync(new URL("../.claude-plugin/plugin.json", import.meta.url), "utf8"),
);

const readInput = () => {
  if (process.stdin.isTTY) return {};
  try {
    return JSON.parse(readFileSync(0, "utf8"));
  } catch {
    return {};
  }
};

const input = readInput();
const lines = [`harness-kit ${manifest.version} loaded`];

if (input.agent_type !== REVIEWER) {
  const projectDir = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const report = spawnSync(
    "bash",
    [fileURLToPath(new URL("./report-path.sh", import.meta.url)), "--prune"],
    { cwd: projectDir, encoding: "utf8" },
  );
  // Stderr is passed on: "removed the stale report" lines, or why there is no path;
  // outside a git repository there is no report, and nothing to say about it.
  if (report.stderr && !report.stderr.includes("not inside a git repository")) process.stderr.write(report.stderr);
  const path = report.status === 0 ? report.stdout.trim() : "";
  if (path) {
    lines.push(
      `harness-kit: write your final report to ${path} (replace what is there). ` +
        `Start it with a section "## Summary" of at most 10 lines: the result, what failed, and what the person must decide. ` +
        `Never commit it: .reports/ is for the person, not for git.`,
    );
  }
  if (process.env.HARNESS_KIT_EVAL) {
    lines.push(EVAL_WARNING);
    process.stdout.write(
      JSON.stringify({
        systemMessage: EVAL_WARNING,
        hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: lines.join("\n") },
      }) + "\n",
    );
    process.exit(0);
  }
}

console.log(lines.join("\n"));
process.exit(0);
