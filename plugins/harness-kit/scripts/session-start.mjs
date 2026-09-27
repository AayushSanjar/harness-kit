#!/usr/bin/env node
// SessionStart hook: announce the plugin and its version, tell Claude where its final
// report and its commit message draft go, remove stale ones, and warn the person when the
// Stop hook is off.
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
// THE COMMIT DRAFT LINE. report-path.sh --commit prints .reports/<branch>.commit.txt and
// points .reports/latest.commit.txt at it. Whenever Claude changes files it writes the
// commit message there, in the form check-commits.mjs checks (COMMIT_DRAFT_RULES), so the
// person commits with `git commit -F .reports/latest.commit.txt` instead of writing the
// message by hand.
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
// The report's Summary template: each heading with what goes under it, in this order.
const SUMMARY_HEADINGS = [
  `"Result:" one line.`,
  `"Evidence:" output lines quoted exactly (the final line of each test or check run, and the key FAIL line of each deliberate break), never paraphrased.`,
  `"Deviations:" anything done differently from, or beyond, the brief (including any git command run); "none" if none.`,
  `"Decide:" what the person must decide; "none" if none.`,
  `"Your commands:" the exact commands the person runs next, in order.`,
];

// What the commit draft's body must hold. The first two are what check-commits.mjs fails on.
const COMMIT_DRAFT_RULES = [
  `names every changed file that .harness/protected-paths lists, by its full path, with the reason it changed;`,
  `puts every number that the diff does not show (a test count, a timing, a cost, anything measured or told) on a line starting "Told:" with its source;`,
  `has a line starting "Breaks:" for every new or changed check or test, naming what makes it fail;`,
  `has a line starting "Decision:" for every choice that closes off an alternative.`,
];

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
  const reportPath = (...args) =>
    spawnSync("bash", [fileURLToPath(new URL("./report-path.sh", import.meta.url)), ...args], {
      cwd: projectDir,
      encoding: "utf8",
    });
  const report = reportPath("--prune");
  // Stderr is passed on: "removed the stale report" lines, or why there is no path;
  // outside a git repository there is no report, and nothing to say about it.
  if (report.stderr && !report.stderr.includes("not inside a git repository")) process.stderr.write(report.stderr);
  const path = report.status === 0 ? report.stdout.trim() : "";
  if (path) {
    lines.push(
      `harness-kit: write your final report to ${path} (replace what is there). ` +
        `Start it with a section "## Summary" of at most 15 lines, under exactly these headings, in this order: ` +
        SUMMARY_HEADINGS.join(" ") +
        ` Never commit it: .reports/ is for the person, not for git.`,
    );
    const draft = reportPath("--commit");
    if (draft.stderr) process.stderr.write(draft.stderr);
    const draftPath = draft.status === 0 ? draft.stdout.trim() : "";
    if (draftPath) {
      lines.push(
        `harness-kit: whenever you change files, also write the commit message for all of the branch's uncommitted changes to ${draftPath} ` +
          `(replace what is there; .reports/latest.commit.txt points at it). ` +
          `Its first line is a one-line subject, then a blank line, then a body that ` +
          COMMIT_DRAFT_RULES.join(" ") +
          ` Never commit the draft itself; the person commits with it.`,
      );
    }
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
