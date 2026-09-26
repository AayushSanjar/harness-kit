#!/usr/bin/env node
// Secrets guard. Two modes:
//
//   PreToolUse hook (default): reads the hook input on stdin and refuses, with
//   permissionDecision "deny", a tool call that would put a secret in the repository.
//   `node guard-secrets.mjs --scan`: checks every git-tracked file in the current
//   repository, prints one line per finding (file and rule, never the value), and
//   exits 1 on any finding, 0 on none. For CI.
//
// A secret reaches history at two different moments, so both are hooked:
//   AUTHORING — Write/Edit/MultiEdit/NotebookEdit creating a secret-shaped file, or
//               writing secret-shaped content into any file
//   STAGING   — `git add` (or `git commit -a`) in a Bash command recording a file
//               that was written earlier, possibly for a good reason
//
// WHY THE BASH MATCHER HAS NO `if:` GATE. `if: "Bash(git add*)"` is a prefix rule and
// misses `git add -A && git commit -m wip`, which is the realistic form. This script
// finds the trigger itself by splitting the command on shell separators, and exits in
// a few milliseconds when there is none. A guard that appears configured but never
// fires is indistinguishable from one that works; a few milliseconds per Bash call is
// the cheaper mistake.
//
// WHAT THIS IS NOT. It is a denylist of shapes, so it catches only the shapes someone
// thought of: the JWT rule below was added after a live token sat in a tracked file,
// unmatched by every other rule. It does not see files written by Bash (heredocs,
// redirects, scripts), only the `git add` that would record them. A clean result
// reduces the chance of an accident; it does not certify that a repository is clean.
import { execFileSync } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { basename, isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const SELF = fileURLToPath(import.meta.url);
const MAX_READ_BYTES = 1_000_000;

// ---------------------------------------------------------------------------
// What counts as a secret
// ---------------------------------------------------------------------------

// PATHS. Matched on the basename.
const PATH_RULES = [
  {
    name: "a .env file",
    // .env, .env.local, .env.production, but NOT .env.example / .sample / .template,
    // which are templates and are meant to be committed.
    test: (base) => /^\.env(\..+)?$/.test(base) && !/\.(example|sample|template)$/i.test(base),
  },
  { name: "a private key file", test: (base) => /\.(pem|key|p12|pfx|jks|keystore)$/i.test(base) },
  { name: "an SSH private key", test: (base) => /^id_(rsa|ed25519|ecdsa|dsa)$/.test(base) },
  { name: "a credential file", test: (base) => /^(\.npmrc|\.netrc|credentials)$/.test(base) },
];

// DIRECTORIES. Dependencies and build output do not belong in history, and are where a
// tool-written credential most often hides. Matched on path segments relative to the
// repository, so a checkout that happens to live under ~/build/ is not caught.
const DIR_RULES = [
  { name: "a node_modules folder", dir: "node_modules" },
  { name: "a build output folder", dir: "dist" },
  { name: "a build output folder", dir: "build" },
];

// CONTENT. Secret SHAPES, never secret WORDS. Code says `key` and docs discuss tokens,
// keys and .env in prose; a rule matching the word would block ordinary edits, get
// switched off within a day, and protect nothing. Each rule matches a structure a real
// credential has and English does not.
//
// The patterns are written so this file does not match itself: each needs literal
// credential characters where the source here has a `[`, `(` or `|`. That is checked,
// not assumed: `--scan` over this repository includes this file.
const CONTENT_RULES = [
  { name: "a PEM private key block", re: /-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----/ },
  { name: "an Atlassian API token", re: /ATATT3x[A-Za-z0-9_=-]{20,}/ },
  { name: "a GitHub token", re: /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b/ },
  { name: "a GitHub fine-grained PAT", re: /\bgithub_pat_[A-Za-z0-9_]{30,}\b/ },
  { name: "an Anthropic API key", re: /\bsk-ant-[A-Za-z0-9_-]{20,}/ },
  { name: "a Slack token", re: /\bxox[baprs]-[A-Za-z0-9-]{10,}/ },
  { name: "an AWS access key id", re: /\bAKIA[0-9A-Z]{16}\b/ },
  { name: "a Google API key", re: /\bAIza[0-9A-Za-z_-]{35}\b/ },
  // Three base64url segments separated by dots, the first starting with the encoding of
  // `{"`. Added after a tool-written session token in a tracked file matched none of
  // the rules above: a shape denylist only catches shapes someone thought of, so path
  // rules and .gitignore have to carry the weight this cannot.
  { name: "a JWT (JSON Web Token)", re: /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/ },
];

// Credentials with no recognisable prefix: a secret-ish NAME assigned a long QUOTED
// value. Code and config files only; prose uses these words and never has this shape.
const GENERIC_RE =
  /\b(api[_-]?key|apikey|secret|password|passwd|token|private[_-]?key)\b\s*[:=]\s*['"`][^'"`\n]{16,}['"`]/i;
const CODE_EXT = /\.(js|jsx|mjs|cjs|ts|tsx|json|ya?ml|sh|env)$/i;

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

// `repoPath` is relative to the repository, or null when the file is outside it, in
// which case only the basename rules apply.
const pathProblem = (fileName, repoPath) => {
  const base = basename(fileName);
  for (const rule of PATH_RULES) if (rule.test(base)) return rule.name;
  if (repoPath !== null) {
    const parts = repoPath.split(/[\\/]/);
    for (const rule of DIR_RULES) if (parts.includes(rule.dir)) return rule.name;
  }
  return null;
};

// Returns { name, line } for the first match, or null. `line` is 1-based.
const contentProblem = (filePath, text) => {
  if (typeof text !== "string" || text === "") return null;
  const lineOf = (index) => text.slice(0, index).split("\n").length;
  for (const rule of CONTENT_RULES) {
    const m = rule.re.exec(text);
    if (m) return { name: rule.name, line: lineOf(m.index) };
  }
  if (CODE_EXT.test(filePath)) {
    const m = GENERIC_RE.exec(text);
    if (m) return { name: "a credential assigned to a named variable", line: lineOf(m.index) };
  }
  return null;
};

// Returns the file's text, or a reason it was not read.
const readForCheck = (absPath) => {
  try {
    const size = statSync(absPath).size;
    if (size > MAX_READ_BYTES) return { skipped: `larger than ${MAX_READ_BYTES} bytes, content not checked` };
    return { text: readFileSync(absPath, "utf8") };
  } catch (error) {
    return { skipped: `could not be read (${error.code ?? error.message}), content not checked` };
  }
};

const git = (args, cwd) => execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

// Is this path already covered by .gitignore? `git check-ignore -q` exits 0 when it IS
// ignored. Used only to make the message honest, never to decide the block.
const isGitIgnored = (repoPath, top) => {
  try {
    execFileSync("git", ["check-ignore", "-q", "--", repoPath], { cwd: top, stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
};

// ---------------------------------------------------------------------------
// --scan: every tracked file in the current repository
// ---------------------------------------------------------------------------

if (process.argv.includes("--scan")) {
  let top;
  let files;
  try {
    top = git(["rev-parse", "--show-toplevel"], process.cwd()).trim();
    files = git(["ls-files", "-z"], top).split("\0").filter(Boolean);
  } catch (error) {
    // Not a clean result: nothing was scanned, so say so and fail.
    process.stderr.write(`guard-secrets --scan: could not list tracked files: ${error.message.trim()}\n`);
    process.exit(2);
  }

  let findings = 0;
  for (const file of files) {
    let problem = pathProblem(file, file);
    let where = file;
    if (!problem) {
      const read = readForCheck(resolve(top, file));
      if (read.skipped) {
        process.stderr.write(`guard-secrets --scan: ${file} ${read.skipped}\n`);
        continue;
      }
      const hit = contentProblem(file, read.text);
      if (hit) {
        problem = hit.name;
        where = `${file}:${hit.line}`;
      }
    }
    if (problem) {
      findings += 1;
      console.log(`FINDING ${where}: ${problem}`);
    }
  }
  console.log(`guard-secrets --scan: ${files.length} tracked files, ${findings} finding(s)`);
  process.exit(findings > 0 ? 1 : 0);
}

// ---------------------------------------------------------------------------
// `git add` and `git commit -a`: ask git what it would ACTUALLY record
// ---------------------------------------------------------------------------

// Pattern-matching the command is not enough: `git add -A`, `git add .` and
// `git commit -a` are the dangerous forms and none of them names the file it records.
//
// Global options before the subcommand (`git -C dir add .`, `git -c k=v commit -a`) are
// passed through to the dry run, so it probes the repository the command would touch.
// KNOWN LIMITATION: a `cd dir && git add .` earlier in the command is not followed; the
// probe runs in the session's directory. From a repository's root that over-reports
// (noisy), from a sibling repository it probes the wrong one (silent). Rare form.
const GIT_OPTIONS_WITH_VALUE = new Set(["-C", "-c", "--git-dir", "--work-tree", "--namespace"]);

const pathsThisCommandWouldRecord = (command, cwd) => {
  const segments = command.split(/&&|\|\||[;\n|]/); // shell separators
  const results = [];

  for (const segment of segments) {
    const trimmed = segment.trim();
    if (!/^git\b/.test(trimmed)) continue;

    // Tokenise, keeping quoted strings whole, then strip the quotes.
    const tokens = (trimmed.match(/'[^']*'|"[^"]*"|\S+/g) ?? []).map((t) => t.replace(/^['"]|['"]$/g, ""));

    // The subcommand is the first token after `git` that is not a global option.
    let i = 1;
    while (i < tokens.length && tokens[i].startsWith("-")) i += GIT_OPTIONS_WITH_VALUE.has(tokens[i]) ? 2 : 1;
    const globals = tokens.slice(1, i);
    const subcommand = tokens[i];
    const args = tokens.slice(i + 1).filter((a) => a !== "--dry-run" && a !== "-n");
    if (subcommand !== "add" && subcommand !== "commit") continue;

    let top;
    try {
      top = git([...globals, "rev-parse", "--show-toplevel"], cwd).trim();
    } catch {
      return { undetermined: trimmed };
    }

    if (subcommand === "add") {
      try {
        // Lines look like: add 'src/app.js'. Paths are relative to the repository root.
        const out = git([...globals, "add", "--dry-run", ...args], cwd);
        for (const line of out.split("\n")) {
          const m = line.match(/^add '(.*)'$/);
          if (m) results.push({ path: m[1], top });
        }
      } catch {
        // Could not determine what would be staged. Do not guess in either direction.
        return { undetermined: trimmed };
      }
    } else if (subcommand === "commit") {
      // `git commit -a` stages and commits in one step without `git add`. It is what
      // gets typed in a hurry, which is when this matters most.
      let out;
      try {
        out = git([...globals, "commit", "--dry-run", "--porcelain", ...args], cwd);
      } catch (error) {
        // `git commit --dry-run` exits 1 when there is nothing to commit but still prints
        // its report, so stdout is authoritative and a non-zero exit is not a failure.
        out = typeof error?.stdout === "string" ? error.stdout : null;
      }
      if (out === null) return { undetermined: trimmed };

      for (const line of out.split("\n")) {
        // Porcelain v1 is `XY path`, where X is the INDEX column: what would actually be
        // committed. ` M file` (worktree only) and `?? file` (untracked) would not be.
        const m = line.match(/^([MADRCU])[MADRCU? ] (.+)$/);
        if (m && m[1] !== "D") {
          const path = m[2].includes(" -> ") ? m[2].split(" -> ").pop() : m[2];
          results.push({ path, top });
        }
      }
    }
  }
  return { paths: results };
};

// ---------------------------------------------------------------------------
// Hook protocol
// ---------------------------------------------------------------------------

// Emitting nothing on the pass path is deliberate: permissionDecision "allow" would
// skip the normal permission prompts. This hook only ever adds a refusal.
const allow = () => process.exit(0);

const decide = (permissionDecision, permissionDecisionReason) => {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision, permissionDecisionReason },
    }),
  );
  process.exit(0);
};

let input;
try {
  input = JSON.parse(readFileSync(0, "utf8"));
} catch (error) {
  // Never block because the hook could not read its input, but never pass silently
  // either: exit 1 lets the tool call proceed and shows this line to the person.
  process.stderr.write(`harness-kit guard-secrets: could not read hook input (${error.message}); nothing was checked\n`);
  process.exit(1);
}

const toolName = input?.tool_name ?? "";
const toolInput = input?.tool_input ?? {};
const cwd = input?.cwd || process.cwd();
const projectDir = process.env.CLAUDE_PROJECT_DIR || cwd;

if (/^(Write|Edit|MultiEdit|NotebookEdit)$/.test(toolName)) {
  const filePath = toolInput.file_path ?? toolInput.notebook_path ?? "";
  // Write sends content; Edit new_string; MultiEdit an edits array; NotebookEdit new_source.
  const written = [
    toolInput.content,
    toolInput.new_string,
    toolInput.new_source,
    ...(Array.isArray(toolInput.edits) ? toolInput.edits.map((e) => e?.new_string) : []),
  ]
    .filter((s) => typeof s === "string")
    .join("\n");

  const rel = relative(projectDir, resolve(cwd, filePath));
  const repoPath = rel.startsWith("..") || isAbsolute(rel) ? null : rel;

  const byPath = pathProblem(filePath, repoPath);
  if (byPath) {
    decide(
      "deny",
      `BLOCKED by harness-kit guard-secrets (never put secrets in the repository).\n\n  ${filePath}\n  is ${byPath}.\n\n` +
        `Nothing was written. If this file must exist, create it outside the repository, or ask the person ` +
        `to write it themselves. Do not work around this guard silently.`,
    );
  }

  const byContent = contentProblem(filePath, written);
  if (byContent) {
    decide(
      "deny",
      `BLOCKED by harness-kit guard-secrets (never put secrets in the repository).\n\n  The content being written to ${filePath}\n` +
        `  contains what looks like ${byContent.name}.\n\n` +
        `Nothing was written. The value itself is not shown here on purpose. If this is a false positive, ` +
        `the pattern lives in ${SELF} and should be narrowed rather than the guard disabled.`,
    );
  }
  allow();
}

if (toolName === "Bash") {
  const command = toolInput.command ?? "";
  if (!/\bgit\b[^\n;&|]*\b(?:add|commit)\b/.test(command)) allow(); // fast exit: the common case

  const staged = pathsThisCommandWouldRecord(command, cwd);
  if (staged.undetermined) {
    decide(
      "ask",
      `harness-kit guard-secrets could not determine what this command would record, so it cannot check it for secrets:\n\n` +
        `  ${staged.undetermined}\n\n` +
        `The git --dry-run probe failed. Approve only if you know what it records.`,
    );
  }

  const problems = [];
  const unchecked = [];
  for (const { path, top } of staged.paths ?? []) {
    let why = pathProblem(path, path);
    if (!why) {
      // Also read the file: a secret at an innocent path is the case this is really for.
      const read = readForCheck(resolve(top, path));
      if (read.skipped) unchecked.push(`  ${path} ${read.skipped}`);
      else why = contentProblem(path, read.text)?.name ?? null;
    }
    if (why) problems.push({ path, why, ignored: isGitIgnored(path, top) });
  }

  if (problems.length > 0) {
    const lines = problems.map(({ path, why, ignored }) => {
      // Reported both ways round on purpose. If .gitignore already covered it, this
      // guard is belt to existing braces and -f was used. If it did not, the ignore rule
      // is the actual bug, and leaving it relies on this guard for every other tool.
      const note = ignored
        ? ".gitignore already covers this; it is only reachable because -f was used"
        : "NOT covered by .gitignore; that is the thing to fix, not this guard";
      return `  ${path}\n    ${why}\n    ${note}`;
    });
    decide(
      "deny",
      `BLOCKED by harness-kit guard-secrets (never put secrets in the repository).\n\n` +
        `This command would stage or commit:\n\n${lines.join("\n\n")}\n\n` +
        `Nothing was staged or committed, and no path was silently dropped from your command. Decide whether ` +
        `each file should exist at all, or merely not be tracked, and run it again yourself.` +
        (unchecked.length > 0 ? `\n\nAlso not content-checked:\n${unchecked.join("\n")}` : ""),
    );
  }
  if (unchecked.length > 0) {
    // Allowed, but a file whose content was not checked is said out loud, not passed.
    process.stderr.write(`harness-kit guard-secrets: not content-checked:\n${unchecked.join("\n")}\n`);
    process.exit(1);
  }
  allow();
}

allow();
