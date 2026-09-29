// Shared by git-guard.mjs (Bash) and brief-guard.mjs (Write, Edit, MultiEdit, NotebookEdit),
// the PreToolUse hooks that keep Claude out of the person's steps: what a scratch copy is,
// and which files are a brief's approval or the Stop hook's pass record. And by git-guard.mjs and background-guard.mjs
// (Bash): reading a shell command as the shell reads it (tokenize, then parse), below.
//
// A SCRATCH COPY is a folder strictly under the OS temp folder: os.tmpdir() (TMPDIR), /tmp,
// or either one's real path (on macOS /tmp is /private/tmp), with symbolic links resolved,
// so a link from the temp folder into the project is not a scratch copy (a link that exists
// when the hook runs: one the same command makes is not seen). Tests and experiments in
// throwaway clones there are left alone. A project kept under the temp folder is not
// guarded.
//
// A BRIEF'S APPROVAL is any file whose name ends in ".brief.approved"
// (.reports/<branch>.brief.approved, brief-lib.sh). Only approve-brief.sh, run by the person
// in their own terminal, writes it; Claude never does, in the real working tree.
//
// THE STOP HOOK'S PASS RECORD is any file named "stop-gate-pass"
// (<git dir>/harness-kit/stop-gate-pass, stop-gate.mjs's THE SKIP). Only the Stop hook
// writes it, after the check passes; a record Claude wrote would let a stop skip the check.
import { realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";

// PATH with every existing part's symbolic links resolved (a path that does not exist yet
// keeps its missing tail as written).
export const realish = (path) => {
  const normal = resolve(path);
  try {
    return realpathSync(normal);
  } catch {
    const parent = dirname(normal);
    return parent === normal ? normal : join(realish(parent), basename(normal));
  }
};

export const TEMP_ROOTS = [...new Set([tmpdir(), "/tmp"].flatMap((root) => [resolve(root), realish(root)]))];

// True when DIR (a path; null means a folder the caller could not work out) is a scratch copy.
export const isScratch = (dir) => dir !== null && TEMP_ROOTS.some((root) => realish(dir).startsWith(`${root}/`));

// True when NAME, a file name or a path, names a brief's approval.
export const isApproval = (name) => /\.brief\.approved$/.test(name);

// True when NAME, a file name or a path, names the Stop hook's pass record.
export const isPassRecord = (name) => /(?:^|\/)stop-gate-pass$/.test(name);

export const PASS_REASON =
  "it is the Stop hook's pass record (<git dir>/harness-kit/stop-gate-pass), which only the Stop hook writes, after the check passes; " +
  "a record written by anything else would let a stop skip the check. To have the check run, just finish: the Stop hook runs it.";

export const APPROVAL_REASON =
  "it is a brief's approval (.reports/<branch>.brief.approved), which only approve-brief.sh writes, run by the person in their own terminal " +
  "after reading the brief. Change the brief if it needs changing, and put approve-brief.sh in the report's \"Your commands\". " +
  "To read an approval, use the Read tool.";

// ---------------------------------------------------------------------------------------
// Words and tokens. A word is a list of parts: { lit }, { variable, fallback }, { sub }
// (a command substitution's text), { tilde }, or { unknown }.
// ---------------------------------------------------------------------------------------

// The index just after the ")" closing the "(" at text[open], skipping quotes; -1 if none.
export const closing = (text, open) => {
  let depth = 0;
  for (let i = open; i < text.length; i += 1) {
    const c = text[i];
    if (c === "\\") i += 1;
    else if (c === "'") {
      const end = text.indexOf("'", i + 1);
      if (end < 0) return -1;
      i = end;
    } else if (c === '"') {
      for (i += 1; i < text.length && text[i] !== '"'; i += 1) if (text[i] === "\\") i += 1;
    } else if (c === "(") depth += 1;
    else if (c === ")" && --depth === 0) return i + 1;
  }
  return -1;
};

export const tokenize = (text) => {
  const tokens = [];
  const heredocs = [];
  let parts = null;
  let quotedWord = false;
  let redirect = false;
  let i = 0;
  const n = text.length;
  const lit = (s) => {
    parts ??= [];
    const last = parts[parts.length - 1];
    if (last && "lit" in last) last.lit += s;
    else parts.push({ lit: s });
  };
  const endWord = () => {
    if (parts !== null) tokens.push({ word: parts, redirect });
    parts = null;
    quotedWord = false;
    redirect = false;
  };
  const op = (value) => {
    endWord();
    tokens.push({ op: value });
  };
  // $... at text[i] (i at the "$"); pushes the part and moves i past it.
  const dollar = () => {
    const next = text[i + 1];
    if (next === "(" && text[i + 2] === "(") {
      const end = closing(text, i + 1);
      parts.push({ unknown: true });
      i = end < 0 ? n : end;
    } else if (next === "(") {
      const end = closing(text, i + 1);
      parts.push({ sub: text.slice(i + 2, end < 0 ? n : end - 1) });
      i = end < 0 ? n : end;
    } else if (next === "{") {
      const end = text.indexOf("}", i + 2);
      const inner = text.slice(i + 2, end < 0 ? n : end);
      const m = /^([A-Za-z_][A-Za-z0-9_]*)(?::?-(.*))?$/s.exec(inner);
      parts.push(m ? { variable: m[1], fallback: m[2] === undefined ? undefined : m[2].replace(/^(["'])(.*)\1$/s, "$2") } : { unknown: true });
      i = end < 0 ? n : end + 1;
    } else if (next === "'") {
      const end = text.indexOf("'", i + 2);
      lit(text.slice(i + 2, end < 0 ? n : end));
      i = end < 0 ? n : end + 1;
    } else if (/[A-Za-z_]/.test(next ?? "")) {
      const m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(text.slice(i + 1));
      parts.push({ variable: m[0] });
      i += 1 + m[0].length;
    } else if (/[0-9?$!#@*-]/.test(next ?? "")) {
      parts.push({ unknown: true });
      i += 2;
    } else {
      lit("$");
      i += 1;
    }
  };
  const backtick = () => {
    let j = i + 1;
    let inner = "";
    while (j < n && text[j] !== "`") {
      if (text[j] === "\\" && j + 1 < n) {
        inner += text[j + 1];
        j += 2;
      } else inner += text[j++];
    }
    parts.push({ sub: inner });
    i = j + 1;
  };
  const skipHeredocs = () => {
    while (heredocs.length > 0) {
      const { delimiter, strip } = heredocs.shift();
      while (i < n) {
        const end = text.indexOf("\n", i);
        const line = text.slice(i, end < 0 ? n : end);
        i = end < 0 ? n : end + 1;
        if ((strip ? line.replace(/^\t+/, "") : line) === delimiter) break;
      }
    }
  };

  while (i < n) {
    const c = text[i];
    const next = text[i + 1];
    if (c === "\\") {
      if (next === "\n") i += 2;
      else {
        parts ??= [];
        lit(next ?? "");
        i += 2;
      }
    } else if (c === "'") {
      parts ??= [];
      quotedWord = true;
      const end = text.indexOf("'", i + 1);
      lit(text.slice(i + 1, end < 0 ? n : end));
      i = end < 0 ? n : end + 1;
    } else if (c === '"') {
      parts ??= [];
      quotedWord = true;
      lit("");
      i += 1;
      while (i < n && text[i] !== '"') {
        if (text[i] === "\\" && /[$`"\\\n]/.test(text[i + 1] ?? "")) {
          if (text[i + 1] !== "\n") lit(text[i + 1]);
          i += 2;
        } else if (text[i] === "$") dollar();
        else if (text[i] === "`") backtick();
        else lit(text[i++]);
      }
      i += 1;
    } else if (c === "$") {
      parts ??= [];
      dollar();
    } else if (c === "`") {
      parts ??= [];
      backtick();
    } else if (c === "#" && parts === null) {
      const end = text.indexOf("\n", i);
      i = end < 0 ? n : end;
    } else if (c === "~" && parts === null && (next === undefined || next === "/" || /[\s;&|()<>]/.test(next))) {
      parts = [{ tilde: true }];
      i += 1;
    } else if ((c === "<" || c === ">") && next === "(") {
      // Process substitution: runs like $(...).
      parts ??= [];
      const end = closing(text, i + 1);
      parts.push({ sub: text.slice(i + 2, end < 0 ? n : end - 1) });
      i = end < 0 ? n : end;
    } else if (c === "<" || c === ">" || (c === "&" && next === ">")) {
      // A redirection: an fd number just before it is not a word; the word after it is
      // its target, not an argument.
      if (parts !== null && !quotedWord && parts.length === 1 && /^\d+$/.test(parts[0].lit ?? "")) parts = null;
      endWord();
      let j = i;
      while (j < n && /[<>&|-]/.test(text[j]) && j - i < 3) j += 1;
      const operator = text.slice(i, j);
      i = j;
      if (operator.startsWith("<<") && !operator.startsWith("<<<")) {
        while (i < n && (text[i] === " " || text[i] === "\t")) i += 1;
        let delimiter = "";
        while (i < n && !/[\s;&|<>()]/.test(text[i])) {
          if (text[i] === "'" || text[i] === '"') {
            const end = text.indexOf(text[i], i + 1);
            delimiter += text.slice(i + 1, end < 0 ? n : end);
            i = end < 0 ? n : end + 1;
          } else if (text[i] === "\\") {
            delimiter += text[i + 1] ?? "";
            i += 2;
          } else delimiter += text[i++];
        }
        if (delimiter !== "") heredocs.push({ delimiter, strip: operator === "<<-" });
      } else {
        redirect = true;
      }
    } else if (c === "\n") {
      op("\n");
      i += 1;
      skipHeredocs();
    } else if (c === ";") {
      op(";");
      i += next === ";" ? 2 : 1;
    } else if (c === "&") {
      op(next === "&" ? "&&" : "&");
      i += next === "&" ? 2 : 1;
    } else if (c === "|") {
      op(next === "|" ? "||" : "|");
      i += next === "|" || next === "&" ? 2 : 1;
    } else if (c === "(" || c === ")") {
      op(c);
      i += 1;
    } else if (c === " " || c === "\t" || c === "\r") {
      const wasRedirect = redirect && parts === null;
      endWord();
      redirect = wasRedirect;
      i += 1;
    } else {
      lit(c);
      i += 1;
    }
  }
  endWord();
  return tokens;
};

// ---------------------------------------------------------------------------------------
// The command's structure: lists of and-or chains of pipelines of commands or subshells.
// ---------------------------------------------------------------------------------------
export const parse = (tokens) => {
  let at = 0;
  const peek = () => tokens[at];
  const list = (inside) => {
    const items = [];
    for (;;) {
      while (peek() && ["\n", ";", "&"].includes(peek().op)) at += 1;
      if (!peek() || (inside && peek().op === ")")) return items;
      if (peek().op === ")") {
        at += 1; // a ")" with no "(" (a case pattern): skipped
        continue;
      }
      const chain = andOr(inside);
      const sep = peek()?.op === "&" ? "&" : ";";
      items.push({ chain, sep });
    }
  };
  const andOr = (inside) => {
    const steps = [{ op: null, pipeline: pipeline(inside) }];
    while (peek() && (peek().op === "&&" || peek().op === "||")) {
      const op = tokens[at++].op;
      while (peek()?.op === "\n") at += 1;
      steps.push({ op, pipeline: pipeline(inside) });
    }
    return steps;
  };
  const pipeline = (inside) => {
    const elements = [element(inside)];
    while (peek()?.op === "|") {
      at += 1;
      while (peek()?.op === "\n") at += 1;
      elements.push(element(inside));
    }
    return elements;
  };
  const element = (inside) => {
    if (peek()?.op === "(") {
      at += 1;
      const inner = list(true);
      if (peek()?.op === ")") at += 1;
      const redirects = [];
      while (peek()?.word) redirects.push(tokens[at++]);
      return { subshell: inner, words: redirects };
    }
    const words = [];
    while (peek()?.word) words.push(tokens[at++]);
    return { words, inside };
  };
  return list(false);
};
