#!/usr/bin/env node
// CI check: the branch's commit messages give a reason for every protected file changed and
// a source for every number they state, and none claims a removed path as a decision. The
// same rules, for one message about to be committed: the commit-msg hook.
//
//   node check-commits.mjs          one PASS or FAIL line, then one line per finding; exit 0 or 1
//   node check-commits.mjs --warn   the same findings under a WARN line; always exit 0
//   node check-commits.mjs --message FILE
//                                   check FILE as the message of the commit about to be made
//                                   from the staged changes (THE MESSAGE MODE, below); with
//                                   GIT_INDEX_FILE set, from that index
//
// RECOMMENDED: --warn. Put `node <plugin>/scripts/check-commits.mjs --warn` in the project's
// check.sh and CI, and enforce (drop --warn) only after 3 branches whose messages were
// written from Claude's commit drafts (.reports/<branch>.commit.txt) show no false findings.
// Replayed on a real project's reviewed history, enforcing from the start would have failed
// branches its reviewer passed, over commit messages written by hand. The commit-msg hook
// (install-hooks.sh) enforces the message mode from the start: it judges only what the new
// message adds (below), so a finding there is the new commit's own.
//
// Run from anywhere inside the project's git repository, in the project's check.sh and in
// CI. The commits checked are those from the merge-base with the review base to HEAD: the
// base is .harness/review-base at HEAD (first line, default main), locally or as
// origin/<base>, as check-reviewed.mjs finds it. A branch with no commits passes.
//
// REPLAY SNAPSHOTS ARE EXEMPT, IN A REPLAY ONLY. replay-faults.sh checks the project in a
// snapshot of the working tree, a commit whose message starts "harness-kit replay-faults:",
// and sets HARNESS_KIT_REPLAY=1 for the check it runs there. Only with HARNESS_KIT_REPLAY=1
// set is such a commit exempt: its message is not checked, and when such commits are the
// newest on HEAD (as a snapshot always is), what they change is left out too: the branch is
// checked as it was up to the newest commit that is not one. An exempt commit anywhere
// else only has its message skipped. Without HARNESS_KIT_REPLAY=1 (a person's check, CI),
// a commit with that subject is checked like any other, so committing one on a real branch
// dodges nothing.
//
// IT FAILS on three kinds of finding:
//   (a) A PROTECTED FILE WITHOUT A REASON. A path changed on the branch (added, changed,
//       deleted, either side of a rename) is protected when .harness/protected-paths lists
//       it, at the merge-base or at HEAD, so a branch cannot unprotect a file and change it
//       in one go. One path per line, # comments and blank lines skipped; a line ending in
//       "/" protects everything under that folder. The path must be named in the BODY of at
//       least one commit on the branch (not only the subject): in full, or by its file name
//       when no other file changed on the branch has that file name. A file name with folders
//       in front (specs/a.md) names the file only when they are the end of its real path
//       (.harness/specs/a.md, not lib/a.md). This check cannot judge the reason; the
//       reviewer does.
//   (b) A NUMBER WITHOUT A SOURCE. Every number in a commit's BODY (the subject is not
//       checked) must appear in the branch's diff (its added and removed lines) or in a
//       "Told:" line in any commit body on the branch, as (a) accepts a reason in any body:
//       a later commit can give the source an earlier one left out. A "Told:" line starts
//       "Told:" (after optional indent and a "-" or "*" bullet) and continues onto the
//       lines after it until a blank line or another "Word:" line (a word and a colon at
//       the start, after optional indent and bullet, such as "Breaks:"). A number is a run
//       of digits, with dots between digit groups (0.9.0, 24.04), not touching a letter,
//       digit, "_" or "." on either side, and not after a letter or digit and a "-": so R1,
//       C13, v0.8.0, 9b, 9b-4 and hex hashes such as 4c1bc4d are names, not numbers. A
//       version matches with or without a leading "v": 0.9.0 in a body is sourced by
//       v0.9.0 in the diff or a "Told:" line. A run of 7 or more digits alone that git
//       resolves to a commit (git rev-parse --verify <token>^{commit}, as for 1234567 in
//       "reverts 1234567") is a reference, not a number; a shorter one (a year, a count)
//       is always a number, even when it happens to be the start of a commit's hash. Trailer lines with an e-mail address
//       (Co-Authored-By: Name <mail>) are skipped.
//   (c) A DECISION THAT IS NOT THIS PROJECT'S. A "Decision:" line (after optional indent and
//       bullet; it continues as a "Told:" line does) must not name a path that
//       .harness/removed-paths lists, at the merge-base or at HEAD: the project's decisions
//       index would record a decision about a file this project does not have, as when
//       another project's (harness-kit's) Decision: lines are copied in. The list's format
//       is .harness/protected-paths's; a path is named in full (a folder line, ending "/",
//       by the folder or any path under it), never by its file name alone. Another
//       project's decisions go on "Upstream:" lines, which no rule reads.
//
// THE MESSAGE MODE (--message FILE), for the commit-msg hook that install-hooks.sh
// installs (git sets GIT_INDEX_FILE for the hook when it commits from another index, as
// `git commit -- <path>` does), and for upgrade.sh, which proves its commit draft against a
// temporary index holding the upgrade's changes. FILE is read
// as git leaves it for the hook: lines starting with the comment character
// (core.commentChar, default "#") and everything from a scissors line down are dropped,
// then the subject is the first paragraph and the body the rest. The commits on the branch
// so far (from the merge-base to HEAD) and the staged changes are the branch; the new
// message is judged against it, and only what the new commit adds can fail:
//   (a) each protected path that the staged changes change (against HEAD) must be named in
//       the new body or in any body on the branch so far;
//   (b) each number in the new body must be in the diff from the merge-base to the staged
//       changes, or on a "Told:" line in the new body or any body on the branch so far;
//   (c) no "Decision:" line in the new body may name a path in .harness/removed-paths (as
//       it is staged, or at the merge-base).
// Findings in earlier commits are left to the branch check above, so an amend (which the
// hook cannot tell from a new commit) is never refused for the message it replaces. With
// no base branch or no merge-base (a new repository), the staged changes alone are the
// branch. HARNESS_KIT_REPLAY does not apply: replay snapshots are made without hooks.
//
// Each finding names the commit, the path or number, and how to fix it. Rewording a
// message does not change the diff, so a recorded review (check-reviewed.mjs) still holds.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";

const PROTECTED = ".harness/protected-paths";
const REMOVED = ".harness/removed-paths";
const NUMBER = /(?<![\p{L}\p{N}_.])(?<![\p{L}\p{N}]-)\d+(?:\.\d+)*(?![\p{L}\p{N}_]|\.\d)/gu;
// A version with a leading "v" (v0.9.0), as a source for the same version without it.
const V_VERSION = /(?<![\p{L}\p{N}_.])(?<![\p{L}\p{N}]-)v(\d+(?:\.\d+)+)(?![\p{L}\p{N}_]|\.\d)/gu;
const TOLD = /^\s*(?:[-*]\s+)?Told:/;
const DECISION = /^\s*(?:[-*]\s+)?Decision:/;
// Any "Word:" line, which ends a "Told:" or "Decision:" line's continuation.
const WORD_LINE = /^\s*(?:[-*]\s+)?[\p{L}][\p{L}\p{N}_-]*:/u;
const REPLAY_SNAPSHOT = "harness-kit replay-faults:";
const IN_REPLAY = process.env.HARNESS_KIT_REPLAY === "1";
const TRAILER = /^[A-Za-z][A-Za-z0-9-]*:\s.*<[^<>\s]+@[^<>\s]+>\s*$/;
const USAGE = "Usage: node check-commits.mjs [--warn] [--message FILE]";

// Arguments.
let WARN = false;
let MESSAGE = null;
const unknown = [];
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 1) {
  if (argv[i] === "--warn") WARN = true;
  else if (argv[i] === "--message" && i + 1 < argv.length) MESSAGE = argv[++i];
  else unknown.push(argv[i]);
}
if (unknown.length > 0) {
  console.log(`FAIL check-commits: unknown argument ${unknown.join(" ")}. ${USAGE}`);
  process.exit(1);
}

const git = (args, { cwd, allowFail = false } = {}) => {
  const result = spawnSync("git", args, { cwd, encoding: "utf8", maxBuffer: 512 * 1024 * 1024 });
  if (result.status !== 0 && !allowFail) {
    throw new Error(`git ${args.join(" ")} failed: ${(result.stderr || result.error?.message || "").trim()}`);
  }
  return result.status === 0 ? result.stdout : null;
};

const fail = (message) => {
  console.log(`FAIL check-commits: ${message}`);
  process.exit(1);
};

// The base ref and its merge-base with HEAD, as check-reviewed.mjs works them out. Throws
// with a message a person can act on.
const branchState = (root) => {
  const configured = (git(["show", "HEAD:.harness/review-base"], { cwd: root, allowFail: true }) ?? "")
    .split(/\r?\n/)[0]
    .trim();
  const base = configured || "main";
  const baseRef = [base, `origin/${base}`].find(
    (ref) => git(["rev-parse", "--verify", "--quiet", `${ref}^{commit}`], { cwd: root, allowFail: true }) !== null,
  );
  if (!baseRef) {
    throw new Error(`base branch "${base}" not found, locally or as origin/${base} (in CI, check out with fetch-depth: 0)`);
  }
  const mergeBase = git(["merge-base", baseRef, "HEAD"], { cwd: root, allowFail: true })?.trim();
  if (!mergeBase) {
    throw new Error(`no merge-base between ${baseRef} and HEAD (a shallow clone? in CI, check out with fetch-depth: 0)`);
  }
  return { baseRef, mergeBase };
};

// A path list (.harness/protected-paths's format) at REV; REV "" is the index.
const pathList = (root, rev, file) =>
  (git(["show", `${rev}:${file}`], { cwd: root, allowFail: true }) ?? "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line !== "" && !line.startsWith("#"))
    .map((line) => line.replace(/^\.\//, ""));
const listAt = (root, revs, file) => [...new Set(revs.flatMap((rev) => pathList(root, rev, file)))];

const isProtected = (path, list) => list.some((entry) => (entry.endsWith("/") ? path.startsWith(entry) : path === entry));

// True when TEXT names PATH: in full, or, when UNIQUE (no other changed file has its file
// name), by its file name alone or with the folders just above it. Never as part of a
// longer name or word.
const escape = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const fileName = (path) => path.slice(path.lastIndexOf("/") + 1);
const names = (text, path, unique) => {
  const name = fileName(path);
  const mention = new RegExp(
    `(?<![\\p{L}\\p{N}_\\-/.])((?:[\\p{L}\\p{N}_.\\-]+/)*)${escape(name)}(?![\\p{L}\\p{N}_\\-/]|\\.[\\p{L}\\p{N}])`,
    "gu",
  );
  for (const [, folders] of text.matchAll(mention)) {
    const written = folders.replace(/^(?:\.\/)+/, "") + name;
    if (written === path) return true;
    if (unique && (written === name || path.endsWith(`/${written}`))) return true;
  }
  return false;
};
// True when TEXT names the removed ENTRY in full: a file by its path, a folder ("x/") by
// its path, with or without the "/", or by any path under it.
const namesRemoved = (text, entry) => {
  const folder = entry.endsWith("/");
  const path = folder ? entry.slice(0, -1) : entry;
  const mention = new RegExp(
    `(?<![\\p{L}\\p{N}_\\-/.])(?:\\./)*${escape(path)}` +
      (folder ? `(?:/|(?![\\p{L}\\p{N}_\\-]|\\.[\\p{L}\\p{N}]))` : `(?![\\p{L}\\p{N}_\\-/]|\\.[\\p{L}\\p{N}])`),
    "u",
  );
  return mention.test(text);
};

const numbersIn = (text) => new Set(text.match(NUMBER) ?? []);
// The numbers TEXT sources: its numbers, and each "v" version without its "v".
const sourcedBy = (text) => new Set([...numbersIn(text), ...[...text.matchAll(V_VERSION)].map((m) => m[1])]);

// LINES split into the lines of LABEL's blocks ("Told:" or "Decision:" lines, each with the
// lines it continues onto) and the rest.
const splitBlocks = (lines, label) => {
  const blocks = [];
  const inside = [];
  const rest = [];
  let current = null;
  for (const line of lines) {
    if (label.test(line)) {
      current = [line];
      blocks.push(current);
    } else if (line.trim() === "" || WORD_LINE.test(line)) {
      current = null;
    } else if (current) {
      current.push(line);
    }
    (current ? inside : rest).push(line);
  }
  return { blocks: blocks.map((block) => block.join("\n")), inside, rest };
};
const linesOf = (body) => body.split(/\r?\n/).filter((line) => !TRAILER.test(line));

// Commits in RANGE, oldest first: hash, subject, body. The fields and records are split by
// control characters that a commit message does not contain.
const commitsIn = (root, range) =>
  (git(["log", "--reverse", "--format=%H%x1f%s%x1f%b%x1e", range], { cwd: root }) ?? "")
    .split("\x1e")
    .map((record) => record.replace(/^\n/, ""))
    .filter(Boolean)
    .map((record) => {
      const [hash, subject, body = ""] = record.split("\x1f");
      return { hash, short: hash.slice(0, 12), subject, body, exempt: IN_REPLAY && subject.startsWith(REPLAY_SNAPSHOT) };
    });

const nameList = (text) => text.split("\0").filter(Boolean);
const addedAndRemoved = (text) =>
  (text ?? "")
    .split("\n")
    .filter((line) => line.startsWith("+") || line.startsWith("-"))
    .join("\n");

// A run of 7 or more digits alone that names a commit is a reference (asked of git only
// for a number with no other source).
const commitRefs = (root) => {
  const refs = new Map();
  return (n) => {
    if (!/^\d{7,}$/.test(n)) return false;
    if (!refs.has(n)) {
      refs.set(n, git(["rev-parse", "--verify", "--quiet", `${n}^{commit}`], { cwd: root, allowFail: true }) !== null);
    }
    return refs.get(n);
  };
};

// The findings shared by both modes.
const protectedFinding = (path, where, unnamed, fix, count) =>
  `(a) ${path} is protected (${PROTECTED}) and ${where}, but ${unnamed}. Fix: ${fix}` +
  (count > 1 ? ` (Its file name alone is not enough: ${count} changed files are called ${fileName(path)}.)` : "");
const numberFinding = (who, n, fix) =>
  `(b) ${who}: the number ${n} is in the body but not in the branch's diff and not on a "Told:" line. ` +
  `Fix: put it on a line "Told: ${n} <what it is>, <where it came from>" ${fix}, or take it out.`;
const decisionFinding = (who, entry, fix) =>
  `(c) ${who}: a "Decision:" line names ${entry}, which ${REMOVED} lists, so it is not this project's decision. ` +
  `Fix: ${fix} "Upstream:" if the decision is another project's (such as harness-kit's), or take the path out.`;
const removedIn = (body, removed) =>
  removed.filter((entry) => splitBlocks(linesOf(body), DECISION).blocks.some((block) => namesRemoved(block, entry)));

// ---------------------------------------------------------------------------------------
// The branch check.
// ---------------------------------------------------------------------------------------
const checkBranch = (root) => {
  let state;
  try {
    state = branchState(root);
  } catch (error) {
    fail(`${error.message}. Nothing was checked.`);
  }
  const { baseRef, mergeBase } = state;
  const where = `from ${mergeBase.slice(0, 12)} (merge-base with ${baseRef}) to HEAD`;

  const all = commitsIn(root, `${mergeBase}..HEAD`);
  // Replay snapshots: skipped, and the newest ones cut off the end of the range.
  let end = all.length;
  while (end > 0 && all[end - 1].exempt) end -= 1;
  const tip = end === 0 ? mergeBase : all[end - 1].hash;
  const range = `${mergeBase}..${tip}`;
  const commits = all.slice(0, end).filter((commit) => !commit.exempt);
  const skipped = all.length - commits.length;
  const skippedNote = skipped === 0 ? "" : ` (${skipped} replay snapshot commit(s) skipped)`;
  if (commits.length === 0) {
    console.log(`PASS check-commits: no commits ${where}${skippedNote}, so there is nothing to check`);
    process.exit(0);
  }

  const findings = [];
  const label = (commit) => `${commit.short} "${commit.subject.length > 60 ? `${commit.subject.slice(0, 57)}...` : commit.subject}"`;

  // (a) Protected files.
  const list = listAt(root, [mergeBase, "HEAD"], PROTECTED);
  const changed = nameList(git(["-c", "core.quotePath=false", "diff", "--name-only", "--no-renames", "-z", mergeBase, tip], { cwd: root }) ?? "");
  const bodies = commits.map((commit) => commit.body).join("\n");
  const nameCount = new Map();
  for (const p of changed) nameCount.set(fileName(p), (nameCount.get(fileName(p)) ?? 0) + 1);
  for (const path of changed.filter((p) => isProtected(p, list))) {
    if (names(bodies, path, nameCount.get(fileName(path)) === 1)) continue;
    const by = (git(["log", "--format=%h", "--abbrev=12", range, "--", path], { cwd: root }) ?? "").split("\n").filter(Boolean);
    findings.push(
      protectedFinding(path, `changed in ${by.join(", ") || "the branch"}`, "no commit body on the branch names it",
        `in the body of the commit that changed it, write the full path with the reason it changed.`, nameCount.get(fileName(path))),
    );
  }

  // (b) Numbers in commit bodies.
  const inDiff = sourcedBy(addedAndRemoved(git(["diff", "--no-color", "--no-ext-diff", "--no-renames", "--unified=0", mergeBase, tip], { cwd: root })));
  const told = sourcedBy(commits.flatMap((commit) => splitBlocks(linesOf(commit.body), TOLD).inside).join("\n"));
  const isCommit = commitRefs(root);
  for (const commit of commits) {
    const { rest } = splitBlocks(linesOf(commit.body), TOLD);
    const unsourced = [...numbersIn(rest.join("\n"))].filter((n) => !inDiff.has(n) && !told.has(n) && !isCommit(n));
    for (const n of unsourced) findings.push(numberFinding(label(commit), n, "in a commit body on the branch"));
  }

  // (c) Decision: lines naming a removed path.
  const removed = listAt(root, [mergeBase, "HEAD"], REMOVED);
  for (const commit of commits) {
    for (const entry of removedIn(commit.body, removed)) findings.push(decisionFinding(label(commit), entry, "reword that commit, relabelling the line"));
  }

  if (findings.length === 0) {
    const what = list.length === 0 ? `no ${PROTECTED}, so no protected files` : `every protected file changed is named in a body`;
    console.log(
      `PASS check-commits: ${commits.length} commit(s) ${where}${skippedNote}: ${what}, every number in a body is in the diff or on a "Told:" line, ` +
        `and no "Decision:" line names a path in ${REMOVED}`,
    );
    process.exit(0);
  }
  console.log(
    `${WARN ? "WARN" : "FAIL"} check-commits: ${findings.length} finding(s) in the ${commits.length} commit(s) ${where}` +
      `${WARN ? " (--warn: not failing)" : ""}. To change a message: git commit --amend for the last commit; ` +
      `git rebase -i ${mergeBase.slice(0, 12)}, marking the commit "reword", for an earlier one.`,
  );
  for (const finding of findings) console.log(`  ${finding}`);
  process.exit(WARN ? 0 : 1);
};

// ---------------------------------------------------------------------------------------
// The message mode.
// ---------------------------------------------------------------------------------------

// The subject and body of TEXT as git will record them for the commit-msg hook's input.
const parseMessage = (root, text) => {
  const configured = (git(["config", "--get", "core.commentChar"], { cwd: root, allowFail: true }) ?? "").trim();
  const comment = [...configured].length === 1 ? configured : "#";
  let lines = text.split(/\r?\n/);
  const scissors = lines.findIndex((line) => line === `${comment} ------------------------ >8 ------------------------`);
  if (scissors >= 0) lines = lines.slice(0, scissors);
  lines = lines.filter((line) => !line.startsWith(comment));
  while (lines.length > 0 && lines[0].trim() === "") lines.shift();
  const blank = lines.findIndex((line) => line.trim() === "");
  const subject = (blank < 0 ? lines : lines.slice(0, blank)).map((line) => line.trim()).join(" ");
  const body = blank < 0 ? "" : lines.slice(blank + 1).join("\n");
  return { subject, body };
};

const checkMessage = (root) => {
  let text;
  try {
    text = readFileSync(MESSAGE, "utf8");
  } catch (error) {
    fail(`cannot read the message file ${MESSAGE}: ${error.message}. Nothing was checked.`);
  }
  const { body } = parseMessage(root, text);

  let mergeBase = null;
  let baseNote;
  try {
    const state = branchState(root);
    mergeBase = state.mergeBase;
    baseNote = `the branch so far (from ${mergeBase.slice(0, 12)}, the merge-base with ${state.baseRef})`;
  } catch (error) {
    baseNote = `no branch so far (${error.message})`;
  }

  const branch = mergeBase ? commitsIn(root, `${mergeBase}..HEAD`) : [];
  const bodies = [...branch.map((commit) => commit.body), body].join("\n");
  const since = mergeBase ? [mergeBase] : [];
  const cached = (args) => git(["-c", "core.quotePath=false", "diff", "--cached", ...args, ...since], { cwd: root }) ?? "";
  const changed = nameList(cached(["--name-only", "--no-renames", "-z"]));
  const inCommit = nameList(git(["-c", "core.quotePath=false", "diff", "--cached", "--name-only", "--no-renames", "-z"], { cwd: root }) ?? "");
  const findings = [];

  // (a) Protected files the new commit changes.
  const list = listAt(root, [...since, ""], PROTECTED);
  const nameCount = new Map();
  for (const p of changed) nameCount.set(fileName(p), (nameCount.get(fileName(p)) ?? 0) + 1);
  for (const path of inCommit.filter((p) => isProtected(p, list))) {
    if (names(bodies, path, nameCount.get(fileName(path)) === 1)) continue;
    findings.push(
      protectedFinding(path, "changed in this commit", "neither this message's body nor any commit body on the branch names it",
        `add a line to this message's body with the full path and the reason it changed.`,
        nameCount.get(fileName(path))),
    );
  }

  // (b) Numbers in the new body.
  const inDiff = sourcedBy(addedAndRemoved(cached(["--no-color", "--no-ext-diff", "--no-renames", "--unified=0"])));
  const told = sourcedBy([...branch.map((commit) => commit.body), body].flatMap((b) => splitBlocks(linesOf(b), TOLD).inside).join("\n"));
  const isCommit = commitRefs(root);
  const { rest } = splitBlocks(linesOf(body), TOLD);
  for (const n of [...numbersIn(rest.join("\n"))].filter((n) => !inDiff.has(n) && !told.has(n) && !isCommit(n))) {
    findings.push(numberFinding("this message", n, "in this message's body"));
  }

  // (c) Decision: lines in the new body naming a removed path.
  for (const entry of removedIn(body, listAt(root, [...since, ""], REMOVED))) {
    findings.push(decisionFinding("this message", entry, "relabel the line"));
  }

  const what = `${MESSAGE}, against the staged changes and ${baseNote}`;
  if (findings.length === 0) {
    console.log(
      `PASS check-commits: the message in ${what}: every protected file in the commit is named in a body, ` +
        `every number in its body is in the diff or on a "Told:" line, and no "Decision:" line names a path in ${REMOVED}`,
    );
    process.exit(0);
  }
  console.log(`${WARN ? "WARN" : "FAIL"} check-commits: ${findings.length} finding(s) in the message in ${what}${WARN ? " (--warn: not failing)" : ""}`);
  for (const finding of findings) console.log(`  ${finding}`);
  process.exit(WARN ? 0 : 1);
};

let root;
try {
  root = git(["rev-parse", "--show-toplevel"]).trim();
} catch (error) {
  fail(`${error.message}. Nothing was checked.`);
}
if (MESSAGE === null) checkBranch(root);
else checkMessage(root);
