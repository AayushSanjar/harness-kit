#!/usr/bin/env node
// PreToolUse hook on Bash: refuse a background command that does not run under a time limit.
//
// The session-start time rule tells Claude never to start a command in the background
// without a time limit; this hook enforces it. It reads only a call whose
// `run_in_background` is true, and allows every other call without reading it.
//
// ALLOWED in the background: a line where every command it runs is the time-limit helper,
//   node <...>/time-limit.mjs run --limit <seconds, or a limit's name> [--name L] [--merge] -- <command>
// That is every command of a list (; && || &), of a pipeline (|), of a ( ... ) subshell,
// and of each command substitution ($(...), backticks, <(...)), wherever it is, the
// wrapped command's arguments and redirections included: a substitution runs in the calling
// shell, before the helper starts, so it needs a wrapper of its own. A command of only
// variable assignments (NAME=value) runs nothing itself and is allowed (its values'
// substitutions are still read). The wrapped command itself is the helper's to limit, so
// `-- sh -c '...'` is how to put a `cd` or a pipeline inside one limit.
//
// DENIED, with the form to use: any other background line, naming the first command that is
// not wrapped. A line that cannot be read (an unclosed quote, backtick or substitution) is
// denied too: the guard fails closed.
//
// The line is read as git-guard.mjs reads it (guard-lib.mjs's tokenize and parse). WHAT
// THIS IS NOT: it reads command TEXT; a script or alias that starts background work of its
// own is not seen.
import { readFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parse, tokenize } from "./guard-lib.mjs";
import { LIMITS } from "./time-limit.mjs";

const HELPER = join(dirname(fileURLToPath(import.meta.url)), "time-limit.mjs");
const WRAPPED = `node ${HELPER} run --limit <seconds> -- <command>`;

// Never block because the hook could not read its input: exit 1 lets the call proceed and
// shows the line to the person.
let input;
try {
  input = JSON.parse(readFileSync(0, "utf8"));
} catch (error) {
  process.stderr.write(`harness-kit background-guard: could not read hook input (${error.message}); nothing was checked\n`);
  process.exit(1);
}
if ((input?.tool_name ?? "") !== "Bash" || input?.tool_input?.run_in_background !== true) process.exit(0);
const command = String(input?.tool_input?.command ?? "");

const deny = (why) => {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason:
          `BLOCKED by harness-kit background-guard: a background command must run under a time limit. Run it as: ${WRAPPED}\n\n` +
          `${why}\n\nEvery command the line runs, each command substitution included, must be wrapped; ` +
          `to limit a cd, a pipeline or a list as one, wrap it as -- sh -c '<the commands>'.`,
      },
    }) + "\n",
  );
  process.exit(0);
};

// Unclosed: true when TEXT ends inside a quote, a backtick or a $( ... ).
const unclosed = (text) => {
  let depth = 0;
  for (let i = 0; i < text.length; i += 1) {
    const c = text[i];
    if (c === "\\") i += 1;
    else if (c === "'") {
      const end = text.indexOf("'", i + 1);
      if (end < 0) return true;
      i = end;
    } else if (c === '"') {
      for (i += 1; i < text.length && text[i] !== '"'; i += 1) {
        if (text[i] === "\\") i += 1;
        else if (text[i] === "$" && text[i + 1] === "(") depth += 1;
        else if (text[i] === ")" && depth > 0) depth -= 1;
      }
      if (i >= text.length) return true;
    } else if (c === "`") {
      const end = text.indexOf("`", i + 1);
      if (end < 0) return true;
      i = end;
    } else if (c === "$" && text[i + 1] === "(") {
      depth += 1;
      i += 1;
    } else if (c === "#" && (i === 0 || /[\s;&|()]/.test(text[i - 1]))) {
      const end = text.indexOf("\n", i);
      i = end < 0 ? text.length : end;
    } else if (c === ")" && depth > 0) depth -= 1;
  }
  return depth > 0;
};

// A word as text: literals as they are, a variable as $NAME, a substitution as $(...).
const wordText = (parts) =>
  parts.map((p) => ("lit" in p ? p.lit : "variable" in p ? `$${p.variable}` : "sub" in p ? `$(${p.sub})` : "tilde" in p ? "~" : "$?")).join("");
const literal = (parts) => (parts.every((p) => "lit" in p) ? parts.map((p) => p.lit).join("") : null);
const ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*=/;

// Is WORDS (a command's words, redirections left out) a run of the helper?
const isHelper = (words) => {
  const lits = words.map((w) => literal(w.word));
  if (basename(lits[0] ?? "") !== "node") return false;
  // The script: a word ending in /time-limit.mjs (a variable in front of it is fine).
  const script = words[1]?.word;
  const tail = script?.[script.length - 1];
  if (!tail || !("lit" in tail) || !(tail.lit === "time-limit.mjs" || tail.lit.endsWith("/time-limit.mjs"))) return false;
  if (lits[2] !== "run") return false;
  let limit = null;
  let k = 3;
  for (; k < words.length && lits[k] !== "--"; k += 1) {
    if (lits[k] === "--limit") limit = lits[++k] ?? null;
    else if (lits[k] === "--name") k += 1;
    else if (lits[k] !== "--merge") return false;
  }
  const valid = limit !== null && (Object.hasOwn(LIMITS, limit) || (/^[0-9]+(\.[0-9]+)?$/.test(limit) && Number(limit) > 0));
  return valid && lits[k] === "--" && k + 1 < words.length;
};

// The first command in the parsed list ITEMS that is not a run of the helper, as text; or
// null when every one is. Substitutions anywhere are read as lines of their own.
const firstUnwrapped = (items) => {
  for (const { chain } of items) {
    for (const { pipeline } of chain) {
      for (const element of pipeline) {
        for (const token of element.words) {
          for (const part of token.word) {
            if ("sub" in part) {
              const found = firstUnwrapped(parse(tokenize(part.sub)));
              if (found !== null) return found;
            }
          }
        }
        if (element.subshell) {
          const found = firstUnwrapped(element.subshell);
          if (found !== null) return found;
          continue;
        }
        const words = element.words.filter((w) => !w.redirect);
        let start = 0;
        while (start < words.length && ASSIGNMENT.test(literal(words[start].word.slice(0, 1)) ?? "")) start += 1;
        const rest = words.slice(start);
        if (rest.length === 0) continue; // assignments only: nothing runs
        if (!isHelper(rest)) return rest.map((w) => wordText(w.word)).join(" ");
      }
    }
  }
  return null;
};

if (command.trim() === "") process.exit(0);
if (unclosed(command)) deny("This line could not be read: it ends inside a quote, a backtick or a $( ... ).");
let found;
try {
  found = firstUnwrapped(parse(tokenize(command)));
} catch (error) {
  deny(`This line could not be read (${error.message}).`);
}
if (found !== null) deny(`Not wrapped: \`${found.slice(0, 300)}\``);
process.exit(0);
