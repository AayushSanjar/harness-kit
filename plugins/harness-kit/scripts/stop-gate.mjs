#!/usr/bin/env node
// Stop hook: refuse to let Claude finish while the project's checks fail.
//
// The check command is the first line of $CLAUDE_PROJECT_DIR/.harness/check-command.
// A failing check blocks the stop with {"decision": "block", "reason": ...}.
// At most MAX_BLOCKS blocks in a row per session; after that the stop is
// allowed and the person is told through systemMessage. The count lives in the
// OS temp folder, resets when the checks pass, and resets when
// stop_hook_active is false (a fresh stop, not a continuation from a block).
//
// Off during a reviewer evaluation: eval-reviewer.sh runs the reviewer with
// HARNESS_KIT_EVAL=1, and a hook process inherits claude's environment ("A hook process
// inherits the parent environment", code.claude.com/docs/en/hooks). With that variable
// set to anything non-empty the stop is allowed silently and the check is not run: a
// read-only reviewer on a historical commit cannot fix the checks, and a block would
// only spend its turns and budget.
//
// Off for the reviewer: review.sh and eval-reviewer.sh start it with `claude --agent
// harness-kit:reviewer`, and hook input carries agent_type, "Present when the session uses
// `--agent` or the hook fires inside a subagent" (same page). For that agent_type the stop
// is allowed silently and the check is not run, for the same reason: the reviewer is
// read-only and cannot fix the checks. Any other agent_type, or none, is gated as usual.
//
// THE EVENT LOG. Each check run is passed, with its output, to events.sh's
// harness_check_event (through bash, in the project folder), which appends a CHECKED line to
// the local event log, .git/harness-kit/events.tsv, when the result differs from the last
// one recorded for the branch; the SessionStart hook's start-up picture shows the latest.
// A recording that fails changes nothing about the decision. When the gate is off
// (HARNESS_KIT_EVAL, the reviewer, no check-command) nothing runs, so nothing is recorded.
//
// IT FAILS CLOSED ON TIME. Claude Code gives this hook 600 seconds (hooks.json), and a hook
// that runs out of time renders no decision, which would let Claude stop unchecked. So the
// check runs through the time-limit helper (time-limit.mjs) under the check limit, and never
// more than HOOK_CHECK_MAX_SECONDS, 540: the hook's limit less 60 seconds, for the grace
// period, the recording and Node's start. A check past its limit is stopped with its whole
// process group, and the stop is BLOCKED with a TIMEOUT message, counted in the same budget
// of 3 blocks as a failing check; it is recorded as a CHECKED FAIL with the status
// "timeout <limit>s". tests/validate.sh checks that this limit plus the grace period stays
// below the hook's timeout.
//
// THE SKIP. In a git repository, the check is not run again when nothing has changed since
// it last passed. After a pass, the hook writes the pass record, <git dir>/harness-kit/
// stop-gate-pass (the worktree's own git directory, so worktrees never share one), holding
// these fields and the time it was written:
//   tree     the working tree's tree id: every tracked file as it is on disk and every
//            untracked file .gitignore does not ignore, from a copy of the index (git add -A,
//            then git write-tree, with GIT_INDEX_FILE), so the real index is never touched.
//            The copy keeps the real index's file time, rounded down to the second: git
//            re-reads a file whose time is not older than its index's, so a same-size edit
//            made in the second the index was written is still seen (git's racy-index check)
//   head    HEAD's commit (a check can read history)
//   refs     the sha256 of `git for-each-ref` (a check can compare with the base)
//   command  the check command
//   version  the plugin's version, from its plugin.json
//   node     Node's version
//   limit    the check limit this stop uses, in seconds
// A stop skips the check only when the record can be used, every field computed now equals
// the record's, and the record is younger than PASS_HOURS (24 hours). A skip clears the
// block count, as a pass does, prints one line on stderr and records nothing: no CHECKED
// line (the result did not change) and no TIMED line (nothing ran). Anything the hook cannot
// read runs the check, and nothing is recorded: a field that cannot be computed (no git
// repository, a git error, an index that cannot be copied, an unreadable plugin.json), or a
// record that cannot be used (unreadable, not JSON, a field missing or extra, a field that is
// not text, or a time missing or in the future). The record is written only for a check that
// ended by itself (not stopped at its limit) with exit 0, and only when the fields computed
// after it equal those before it, so a check that changes a file while it runs leaves none;
// any other check removes it. Ignored files (node_modules, .env, build output) are not in the
// tree: an `npm install` after a pass is not seen until something else changes or the pass
// is 24 hours old. git-guard.mjs and brief-guard.mjs deny Claude writing the record.
//
// THE BUDGET. Each check run is timed and recorded, with the check budget (120 seconds by
// default; time-limit.mjs's BUDGETS), as a TIMED line in the event log, at every run, through
// events.sh's harness_timed_event, in the same bash call as the CHECKED line. The first time
// in a Claude session that a check is over its budget, the person is told through
// systemMessage (on a pass or a block); the session's marker is a file in the OS temp folder,
// beside the block count. Later overruns in the session are recorded, not said again.
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, statSync, utimesSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { budgetSeconds, budgetWarning, exitOnSignals, limitSeconds, overBudget, runLimited } from "./time-limit.mjs";

const REVIEWER = "harness-kit:reviewer";
const HOOK_CHECK_MAX_SECONDS = 540;
const MAX_BLOCKS = 3;
const MAX_FEEDBACK_LINES = 50;
const INSTRUCTION =
  "Fix the failing checks before finishing. Do not edit protected files; if a protected test is wrong, say so and stop.";
const TIMEOUT_INSTRUCTION = "Find what hangs or runs slowly and fix it before finishing.";
const BUDGET_LINE =
  "harness-kit: checks still failing after 3 attempts — the person must look";
// THE SKIP's age limit: a pass older than this runs the check again.
const PASS_HOURS = { env: "HARNESS_KIT_STOP_GATE_PASS_HOURS", hours: 24 };
const PASS_FIELDS = ["tree", "head", "refs", "command", "version", "node", "limit"];
const PASS_KEYS = [...PASS_FIELDS, "time"].sort().join(",");
const PLUGIN_JSON = new URL("../.claude-plugin/plugin.json", import.meta.url);

function readInput() {
  try {
    return JSON.parse(readFileSync(0, "utf8"));
  } catch {
    return {};
  }
}

function readCount(file) {
  try {
    const n = Number.parseInt(readFileSync(file, "utf8"), 10);
    return Number.isFinite(n) ? n : 0;
  } catch {
    return 0;
  }
}

const input = readInput();
if (process.env.HARNESS_KIT_EVAL || input.agent_type === REVIEWER) process.exit(0);
const projectDir = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();

let command;
try {
  command = readFileSync(join(projectDir, ".harness", "check-command"), "utf8")
    .split(/\r?\n/)[0]
    .trim();
} catch {
  process.stderr.write("harness-kit: no .harness/check-command, so the stop gate is off\n");
  process.exit(0);
}
if (!command) {
  process.stderr.write("harness-kit: .harness/check-command is empty, so the stop gate is off\n");
  process.exit(0);
}

const sessionId = String(input.session_id || "unknown").replace(/[^A-Za-z0-9_-]/g, "_");
const countFile = join(tmpdir(), `harness-kit-stop-gate-${sessionId}.count`);

const limit = Math.min(limitSeconds("check"), HOOK_CHECK_MAX_SECONDS);

// THE SKIP.
// git ARGS [INDEX]: git's stdout, run in the project (with GIT_INDEX_FILE=INDEX when given),
// or null when it fails. Only local commands that read the repository.
const git = (args, index) => {
  const r = spawnSync("git", args, {
    cwd: projectDir,
    encoding: "utf8",
    maxBuffer: 256 * 1024 * 1024,
    env: index ? { ...process.env, GIT_INDEX_FILE: index } : process.env,
  });
  return r.status === 0 && !r.error ? r.stdout : null;
};
const trimmed = (text) => (text === null ? null : text.trim() || null);
const sha256 = (text) => (text === null ? null : createHash("sha256").update(text).digest("hex"));
const positive = (value) => (/^[0-9]+(\.[0-9]+)?$/.test(value ?? "") && Number(value) > 0 ? Number(value) : null);
const passMaxMs = (positive(process.env[PASS_HOURS.env]) ?? PASS_HOURS.hours) * 60 * 60 * 1000;

// The working tree's tree id, from a copy of the index; null when it cannot be computed.
const workingTree = () => {
  const real = trimmed(git(["rev-parse", "--path-format=absolute", "--git-path", "index"]));
  if (real === null) return null;
  let folder = null;
  try {
    folder = mkdtempSync(join(tmpdir(), "harness-kit-stop-gate-index."));
    const index = join(folder, "index");
    if (existsSync(real)) {
      // The copy takes the real index's time, read before the copy is made: a copy with a
      // new time would have git trust a same-size edit made in the second the index was
      // written. An error here is caught below, so the check runs.
      const second = Math.floor(statSync(real).mtimeMs / 1000);
      copyFileSync(real, index);
      utimesSync(index, second, second);
    }
    if (git(["add", "-A"], index) === null) return null;
    return trimmed(git(["write-tree"], index));
  } catch {
    return null;
  } finally {
    if (folder !== null) rmSync(folder, { recursive: true, force: true });
  }
};

const pluginVersion = () => {
  try {
    const version = JSON.parse(readFileSync(PLUGIN_JSON, "utf8")).version;
    return typeof version === "string" && version !== "" ? version : null;
  } catch {
    return null;
  }
};

// The fields, computed now; a field that cannot be computed is null.
const passFields = () => ({
  tree: workingTree(),
  head: trimmed(git(["rev-parse", "-q", "--verify", "HEAD"])),
  refs: sha256(git(["for-each-ref", "--format=%(objectname) %(refname)"])),
  command: command,
  version: pluginVersion(),
  node: process.version,
  limit: String(limit),
});

// A field matches only when it was computed and equals the record's.
const same = (now, recorded) => now !== null && now === recorded;

// Whether RECORD, as parsed, can be used: an object with exactly the fields and the time,
// each one text, and a time that is a date, not in the future.
const usable = (record) =>
  record !== null &&
  typeof record === "object" &&
  !Array.isArray(record) &&
  Object.keys(record).sort().join(",") === PASS_KEYS &&
  Object.values(record).every((value) => typeof value === "string") &&
  Date.parse(record.time) <= Date.now();

const gitDir = trimmed(git(["rev-parse", "--path-format=absolute", "--git-dir"]));
const passFile = gitDir === null ? null : join(gitDir, "harness-kit", "stop-gate-pass");

// The pass record, or null when there is none or it cannot be used.
const readPass = () => {
  if (passFile === null) return null;
  let record;
  try {
    record = JSON.parse(readFileSync(passFile, "utf8"));
  } catch {
    return null;
  }
  if (!usable(record)) return null;
  return record;
};

const tooOld = (record) => Date.now() - Date.parse(record.time) >= passMaxMs;
const before = passFile === null ? null : passFields();
const pass = readPass();
if (before !== null && pass !== null && !tooOld(pass) && PASS_FIELDS.every((field) => same(before[field], pass[field]))) {
  rmSync(countFile, { force: true });
  process.stderr.write(`harness-kit stop gate: nothing changed since the check passed at ${pass.time}; the check was not run\n`);
  process.exit(0);
}

exitOnSignals();
const result = await runLimited("/bin/sh", ["-c", command], { cwd: projectDir, limit, capture: true });
const output = `${result.stdout || ""}\n${result.stderr || ""}`;
const status = result.timedOut ? `timeout ${limit}s` : result.error ? "not run" : result.signal ? `signal ${result.signal}` : String(result.code);
const seconds = result.seconds ?? 0;
const budget = budgetSeconds("check");

// Record the result (events.sh's harness_check_event decides whether it is new) and its time
// (harness_timed_event, at every run; quiet, as the warning is said below, once a session).
// no-limit: events.sh's harness_check_event and harness_timed_event only read and append the local event log
const recorded = spawnSync(
  "bash",
  ["-c", '. "$1" && { harness_check_event stop-gate.mjs "" "$2"; harness_timed_event stop-gate.mjs check "$3" "$4" quiet </dev/null; }', "harness-kit",
    fileURLToPath(new URL("./events.sh", import.meta.url)), status, seconds.toFixed(2), String(budget)],
  { cwd: projectDir, input: output, encoding: "utf8" },
);
if (recorded.stderr) process.stderr.write(recorded.stderr);

// THE BUDGET: said once per Claude session.
const warnedFile = join(tmpdir(), `harness-kit-stop-gate-${sessionId}.budget-check`);
let warning = null;
if (overBudget(seconds, budget) && !existsSync(warnedFile)) {
  warning = `${budgetWarning("check", seconds, budget)}. This is said once per session.`;
  try {
    writeFileSync(warnedFile, "");
  } catch {
    // A marker that cannot be written costs only a repeated warning.
  }
}

// THE SKIP's record: kept only for a check that ended by itself with exit 0 and changed
// nothing while it ran; any other check removes it.
let keep = before !== null;
if (result.timedOut) keep = false; // a check stopped at its limit proved nothing
if (result.code !== 0) keep = false; // a failing check
if (keep) {
  const after = passFields();
  keep = PASS_FIELDS.every((field) => same(after[field], before[field]));
}
if (passFile !== null) {
  try {
    if (keep) {
      mkdirSync(dirname(passFile), { recursive: true });
      writeFileSync(passFile, `${JSON.stringify({ ...before, time: new Date().toISOString() })}\n`);
    } else {
      rmSync(passFile, { force: true });
    }
  } catch {
    // A record that cannot be written or removed costs only a skip: the next stop checks.
  }
}

if (!result.timedOut && result.code === 0) {
  rmSync(countFile, { force: true });
  if (warning !== null) process.stdout.write(JSON.stringify({ systemMessage: warning }) + "\n");
  process.exit(0);
}

const previous = input.stop_hook_active === true ? readCount(countFile) : 0;
if (previous >= MAX_BLOCKS) {
  process.stderr.write(`${BUDGET_LINE}\n`);
  process.stdout.write(JSON.stringify({ systemMessage: warning === null ? BUDGET_LINE : `${BUDGET_LINE}\n${warning}` }) + "\n");
  process.exit(0);
}
writeFileSync(countFile, String(previous + 1));

let lines = output.split(/\r?\n/).filter((line) => /^\s*FAIL\b/.test(line));
if (result.timedOut) {
  // What it printed last, to show where it hung.
  lines = output.split(/\r?\n/).filter((line) => line.trim() !== "").slice(-MAX_FEEDBACK_LINES);
} else if (lines.length === 0) {
  // No FAIL lines: fall back to the tail of the output so Claude sees something.
  lines = output.split(/\r?\n/).filter((line) => line.trim() !== "");
  if (result.error) lines.push(String(result.error.message));
  lines = lines.slice(-MAX_FEEDBACK_LINES);
} else if (lines.length > MAX_FEEDBACK_LINES) {
  lines = [...lines.slice(0, MAX_FEEDBACK_LINES), `... ${lines.length - MAX_FEEDBACK_LINES} more FAIL lines`];
}

const exit = result.code === null ? `signal ${result.signal}` : `exit ${result.code}`;
const reason = (
  result.timedOut
    ? [
        `harness-kit stop gate: \`${command}\` did not finish within ${limit} seconds (TIMEOUT); it was stopped. Block ${previous + 1} of ${MAX_BLOCKS}.`,
        TIMEOUT_INSTRUCTION,
        ...(lines.length > 0 ? ["Its last output lines:", ...lines.map((line) => line.slice(0, 500))] : []),
      ]
    : [`harness-kit stop gate: \`${command}\` failed (${exit}), block ${previous + 1} of ${MAX_BLOCKS}.`, ...lines.map((line) => line.slice(0, 500)), INSTRUCTION]
).join("\n");

process.stdout.write(JSON.stringify({ decision: "block", reason, ...(warning === null ? {} : { systemMessage: warning }) }) + "\n");
process.exit(0);
