#!/usr/bin/env node
// Stop hook: refuse to let Claude finish while the project's checks fail.
//
// The check command is the first line of $CLAUDE_PROJECT_DIR/.harness/check-command.
// A failing check blocks the stop with {"decision": "block", "reason": ...}.
// At most MAX_BLOCKS blocks in a row per session; after that the stop is
// allowed and the person is told through systemMessage. The count lives in the
// OS temp folder, resets when the checks pass, and resets when
// stop_hook_active is false (a fresh stop, not a continuation from a block).
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const MAX_BLOCKS = 3;
const MAX_FEEDBACK_LINES = 50;
const INSTRUCTION =
  "Fix the failing checks before finishing. Do not edit protected files; if a protected test is wrong, say so and stop.";
const BUDGET_LINE =
  "harness-kit: checks still failing after 3 attempts — the person must look";

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

const result = spawnSync(command, { cwd: projectDir, shell: true, encoding: "utf8" });

if (result.status === 0) {
  rmSync(countFile, { force: true });
  process.exit(0);
}

const previous = input.stop_hook_active === true ? readCount(countFile) : 0;
if (previous >= MAX_BLOCKS) {
  process.stderr.write(`${BUDGET_LINE}\n`);
  process.stdout.write(JSON.stringify({ systemMessage: BUDGET_LINE }) + "\n");
  process.exit(0);
}
writeFileSync(countFile, String(previous + 1));

const output = `${result.stdout || ""}\n${result.stderr || ""}`;
let lines = output.split(/\r?\n/).filter((line) => /^\s*FAIL\b/.test(line));
if (lines.length === 0) {
  // No FAIL lines: fall back to the tail of the output so Claude sees something.
  lines = output.split(/\r?\n/).filter((line) => line.trim() !== "");
  if (result.error) lines.push(String(result.error.message));
  lines = lines.slice(-MAX_FEEDBACK_LINES);
} else if (lines.length > MAX_FEEDBACK_LINES) {
  lines = [...lines.slice(0, MAX_FEEDBACK_LINES), `... ${lines.length - MAX_FEEDBACK_LINES} more FAIL lines`];
}

const exit = result.status === null ? `signal ${result.signal}` : `exit ${result.status}`;
const reason = [
  `harness-kit stop gate: \`${command}\` failed (${exit}), block ${previous + 1} of ${MAX_BLOCKS}.`,
  ...lines.map((line) => line.slice(0, 500)),
  INSTRUCTION,
].join("\n");

process.stdout.write(JSON.stringify({ decision: "block", reason }) + "\n");
process.exit(0);
