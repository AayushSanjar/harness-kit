#!/usr/bin/env node
// PreToolUse hook on Bash: keep Claude's git and the person's steps out of the real working
// tree. Claude may commit (the commit-msg hook checks the message); it never pushes, never
// throws work away, and never runs the person's scripts.
//
// DENIED, anywhere but a scratch copy (below):
//   - git push, of any kind (--force, --dry-run, a tag, a deletion);
//   - destructive git: git reset --hard, git checkout with "--" and a path after it
//     (git checkout -- <path>, git checkout <ref> -- <path>), git checkout . (any checkout
//     naming "."), git checkout -f/--force (alone or in a cluster), git restore (any form),
//     git clean with -f or --force (alone or in a cluster such as -fd), git branch -D (or
//     --delete/-d with --force/-f), git stash drop, git stash clear, and git rebase (any
//     form: it rewrites history, and an interactive one cannot run in Claude's shell);
//   - running land.sh, ship.sh, release.sh, upgrade.sh, approve-protected.sh or
//     approve-brief.sh (by path, or through bash, sh, zsh, dash, ksh, source or "."): they
//     are the person's steps (approve-brief.sh is the person approving the brief that
//     /harness-kit:brief wrote; it also refuses without a terminal);
//   - any command with a word naming a brief's approval, a path ending in ".brief.approved"
//     (as an argument, a redirection's target or an assignment's value, in full or with an
//     unknown folder in front, such as "$R/x.brief.approved", or a glob such as
//     *.brief.approved), when that path is not in a scratch copy: a redirect, cp, tee, mv,
//     rm or even cat. Only approve-brief.sh, the person's, writes an approval; Claude reads
//     one with the Read tool. A word with whitespace in it (a commit message that mentions
//     one) is not a path. brief-guard.mjs denies the same files to Write, Edit, MultiEdit
//     and NotebookEdit;
//   - the same, for a word naming the Stop hook's pass record, a file named
//     "stop-gate-pass" (<git dir>/harness-kit/stop-gate-pass, guard-lib.mjs): only the Stop
//     hook writes it, and a record written by anything else would let a stop skip the
//     check.
// Everything else is left alone: nothing is printed, so the normal permission flow
// decides. `git commit` is allowed.
//
// A SCRATCH COPY is a folder strictly under the OS temp folder (guard-lib.mjs, shared with
// brief-guard.mjs: os.tmpdir(), /tmp, or either one's real path, with symbolic links
// resolved). A denied command is allowed there, so tests and experiments in throwaway
// clones still work. A project kept under the temp folder is not guarded.
//
// WHERE A COMMAND RUNS. The hook input's cwd (Claude's shell folder), changed by what the
// command itself does before it: `cd` and `pushd` (`cd` alone is $HOME; `cd -` is unknown),
// `git -C <path>`, `--git-dir`/`--work-tree`, `bash -c '...'`/`sh -c`, `eval`, `$(...)` and
// backticks (run where the command around them runs), `( ... )` subshells (their `cd` ends
// with them), and pipelines and `&` (a `cd` there changes nothing after it). The hook
// keeps EVERY folder a command might run in: a `cd` that might fail (`cd x; git push`,
// or a `cd` after `||`) leaves the old folder possible too, while `cd x && git push` runs
// the push only in x. A denied command is allowed only when every possible folder is a
// scratch copy. A folder it cannot work out (an unknown variable, `cd -`) counts as the
// real working tree. Variables it knows: HOME, TMPDIR, PWD (when there is one folder),
// and those the command assigns with a known value (NAME=value on its own, or export),
// including NAME=$(mktemp ...), a path under the temp folder unless mktemp is given one.
// Quotes, escapes, comments and heredoc bodies are read as the shell reads them, so a
// commit message that mentions `git push` is not a push. The reading (tokenize, then parse)
// is guard-lib.mjs's, shared with background-guard.mjs.
//
// WHAT THIS IS NOT. It reads command TEXT, as predeploy-gate.mjs does: an alias, a git
// alias, a script that pushes, or a variable holding the command name are not seen. It
// stops mistakes, not a determined process. The person's own terminal is not affected.
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { APPROVAL_REASON, PASS_REASON, TEMP_ROOTS, isApproval, isPassRecord, isScratch, parse, tokenize } from "./guard-lib.mjs";

const SCRIPTS = new Set(["land.sh", "ship.sh", "release.sh", "upgrade.sh", "approve-protected.sh", "approve-brief.sh"]);
const SHELLS = new Set(["bash", "sh", "zsh", "dash", "ksh"]);
const RESERVED = new Set(["!", "{", "}", "if", "then", "elif", "else", "fi", "do", "done", "while", "until", "time"]);
const SKIPPED = new Set(["for", "case", "esac", "select", "function", "in"]);
const UNKNOWN = null;

// Never block because the hook could not read its input: exit 1 lets the call proceed and
// shows the line to the person.
let input;
try {
  input = JSON.parse(readFileSync(0, "utf8"));
} catch (error) {
  process.stderr.write(`harness-kit git-guard: could not read hook input (${error.message}); nothing was checked\n`);
  process.exit(1);
}
if ((input?.tool_name ?? "") !== "Bash") process.exit(0);
const command = String(input?.tool_input?.command ?? "");
const HOME = process.env.HOME || homedir();

// ---------------------------------------------------------------------------------------
// Words, tokens and the command's structure: guard-lib.mjs's tokenize and parse (shared with
// background-guard.mjs).
// ---------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------
// Evaluation: the set of folders each command may run in.
// ---------------------------------------------------------------------------------------
const union = (...sets) => new Set(sets.flatMap((s) => [...s]));
const denials = [];

const valueOf = (parts, dirs, vars) => {
  let value = "";
  for (const part of parts) {
    if ("lit" in part) value += part.lit;
    else if (part.tilde) value += HOME;
    else if (part.unknown) return UNKNOWN;
    else if ("sub" in part) {
      const mktemp = mktempValue(part.sub, dirs, vars);
      if (mktemp === UNKNOWN) return UNKNOWN;
      value += mktemp;
    } else if ("variable" in part) {
      let v = vars.has(part.variable) ? vars.get(part.variable) : undefined;
      if (v === undefined && part.variable === "PWD" && dirs.size === 1) v = [...dirs][0];
      if (v === undefined || v === "") v = part.fallback;
      if (v === undefined || v === UNKNOWN) return UNKNOWN;
      value += v;
    }
  }
  return value;
};

// The output of a $(...) that is a plain mktemp call: a path under the temp folder (or
// under the template's folder when one is given); UNKNOWN for anything else.
const mktempValue = (text, dirs, vars) => {
  const commands = parse(tokenize(text));
  if (commands.length !== 1 || commands[0].chain.length !== 1 || commands[0].chain[0].pipeline.length !== 1) return UNKNOWN;
  const words = (commands[0].chain[0].pipeline[0].words ?? []).filter((w) => !w.redirect).map((w) => valueOf(w.word, dirs, vars));
  if (words[0] !== "mktemp" || words.includes(UNKNOWN)) return UNKNOWN;
  let base = process.env.TMPDIR || "/tmp";
  let template = null;
  for (let k = 1; k < words.length; k += 1) {
    const w = words[k];
    if (w === "-p" || w === "--tmpdir") base = words[++k] ?? base;
    else if (w.startsWith("--tmpdir=")) base = w.slice("--tmpdir=".length);
    else if (w === "-t") k += 1;
    else if (!w.startsWith("-")) template = w;
  }
  if (template !== null && (isAbsolute(template) || template.includes("/"))) {
    if (!isAbsolute(template)) return UNKNOWN;
    return template;
  }
  return join(base, template ?? "tmp.mktemp");
};

// The file name a word ends in, when that much is known even if the folder is not
// ("$PLUGIN/scripts/ship.sh" ends in ship.sh); UNKNOWN otherwise.
const baseOf = (parts, value) => {
  if (value !== UNKNOWN) return basename(value);
  const last = parts[parts.length - 1];
  return last && "lit" in last && last.lit.includes("/") ? last.lit.slice(last.lit.lastIndexOf("/") + 1) : UNKNOWN;
};

const ASSIGNMENT = /^([A-Za-z_][A-Za-z0-9_]*)=/;

// Leading assignments and reserved words off, then wrappers (env, sudo, command, ...) off.
// Returns the index of the word that names the command.
const commandStart = (values) => {
  let k = 0;
  const skipOptions = (withArgument) => {
    while (k < values.length && values[k] !== UNKNOWN && values[k].startsWith("-") && values[k] !== "-") {
      const option = values[k++];
      if (option === "--") break;
      if (withArgument.includes(option)) k += 1;
    }
  };
  for (;;) {
    const w = values[k];
    if (w === undefined) return k;
    if (w !== UNKNOWN && (ASSIGNMENT.test(w) || RESERVED.has(w))) {
      k += 1;
      continue;
    }
    if (w === "command" || w === "builtin" || w === "nohup" || w === "exec") {
      k += 1;
      skipOptions(["-a"]);
    } else if (w === "env") {
      k += 1;
      skipOptions(["-u", "-C", "-S"]);
      while (k < values.length && values[k] !== UNKNOWN && ASSIGNMENT.test(values[k])) k += 1;
    } else if (w === "sudo") {
      k += 1;
      skipOptions(["-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U"]);
    } else if (w === "nice") {
      k += 1;
      skipOptions(["-n"]);
    } else if (w === "timeout") {
      k += 1;
      skipOptions(["-s", "-k"]);
      k += 1; // the duration
    } else if (w === "xargs") {
      k += 1;
      skipOptions(["-n", "-I", "-L", "-P", "-d", "-E", "-s", "-a"]);
    } else {
      return k;
    }
  }
};

const GIT_VALUE_OPTIONS = new Set(["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env", "--exec-path"]);

// Which rule a git command breaks, if any: { rule, what }.
const gitRule = (args) => {
  const [sub, ...rest] = args;
  const short = (letter) => rest.some((a) => a !== UNKNOWN && new RegExp(`^-[A-Za-z]*${letter}`).test(a));
  const has = (word) => rest.includes(word);
  if (sub === "push") return { rule: "push", what: "git push" };
  if (sub === "reset" && has("--hard")) return { rule: "destructive", what: "git reset --hard" };
  if (sub === "checkout" && rest.indexOf("--") >= 0 && rest.indexOf("--") < rest.length - 1) return { rule: "destructive", what: "git checkout -- <path>" };
  if (sub === "checkout" && has(".")) return { rule: "destructive", what: "git checkout ." };
  if (sub === "checkout" && (has("--force") || short("f"))) return { rule: "destructive", what: "git checkout -f" };
  if (sub === "stash" && (rest[0] === "drop" || rest[0] === "clear")) return { rule: "destructive", what: `git stash ${rest[0]}` };
  if (sub === "rebase") return { rule: "destructive", what: "git rebase" };
  if (sub === "restore") return { rule: "destructive", what: "git restore" };
  if (sub === "clean" && (has("--force") || short("f"))) return { rule: "destructive", what: "git clean -f" };
  if (sub === "branch" && (short("D") || ((has("--delete") || short("d")) && (has("--force") || short("f"))))) {
    return { rule: "destructive", what: "git branch -D" };
  }
  return null;
};

const REASONS = {
  push: "Claude never pushes: the person pushes, through ship.sh (or release.sh), after the review and CI.",
  destructive: "it throws work away in the real working tree. If it is needed, put the exact command in the report's \"Your commands\" for the person to run.",
  script: "it is the person's step, run in their own terminal. Put the exact command in the report's \"Your commands\".",
  approval: APPROVAL_REASON,
  pass: PASS_REASON,
};

const deny = (rule, what, dirs, text) => {
  const where = [...dirs].map((d) => (d === UNKNOWN ? "(a folder the hook cannot work out)" : d)).join(", ");
  denials.push(
    `BLOCKED by harness-kit git-guard: \`${what}\` in ${where}, not a scratch copy under the OS temp folder (${TEMP_ROOTS.join(", ")}): ` +
      `${REASONS[rule]}\n  command: ${text}`,
  );
};

const resolveIn = (dirs, target) =>
  new Set([...dirs].map((d) => (target === UNKNOWN ? UNKNOWN : isAbsolute(target) ? resolve(target) : d === UNKNOWN ? UNKNOWN : resolve(d, target))));

// A simple command in DIRS. Returns { ok, fail }: the folders after it succeeds or fails.
const runCommand = (element, dirs, vars, inPipeline) => {
  const same = { ok: dirs, fail: dirs };
  // Substitutions run first, where the command runs.
  for (const token of element.words) {
    for (const part of token.word) if ("sub" in part) runList(parse(tokenize(part.sub)), dirs, new Map(vars));
  }
  const args = element.words.filter((t) => !t.redirect);
  const values = args.map((t) => valueOf(t.word, dirs, vars));
  const text = values.map((v) => (v === UNKNOWN ? "?" : v)).join(" ");

  // A word naming a brief's approval or the Stop hook's pass record (an argument, a
  // redirection's target, an assignment's value), anywhere but a scratch copy.
  for (const token of element.words) {
    const whole = valueOf(token.word, dirs, vars);
    const value = whole !== UNKNOWN && ASSIGNMENT.test(whole) ? whole.replace(ASSIGNMENT, "") : whole;
    const name = baseOf(token.word, value);
    if (name === UNKNOWN || /\s/.test(name) || (value !== UNKNOWN && /\s/.test(value))) continue;
    const rule = isApproval(name) ? "approval" : isPassRecord(name) ? "pass" : null;
    if (rule === null) continue;
    const paths = resolveIn(dirs, value);
    if (![...paths].every(isScratch)) deny(rule, `a command naming ${value === UNKNOWN ? `.../${name}` : value}`, paths, text);
  }

  // NAME=value alone (or export NAME=value): remembered.
  const assignments = values[0] === "export" ? values.slice(1) : values;
  if (!inPipeline && assignments.length > 0 && assignments.every((v) => v !== UNKNOWN && ASSIGNMENT.test(v))) {
    element.words
      .filter((t) => !t.redirect)
      .slice(values[0] === "export" ? 1 : 0)
      .forEach((token) => {
        const raw = token.word;
        const name = ASSIGNMENT.exec(raw[0]?.lit ?? "")?.[1];
        if (!name) return;
        const first = { lit: raw[0].lit.slice(name.length + 1) };
        vars.set(name, valueOf([first, ...raw.slice(1)], dirs, vars));
      });
    return same;
  }
  if (values[0] === "export") return same;

  const first = commandStart(values);
  const words = values.slice(first);
  const bases = args.slice(first).map((t, k) => baseOf(t.word, words[k]));
  if (words.length === 0 || bases[0] === UNKNOWN || SKIPPED.has(words[0])) return same;
  const name = bases[0];

  if (name === "cd" || name === "pushd") {
    const args = words.slice(1).filter((w) => w === UNKNOWN || !/^-[LPe@]+$/.test(w));
    const target = args.length === 0 ? HOME : args[0] === "-" ? UNKNOWN : args[0];
    if (inPipeline) return same;
    return { ok: resolveIn(dirs, target), fail: dirs };
  }
  if (name === "popd") return inPipeline ? same : { ok: new Set([UNKNOWN]), fail: dirs };

  if (name === "git") {
    let where = dirs;
    let k = 1;
    while (k < words.length && words[k] !== UNKNOWN && words[k].startsWith("-")) {
      const option = words[k];
      const [flag, inline] = option.includes("=") ? [option.slice(0, option.indexOf("=")), option.slice(option.indexOf("=") + 1)] : [option, undefined];
      if (GIT_VALUE_OPTIONS.has(flag)) {
        const value = inline !== undefined ? inline : words[++k];
        if (flag === "-C" || flag === "--work-tree") where = resolveIn(where, value ?? UNKNOWN);
        else if (flag === "--git-dir") where = resolveIn(where, value === undefined || value === UNKNOWN ? UNKNOWN : dirname(resolve(value)));
      }
      k += 1;
    }
    const broken = gitRule(words.slice(k));
    if (broken && ![...where].every(isScratch)) deny(broken.rule, broken.what, where, text);
    return same;
  }

  if (SHELLS.has(name) || name === "source" || name === ".") {
    // -c, alone or in a cluster (-lc): the next word is the command text.
    const c = words.findIndex((a, k) => k > 0 && a !== UNKNOWN && /^-[A-Za-z]*c[A-Za-z]*$/.test(a));
    if (SHELLS.has(name) && c > 0) {
      if (words[c + 1] !== undefined && words[c + 1] !== UNKNOWN) runList(parse(tokenize(words[c + 1])), dirs, new Map(vars));
      return same;
    }
    const script = words.findIndex((a, k) => k > 0 && (a === UNKNOWN || !a.startsWith("-")));
    if (script > 0 && SCRIPTS.has(bases[script]) && ![...dirs].every(isScratch)) deny("script", bases[script], dirs, text);
    return same;
  }
  if (name === "eval") {
    const rest = words.slice(1);
    if (!rest.includes(UNKNOWN)) return runList(parse(tokenize(rest.join(" "))), dirs, vars, true);
    return same;
  }
  if (SCRIPTS.has(name) && ![...dirs].every(isScratch)) deny("script", name, dirs, text);
  return same;
};

const runPipeline = (elements, dirs, vars) => {
  const inPipeline = elements.length > 1;
  let result = { ok: dirs, fail: dirs };
  for (const element of elements) {
    if (element.subshell) {
      runList(element.subshell, dirs, new Map(vars));
      for (const token of element.words) for (const part of token.word) if ("sub" in part) runList(parse(tokenize(part.sub)), dirs, new Map(vars));
    } else {
      result = runCommand(element, dirs, vars, inPipeline);
    }
  }
  return inPipeline || elements[0].subshell ? { ok: dirs, fail: dirs } : result;
};

// Runs ITEMS from DIRS; returns the folders after them (with WITH_RESULT, { ok, fail } of
// the last, for eval).
function runList(items, dirs, vars, withResult = false) {
  let current = dirs;
  let last = { ok: dirs, fail: dirs };
  for (const { chain, sep } of items) {
    let { ok, fail } = runPipeline(chain[0].pipeline, current, vars);
    for (const step of chain.slice(1)) {
      if (step.op === "&&") {
        const r = runPipeline(step.pipeline, ok, vars);
        ok = r.ok;
        fail = union(fail, r.fail);
      } else {
        const r = runPipeline(step.pipeline, fail, vars);
        ok = union(ok, r.ok);
        fail = r.fail;
      }
    }
    last = { ok, fail };
    if (sep !== "&") current = union(ok, fail);
  }
  return withResult ? last : current;
}

const start = input?.cwd || process.cwd();
const vars = new Map([["HOME", HOME]]);
if (process.env.TMPDIR) vars.set("TMPDIR", process.env.TMPDIR);
runList(parse(tokenize(command)), new Set([resolve(start)]), vars);

if (denials.length === 0) process.exit(0);
process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: [...new Set(denials)].join("\n"),
    },
  }) + "\n",
);
process.exit(0);
