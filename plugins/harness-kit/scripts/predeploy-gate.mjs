#!/usr/bin/env node
// PreToolUse hook on Bash: refuse a deploy command while the project's pre-deploy
// check fails.
//
// Configured by two files in the project, first line of each:
//   .harness/deploy-pattern      a JavaScript regular expression for the deploy command
//   .harness/predeploy-command   the check, run from the project root with /bin/sh
// If either is missing the gate is off, and says so on stderr.
//
// WHERE THE PATTERN MATCHES. The command is split on shell separators, and the pattern
// is tried only at the START of each segment, after any `NAME=value` assignments. So
// `npm run build && forge deploy` matches, and a heredoc body, a quoted string or a
// comment that merely mentions the words does not. An unanchored regex over the whole
// command blocked documentation writes five times in the project this was taken from;
// the fifth time, a pattern that noisy gets narrowed or switched off.
//
// WHAT THIS IS NOT. It reads command TEXT. It does not see a deploy run inside a script,
// an alias, `bash -c '...'`, `eval`, or `"$(...)"`; name those in the pattern if they are
// how the project deploys (`npm run deploy`). And it cannot gate a person's terminal at
// all: a Claude Code hook sees only Claude's Bash calls. For the human side, deploy.sh
// beside this file runs the same check before the deploy.
//
// THREE OUTCOMES, NOT TWO. A check that PASSED, a check that FAILED, and a check that
// COULD NOT RUN (not found, not executable, killed, timed out). The last blocks exactly
// as a failure does, but says so, so nobody hunts for a test failure that is really a
// missing tool or a network timeout. And a pass is said out loud (systemMessage, on the
// matched command only), so a pass cannot be mistaken for the gate not running.
//
// THE TIME LIMIT. The check runs through the time-limit helper (time-limit.mjs) under the
// check limit, and never more than HOOK_CHECK_MAX_SECONDS, 540: below the hook's own
// timeout in hooks.json (600 s), as Claude Code killing this hook first would let the
// deploy go ahead unchecked. Past it, the check's whole process group is stopped (SIGTERM,
// then SIGKILL when the grace period ends) and the deploy is refused, COULD NOT RUN: timed
// out. tests/validate.sh checks that the limit plus the grace period stays below the
// hook's timeout.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { exitOnSignals, limitSeconds, runLimited } from "./time-limit.mjs";

const MAX_OUTPUT_LINES = 40;
const HOOK_CHECK_MAX_SECONDS = 540;

// Emitting nothing on the pass path is deliberate: permissionDecision "allow" would
// skip the normal permission prompts. This hook only ever adds a refusal.
const allow = () => process.exit(0);

const deny = (reason) => {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason,
      },
    }) + "\n",
  );
  process.exit(0);
};

// ---------------------------------------------------------------------------
// Splitting a command into segments
// ---------------------------------------------------------------------------

// Returns the command's segments as text, split on ; & && || | ( ) and newlines that are
// outside quotes. Heredoc bodies and comments are dropped. Quoted strings stay in their
// segment, whole, so their contents can never start a segment of their own.
const segmentsOf = (command) => {
  const segments = [];
  const pendingHeredocs = []; // { delimiter, stripTabs }, bodies start at the next newline
  let current = "";
  let i = 0;
  const n = command.length;

  const endSegment = () => {
    if (current.trim() !== "") segments.push(current.trim());
    current = "";
  };

  // Skip heredoc bodies that begin after the newline at command[i - 1].
  const skipHeredocBodies = () => {
    while (pendingHeredocs.length > 0) {
      const { delimiter, stripTabs } = pendingHeredocs.shift();
      for (;;) {
        if (i >= n) return;
        const end = command.indexOf("\n", i);
        const line = command.slice(i, end === -1 ? n : end);
        i = end === -1 ? n : end + 1;
        if ((stripTabs ? line.replace(/^\t+/, "") : line) === delimiter) break;
      }
    }
  };

  // Reads the heredoc delimiter word starting at i, removing quotes and backslashes.
  const readDelimiter = () => {
    let word = "";
    while (i < n && !/[\s;&|<>()]/.test(command[i])) {
      const c = command[i];
      if (c === "'" || c === '"') {
        const close = command.indexOf(c, i + 1);
        const stop = close === -1 ? n : close;
        word += command.slice(i + 1, stop);
        current += command.slice(i, stop + 1);
        i = stop + 1;
      } else if (c === "\\" && i + 1 < n) {
        word += command[i + 1];
        current += command.slice(i, i + 2);
        i += 2;
      } else {
        word += c;
        current += c;
        i += 1;
      }
    }
    return word;
  };

  while (i < n) {
    const c = command[i];
    const next = command[i + 1];

    if (c === "\\") {
      // A backslash-newline continues the line; any other escaped character is literal.
      current += next === "\n" ? " " : command.slice(i, i + 2);
      i += 2;
    } else if (c === "'") {
      const close = command.indexOf("'", i + 1);
      const stop = close === -1 ? n : close + 1;
      current += command.slice(i, stop);
      i = stop;
    } else if (c === '"') {
      let j = i + 1;
      while (j < n && command[j] !== '"') j += command[j] === "\\" ? 2 : 1;
      const stop = Math.min(j + 1, n);
      current += command.slice(i, stop);
      i = stop;
    } else if (c === "#" && (current === "" || /\s$/.test(current))) {
      // A comment runs to the end of the line; the newline itself still separates.
      const end = command.indexOf("\n", i);
      i = end === -1 ? n : end;
    } else if (c === "<" && next === "<" && command[i + 2] === "<") {
      current += "<<<"; // a here-string: its word stays in the segment, no body follows
      i += 3;
    } else if (c === "<" && next === "<") {
      i += 2;
      current += "<<";
      const stripTabs = command[i] === "-";
      if (stripTabs) {
        current += "-";
        i += 1;
      }
      while (i < n && (command[i] === " " || command[i] === "\t")) current += command[i++];
      const delimiter = readDelimiter();
      if (delimiter !== "") pendingHeredocs.push({ delimiter, stripTabs });
    } else if (c === "\n") {
      endSegment();
      i += 1;
      skipHeredocBodies();
    } else if (c === ";" || c === "(" || c === ")" || c === "`") {
      endSegment();
      i += 1;
    } else if (c === "|" || c === "&") {
      // `>&`, `<&` and `&>` are redirections (2>&1, &>log), not separators.
      const prev = current[current.length - 1];
      if (c === "&" && (prev === ">" || prev === "<" || next === ">")) {
        current += c;
        i += 1;
      } else {
        endSegment();
        i += next === c ? 2 : 1;
      }
    } else {
      current += c;
      i += 1;
    }
  }
  endSegment();
  return segments;
};

// Leading `NAME=value` assignments, and the reserved words that can open a command
// (`if forge deploy; then`), come off before the pattern is tried.
const ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*=(?:'[^']*'|"(?:[^"\\]|\\.)*"|\\.|[^\s'"\\])*(?:\s+|$)/;
const RESERVED = /^(?:!|\{|if|then|elif|else|do|while|until|time)(?:\s+|$)/;

const commandPart = (segment) => {
  let rest = segment;
  for (;;) {
    const m = ASSIGNMENT.exec(rest) ?? RESERVED.exec(rest);
    if (!m) return rest;
    rest = rest.slice(m[0].length);
  }
};

// ---------------------------------------------------------------------------
// Hook protocol
// ---------------------------------------------------------------------------

let input;
try {
  input = JSON.parse(readFileSync(0, "utf8"));
} catch (error) {
  // Never block because the hook could not read its input, but never pass silently
  // either: exit 1 lets the tool call proceed and shows this line to the person.
  process.stderr.write(`harness-kit predeploy-gate: could not read hook input (${error.message}); nothing was checked\n`);
  process.exit(1);
}

if ((input?.tool_name ?? "") !== "Bash") allow();
const command = input?.tool_input?.command ?? "";
const projectDir = process.env.CLAUDE_PROJECT_DIR || input?.cwd || process.cwd();

const firstLine = (name) => {
  try {
    return readFileSync(join(projectDir, ".harness", name), "utf8").split(/\r?\n/)[0].trim();
  } catch {
    return "";
  }
};

const pattern = firstLine("deploy-pattern");
const check = firstLine("predeploy-command");
for (const [name, value] of [["deploy-pattern", pattern], ["predeploy-command", check]]) {
  if (!value) {
    process.stderr.write(`harness-kit: no .harness/${name}, so the pre-deploy gate is off\n`);
    allow();
  }
}

let deployRe;
try {
  deployRe = new RegExp(`^(?:${pattern})`);
} catch (error) {
  // Configured but unusable. Allowing would pass every deploy unchecked, silently.
  deny(
    `BLOCKED by harness-kit predeploy-gate: .harness/deploy-pattern is not a valid regular expression, ` +
      `so this command could not be checked.\n\n  ${error.message}\n\nFix the pattern, or delete the file to turn the gate off.`,
  );
}

const matched = segmentsOf(command).find((segment) => deployRe.test(commandPart(segment)));
if (matched === undefined) allow();

// `exec 2>&1` first, so the output keeps its order and a syntax error in the check
// itself lands in the captured text too.
const limit = Math.min(limitSeconds("check"), HOOK_CHECK_MAX_SECONDS);
exitOnSignals();
const result = await runLimited("/bin/sh", ["-c", 'exec 2>&1; eval "$1"', "harness-kit-predeploy", check], {
  cwd: projectDir,
  stdio: ["ignore", "pipe", "pipe"],
  limit,
  capture: true,
});

if (!result.timedOut && result.code === 0) {
  process.stdout.write(
    JSON.stringify({ systemMessage: `harness-kit predeploy-gate: \`${check}\` passed; the deploy may go ahead` }) + "\n",
  );
  process.exit(0);
}

let outcome;
if (result.timedOut) {
  outcome = `COULD NOT RUN: timed out after ${limit} s`;
} else if (result.error) {
  outcome = `COULD NOT RUN: ${result.error.message}`;
} else if (result.signal) {
  outcome = `COULD NOT RUN: killed by ${result.signal}`;
} else if (result.code === 127 || result.code === 126) {
  const why = result.code === 127 ? "command not found" : "not executable";
  outcome = `COULD NOT RUN: exit ${result.code} (${why}), so the check itself never ran`;
} else {
  outcome = `FAILED: exit ${result.code}`;
}

const lines = `${result.stdout ?? ""}${result.stderr ?? ""}`.replace(/\n+$/, "").split(/\r?\n/);
const tail = lines.slice(-MAX_OUTPUT_LINES);
const omitted = lines.length - tail.length;

deny(
  [
    `BLOCKED by harness-kit predeploy-gate: the pre-deploy check did not pass, so this deploy was not run.`,
    ``,
    `  deploy:  ${matched}`,
    `  check:   ${check}`,
    `  result:  ${outcome}`,
    ``,
    omitted > 0 ? `Last ${tail.length} lines of the check's output (${omitted} earlier lines omitted):` : `The check's output:`,
    ...tail,
    ``,
    `Fix what the check reports and deploy again. Do not change the check, the pattern or the command to get past this gate.`,
  ].join("\n"),
);
