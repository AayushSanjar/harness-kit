#!/usr/bin/env node
// SessionStart hook: announce the plugin and its version, tell Claude where its final
// report and its commit message draft go (and to update or list everything that describes
// behaviour it changed), remove stale ones, and warn the person when the Stop hook is off.
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
// THE REPORT LINE. report-path.sh --prune, run in the project, deletes stale reports (and
// stale briefs and approvals) and prints the report path for the current branch; this hook
// tells Claude to write there, starting with the Summary template (summaryHeadings). Its
// "Replay:" heading says which fault replay ran and why, as replay-faults.sh's Replay line
// said it (targeted, of the faults tied to the files changed, or full). Its
// "Deviations:" heading measures the work against the branch's brief, named by its path
// (the report path ending .brief.md, as report-path.sh --brief names it): /harness-kit:brief
// writes it and the person approves it with approve-brief.sh. Outside a git repository
// there is no report line.
//
// THE COMMIT DRAFT LINE. report-path.sh --commit prints .reports/<branch>.commit.txt and
// points .reports/latest.commit.txt at it. Whenever Claude changes files it writes the
// commit message there, in the form check-commits.mjs checks (COMMIT_DRAFT_RULES), so the
// person commits with `git commit -F .reports/latest.commit.txt` instead of writing the
// message by hand.
//
// THE COMMIT LINE. After the draft line: Claude may commit its own work locally with that
// draft once the project's check passes (the commit-msg hook from install-hooks.sh checks
// the message as it is committed), but never a change to a protected file (those go to the
// person as a patch, applied with land.sh, which runs the approval) and never a push. The
// git-guard hook (git-guard.mjs) refuses the push, destructive git, the person's scripts
// and any command naming a brief's approval outside the temp folder, and brief-guard.mjs
// refuses the file tools that approval, whatever Claude reads here.
//
// THE BLAST-RADIUS LINE. After the report, commit draft and commit lines comes one more: before finishing, Claude
// searches for every file, comment, test and document that describes behaviour it changed,
// and updates each or lists it in the report, so a change does not leave its descriptions
// saying the old thing.
//
// THE BASH LINE. Then: harness-kit's .sh scripts are run as `bash <path>`, since some are
// not executable (install-hooks.sh, events.sh and the *-lib.sh files), and a plugin copied into the cache
// keeps the modes git gave it.
//
// THE TIME RULE. Then, in a git repository too: a command expected to take over 2 minutes is
// estimated first, and run only if the approved brief lists it in its Verification plan
// (otherwise Claude asks the person); and no command starts in the background without a
// time limit, through the time-limit helper (time-limit.mjs). background-guard.mjs refuses
// a background command that is not wrapped in it, whatever Claude reads here.
//
// THE START-UP PICTURE. After those lines, in a git repository, come the lines of
// start-picture.mjs (its header says what each holds and where it comes from): the branch
// and its brief with the goal, the last check result from the local event log with the
// failing checks, the last full fault replay's age from the same log and, where
// .harness/ci-replay names it, on CI, read with gh under a 5-second limit (from 7 days on,
// the command that starts one on CI, or where there is no CI replay, the local command with
// how long it would take), the branch's last review verdict from .harness/reviews.tsv, the
// uncommitted changes, and the first lines of the project's state file (.harness/state-file,
// default docs/STATE.md). At most 16 lines, none longer than 200 characters but for the
// replay line's command, which is never cut; a missing source is shown as "none" with the
// reason. Outside a git repository there is no picture.
//
// THE REVIEWER. review.sh and eval-reviewer.sh start the reviewer with `claude --agent
// harness-kit:reviewer`, and SessionStart input carries `agent_type`, "present when you
// start Claude Code with claude --agent <name>". For that session this hook prints only
// the version line (no start-up picture either): the read-only reviewer writes no report,
// an evaluation's worktree gets no .reports/ folder, and HARNESS_KIT_EVAL is expected
// there, so there is no warning.
//
// THE WARNING. The Stop hook (stop-gate.mjs) is off whenever HARNESS_KIT_EVAL is set to
// anything non-empty, and "A hook process inherits the parent environment". Set in a
// normal session (a leftover export in the person's shell), Claude could finish with the
// checks failing, so the person is told.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { startPicture } from "./start-picture.mjs";

const REVIEWER = "harness-kit:reviewer";
const EVAL_WARNING =
  "harness-kit WARNING: HARNESS_KIT_EVAL is set in this session, so the Stop hook is OFF: " +
  "Claude can finish while the project's checks fail. Unset HARNESS_KIT_EVAL and start a new session.";
const BLAST_RADIUS =
  "harness-kit: before finishing, search for every file, comment, test and document that describes behaviour you changed, " +
  "and update each or list it in the report.";
const BASH_RULE = "harness-kit: run harness-kit's .sh scripts as `bash <path>`: some are not executable.";
const timeRule = (brief) =>
  `harness-kit time rule: before you run any command you expect to take over 2 minutes, write down your estimate of its time. ` +
  `Run it only if the approved brief (${brief}) lists it in its Verification plan; otherwise ask the person. ` +
  `Never start a command in the background without a time limit: wrap it as ` +
  `node ${join(dirname(fileURLToPath(import.meta.url)), "time-limit.mjs")} run --limit <seconds> -- <command>. ` +
  `The background-guard hook refuses a background command that is not wrapped.`;
// The report's Summary template: each heading with what goes under it, in this order.
// BRIEF is the path of the branch's brief.
const summaryHeadings = (brief) => [
  `"Result:" one line.`,
  `"Evidence:" output lines quoted exactly (the final line of each test or check run, and the key FAIL line of each deliberate break), never paraphrased.`,
  `"Replay:" "targeted (N faults)" or "full", and why, as replay-faults.sh's Replay line said it; "targeted (0 faults)" with why when no fault is tied to the changed files.`,
  `"Deviations:" anything done differently from, or beyond, the brief (${brief}, the brief from /harness-kit:brief as the person approved it, when there is one; otherwise what the person asked for), including any git command run; "none" if none.`,
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
        summaryHeadings(path.replace(/\.md$/, ".brief.md")).join(" ") +
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
          ` Never commit the draft file itself.`,
      );
      lines.push(
        `harness-kit: you may commit your own work locally with that draft (git commit -F ${draftPath}) once the project's check passes; ` +
          `the commit-msg hook checks the message and, if it refuses, says how to fix it. ` +
          `Never commit a change to a file that .harness/protected-paths lists: put those changes in a patch under .reports/ ` +
          `(git diff -- <files> > .reports/<name>.patch, then git apply -R that patch to take them out of the working tree), ` +
          `and name "land.sh .reports/<name>.patch" in "Your commands": the person applies it, with the approval. Never push: the person ships.`,
      );
    }
    lines.push(BLAST_RADIUS);
    lines.push(BASH_RULE);
    lines.push(timeRule(path.replace(/\.md$/, ".brief.md")));
  }
  lines.push(...(await startPicture(projectDir)));
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
