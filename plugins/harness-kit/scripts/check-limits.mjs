#!/usr/bin/env node
// The check that nothing in harness-kit starts long work without the time-limit helper.
//
//   node check-limits.mjs [FOLDER...]    default: this file's own folder (the plugin's scripts)
//
// Reads every *.sh and *.mjs file in each FOLDER (not below it). LONG WORK is:
//   in a .sh file   running a command line (`/bin/sh -c`, `sh -c` or `eval`, as the harness
//                   runs a line of a .harness/*-command file), `claude -p`, `claude plugin`,
//                   any `gh` call, and `git push`, `git fetch` and `git ls-remote`;
//   in a .mjs file  a spawn, spawnSync, exec, execSync, execFile or execFileSync whose
//                   command is "/bin/sh", "sh", "claude" or "gh", or with `shell: true`, and
//                   every exec and execSync (they always run a shell).
// Only code counts: comments, quoted text (but not a $(...) inside double quotes) and heredoc
// bodies are skipped, and a command continued over lines with "\" is read as one.
//
// THE RULES, each problem printed as "FILE:LINE: rule: the line":
//   1. Long work goes through the helper: on its line, hk_limited or hk_git_net
//      (limit-lib.sh), time-limit.mjs or $HK_LIMIT_JS run, or the helper's library
//      (startLimited, runLimited); or it carries a "no-limit:" comment, on its line or the
//      one before, with a reason after the colon.
//   2. A "no-limit:" comment has a reason after it.
//   3. A .sh file that makes a temporary file or folder with mktemp sets its cleanup with
//      hk_on_exit (limit-lib.sh), so the file is removed on any exit.
// Exit 0 with one line saying how many files were read; 1 with the problems.
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HELPER = /\bhk_limited\b|\bhk_git_net\b|time-limit\.mjs|\$HK_LIMIT_JS"? run\b|\bstartLimited\b|\brunLimited\b/;
const MARKER = /(?:#|\/\/)\s*no-limit:(.*)$/;

// shellCode TEXT: TEXT with every character that is not code replaced: quoted text by "_"
// (the quotes kept; a $(...) inside double quotes stays code), comments and heredoc bodies
// by spaces. Line breaks are kept, so line numbers stay.
export const shellCode = (text) => {
  const out = [];
  const stack = ["code"]; // code | double | subst
  const depth = [0]; // open ( in each subst frame
  let heredocs = []; // pending heredoc delimiters, read from the next line
  let i = 0;
  const top = () => stack[stack.length - 1];
  const wordStart = () => {
    const prev = out.length === 0 ? "\n" : text[i - 1];
    return /[\s;&|()]/.test(prev);
  };
  while (i < text.length) {
    const c = text[i];
    const mode = top();
    if (c === "\n") {
      out.push("\n");
      i += 1;
      // Heredoc bodies begin on the next line: blank them to their delimiter lines.
      for (const { delim, dash } of heredocs) {
        while (i < text.length) {
          const end = text.indexOf("\n", i);
          const line = text.slice(i, end === -1 ? text.length : end);
          out.push(" ".repeat(line.length));
          i = end === -1 ? text.length : end;
          if (i < text.length) {
            out.push("\n");
            i += 1;
          }
          if ((dash ? line.replace(/^\t+/, "") : line) === delim) break;
        }
      }
      heredocs = [];
      continue;
    }
    if (mode === "double") {
      if (c === "\\" && i + 1 < text.length) {
        out.push("_", text[i + 1] === "\n" ? "\n" : "_");
        i += 2;
      } else if (c === '"') {
        out.push('"');
        stack.pop();
        i += 1;
      } else if (c === "$" && text[i + 1] === "(" && text[i + 2] !== "(") {
        out.push("$(");
        stack.push("subst");
        depth.push(0);
        i += 2;
      } else {
        out.push("_");
        i += 1;
      }
      continue;
    }
    // code or subst
    if (c === "\\" && i + 1 < text.length) {
      out.push(c, text[i + 1]);
      i += 2;
    } else if (c === "'") {
      const end = text.indexOf("'", i + 1);
      const stop = end === -1 ? text.length : end;
      out.push("'", ...text.slice(i + 1, stop).replace(/[^\n]/g, "_"), end === -1 ? "" : "'");
      i = stop + 1;
    } else if (c === "$" && text[i + 1] === "'") {
      let j = i + 2;
      while (j < text.length && text[j] !== "'") j += text[j] === "\\" ? 2 : 1;
      out.push("$'", ...text.slice(i + 2, j).replace(/[^\n]/g, "_"), "'");
      i = j + 1;
    } else if (c === '"') {
      out.push('"');
      stack.push("double");
      i += 1;
    } else if (c === "#" && wordStart()) {
      const end = text.indexOf("\n", i);
      const stop = end === -1 ? text.length : end;
      out.push(" ".repeat(stop - i));
      i = stop;
    } else if (c === "<" && text[i + 1] === "<" && text[i + 2] !== "<") {
      const m = /^<<(-?)\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\2/.exec(text.slice(i));
      if (m) {
        heredocs.push({ delim: m[3], dash: m[1] === "-" });
        out.push(m[0]);
        i += m[0].length;
      } else {
        out.push("<<");
        i += 2;
      }
    } else if (c === "$" && text[i + 1] === "(" && text[i + 2] !== "(") {
      out.push("$(");
      stack.push("subst");
      depth.push(0);
      i += 2;
    } else if (mode === "subst" && c === "(") {
      depth[depth.length - 1] += 1;
      out.push(c);
      i += 1;
    } else if (mode === "subst" && c === ")") {
      if (depth[depth.length - 1] === 0) {
        stack.pop();
        depth.pop();
      } else {
        depth[depth.length - 1] -= 1;
      }
      out.push(c);
      i += 1;
    } else {
      out.push(c);
      i += 1;
    }
  }
  return out.join("");
};

// Logical lines: [first line number, code, raw text], a line ending in "\" joined with the next.
const logicalLines = (code, raw) => {
  const codeLines = code.split("\n");
  const rawLines = raw.split("\n");
  const lines = [];
  for (let n = 0; n < codeLines.length; n++) {
    let c = codeLines[n];
    let r = rawLines[n] ?? "";
    const first = n;
    while (/\\\s*$/.test(rawLines[n] ?? "") && n + 1 < codeLines.length) {
      n += 1;
      c += ` ${codeLines[n]}`;
      r += ` ${rawLines[n] ?? ""}`;
    }
    lines.push([first + 1, c, r]);
  }
  return lines;
};

const SH_LONG = [
  [/(^|[\s;&|(!{])(\/bin\/)?sh\s+-c\b/, "runs a command line (sh -c)"],
  [/(^|[\s;&|(!{])eval\s/, "runs a command line (eval)"],
  [/(^|[\s;&|(!{])claude\s+(-p|plugin)\b/, "starts claude"],
  [/(^|[\s;&|(!{])gh(\s|$)/, "calls gh"],
  [/(^|[\s;&|(!{])git\s+(?:(?:-C|-c)\s+\S+\s+)*(push|fetch|ls-remote)\b/, "runs a git network command"],
];

// A call of child_process's functions, not a method such as RegExp's .exec(.
const CALL = /(?<![.\w$])(spawn|spawnSync|exec|execSync|execFile|execFileSync)\s*\(/g;

// The text of a call's arguments, from just after its "(" to its matching ")".
const callArgs = (text, from) => {
  let depth = 1;
  let i = from;
  let quote = null;
  while (i < text.length && depth > 0) {
    const c = text[i];
    if (quote) {
      if (c === "\\") i += 1;
      else if (c === quote) quote = null;
    } else if (c === '"' || c === "'" || c === "`") quote = c;
    else if (c === "(") depth += 1;
    else if (c === ")") depth -= 1;
    i += 1;
  }
  return text.slice(from, i - 1);
};

// checkFile PATH NAME: the problems in one file, as [line, rule, text].
export const checkFile = (path, name) => {
  const raw = readFileSync(path, "utf8");
  const rawLines = raw.split("\n");
  const problems = [];
  const marked = (n) => [rawLines[n - 1], rawLines[n - 2]].some((l) => l !== undefined && MARKER.test(l));
  rawLines.forEach((line, k) => {
    const m = MARKER.exec(line);
    if (m && m[1].trim() === "") problems.push([k + 1, "a no-limit comment needs a reason after the colon", line.trim()]);
  });
  if (name.endsWith(".sh")) {
    const code = shellCode(raw);
    for (const [n, c, r] of logicalLines(code, raw)) {
      const hit = SH_LONG.find(([re]) => re.test(c));
      if (!hit || HELPER.test(r) || marked(n)) continue;
      problems.push([n, `${hit[1]} without the time-limit helper (hk_limited, hk_git_net) or a no-limit comment with a reason`, r.trim()]);
    }
    if (/(^|[\s;&|(!{])mktemp\s/m.test(code) && !/\bhk_on_exit\b/.test(code)) {
      const n = code.split("\n").findIndex((l) => /(^|[\s;&|(!{])mktemp\s/.test(l)) + 1;
      problems.push([n, "makes a temporary file with mktemp but sets no cleanup with hk_on_exit", rawLines[n - 1].trim()]);
    }
  } else {
    // Comment lines out; calls and their arguments read from what is left.
    const code = rawLines.map((l) => (/^\s*\/\//.test(l) ? "" : l)).join("\n");
    for (const m of code.matchAll(CALL)) {
      const args = callArgs(code, m.index + m[0].length);
      const first = /^\s*(["'`])([^"'`]*)\1/.exec(args)?.[2];
      const shell = /\bshell\s*:\s*true\b/.test(args) || m[1] === "exec" || m[1] === "execSync";
      if (!shell && !["/bin/sh", "sh", "claude", "gh"].includes(first)) continue;
      const n = code.slice(0, m.index).split("\n").length;
      if (HELPER.test(rawLines[n - 1]) || marked(n)) continue;
      problems.push([n, `${first ? `spawns ${first}` : "runs a shell"} without the time-limit helper (startLimited, runLimited) or a no-limit comment with a reason`, rawLines[n - 1].trim()]);
    }
  }
  return problems;
};

const main = (folders) => {
  let files = 0;
  const all = [];
  for (const folder of folders) {
    for (const name of readdirSync(folder).sort()) {
      if (!name.endsWith(".sh") && !name.endsWith(".mjs")) continue;
      files += 1;
      for (const [n, rule, text] of checkFile(join(folder, name), name)) all.push(`${join(folder, name)}:${n}: ${rule}: ${text}`);
    }
  }
  if (all.length > 0) {
    console.log(all.join("\n"));
    return 1;
  }
  console.log(`check-limits: ${files} files read; no long work starts without the time-limit helper, and every mktemp has its cleanup`);
  return 0;
};

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const folders = process.argv.slice(2);
  process.exit(main(folders.length > 0 ? folders : [dirname(fileURLToPath(import.meta.url))]));
}
