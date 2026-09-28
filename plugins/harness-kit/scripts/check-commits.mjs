#!/usr/bin/env node
// CI check: the branch's commit messages give a reason for every protected file changed and
// a source for every number they state.
//
//   node check-commits.mjs          one PASS or FAIL line, then one line per finding; exit 0 or 1
//   node check-commits.mjs --warn   the same findings under a WARN line; always exit 0
//
// RECOMMENDED: --warn. Put `node <plugin>/scripts/check-commits.mjs --warn` in the project's
// check.sh and CI, and enforce (drop --warn) only after 3 branches whose messages were
// written from Claude's commit drafts (.reports/<branch>.commit.txt) show no false findings.
// Replayed on a real project's reviewed history, enforcing from the start would have failed
// branches its reviewer passed, over commit messages written by hand.
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
// IT FAILS on two kinds of finding:
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
//
// Each finding names the commit, the path or number, and how to fix it. Rewording a
// message does not change the diff, so a recorded review (check-reviewed.mjs) still holds.
import { spawnSync } from "node:child_process";

const PROTECTED = ".harness/protected-paths";
const WARN = process.argv.includes("--warn");
const NUMBER = /(?<![\p{L}\p{N}_.])(?<![\p{L}\p{N}]-)\d+(?:\.\d+)*(?![\p{L}\p{N}_]|\.\d)/gu;
// A version with a leading "v" (v0.9.0), as a source for the same version without it.
const V_VERSION = /(?<![\p{L}\p{N}_.])(?<![\p{L}\p{N}]-)v(\d+(?:\.\d+)+)(?![\p{L}\p{N}_]|\.\d)/gu;
const TOLD = /^\s*(?:[-*]\s+)?Told:/;
// Any "Word:" line, which ends a "Told:" line's continuation.
const WORD_LINE = /^\s*(?:[-*]\s+)?[\p{L}][\p{L}\p{N}_-]*:/u;
const REPLAY_SNAPSHOT = "harness-kit replay-faults:";
const IN_REPLAY = process.env.HARNESS_KIT_REPLAY === "1";
const TRAILER = /^[A-Za-z][A-Za-z0-9-]*:\s.*<[^<>\s]+@[^<>\s]+>\s*$/;

const unknown = process.argv.slice(2).filter((arg) => arg !== "--warn");
if (unknown.length > 0) {
  console.log(`FAIL check-commits: unknown argument ${unknown.join(" ")}. Usage: node check-commits.mjs [--warn]`);
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

// The base ref and its merge-base with HEAD, as check-reviewed.mjs works them out.
const branchState = () => {
  const root = git(["rev-parse", "--show-toplevel"]).trim();
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
  return { root, baseRef, mergeBase };
};

const protectedList = (root, rev) =>
  (git(["show", `${rev}:${PROTECTED}`], { cwd: root, allowFail: true }) ?? "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line !== "" && !line.startsWith("#"))
    .map((line) => line.replace(/^\.\//, ""));

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

const numbersIn = (text) => new Set(text.match(NUMBER) ?? []);
// The numbers TEXT sources: its numbers, and each "v" version without its "v".
const sourcedBy = (text) => new Set([...numbersIn(text), ...[...text.matchAll(V_VERSION)].map((m) => m[1])]);

// LINES split into the "Told:" lines, each with the lines it continues onto, and the rest.
const splitTold = (lines) => {
  const told = [];
  const rest = [];
  let inTold = false;
  for (const line of lines) {
    if (TOLD.test(line)) inTold = true;
    else if (line.trim() === "" || WORD_LINE.test(line)) inTold = false;
    (inTold ? told : rest).push(line);
  }
  return { told, rest };
};

const main = () => {
  let state;
  try {
    state = branchState();
  } catch (error) {
    fail(`${error.message}. Nothing was checked.`);
  }
  const { root, baseRef, mergeBase } = state;
  const where = `from ${mergeBase.slice(0, 12)} (merge-base with ${baseRef}) to HEAD`;

  // Commits, oldest first: hash, subject, body. The fields and records are split by
  // control characters that a commit message does not contain.
  const all = (git(["log", "--reverse", "--format=%H%x1f%s%x1f%b%x1e", `${mergeBase}..HEAD`], { cwd: root }) ?? "")
    .split("\x1e")
    .map((record) => record.replace(/^\n/, ""))
    .filter(Boolean)
    .map((record) => {
      const [hash, subject, body = ""] = record.split("\x1f");
      return { hash, short: hash.slice(0, 12), subject, body, exempt: IN_REPLAY && subject.startsWith(REPLAY_SNAPSHOT) };
    });
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
  const list = [...new Set([...protectedList(root, mergeBase), ...protectedList(root, "HEAD")])];
  const changed = (git(["-c", "core.quotePath=false", "diff", "--name-only", "--no-renames", "-z", mergeBase, tip], { cwd: root }) ?? "")
    .split("\0")
    .filter(Boolean);
  const bodies = commits.map((commit) => commit.body).join("\n");
  const nameCount = new Map();
  for (const p of changed) nameCount.set(fileName(p), (nameCount.get(fileName(p)) ?? 0) + 1);
  for (const path of changed.filter((p) => isProtected(p, list))) {
    if (names(bodies, path, nameCount.get(fileName(path)) === 1)) continue;
    const by = (git(["log", "--format=%h", "--abbrev=12", range, "--", path], { cwd: root }) ?? "").split("\n").filter(Boolean);
    findings.push(
      `(a) ${path} is protected (${PROTECTED}) and changed in ${by.join(", ") || "the branch"}, but no commit body on the branch names it. ` +
        `Fix: in the body of the commit that changed it, write the full path with the reason it changed.` +
        (nameCount.get(fileName(path)) > 1 ? ` (Its file name alone is not enough: ${nameCount.get(fileName(path))} changed files are called ${fileName(path)}.)` : ""),
    );
  }

  // (b) Numbers in commit bodies.
  const diff = (git(["diff", "--no-color", "--no-ext-diff", "--no-renames", "--unified=0", mergeBase, tip], { cwd: root }) ?? "")
    .split("\n")
    .filter((line) => line.startsWith("+") || line.startsWith("-"))
    .join("\n");
  const inDiff = sourcedBy(diff);
  const linesOf = (commit) => commit.body.split(/\r?\n/).filter((line) => !TRAILER.test(line));
  const told = sourcedBy(commits.flatMap((commit) => splitTold(linesOf(commit)).told).join("\n"));
  // A run of 7 or more digits alone that names a commit is a reference (asked of git only
  // for a number with no other source).
  const refs = new Map();
  const isCommit = (n) => {
    if (!/^\d{7,}$/.test(n)) return false;
    if (!refs.has(n)) {
      refs.set(n, git(["rev-parse", "--verify", "--quiet", `${n}^{commit}`], { cwd: root, allowFail: true }) !== null);
    }
    return refs.get(n);
  };
  for (const commit of commits) {
    const { rest } = splitTold(linesOf(commit));
    const unsourced = [...numbersIn(rest.join("\n"))].filter((n) => !inDiff.has(n) && !told.has(n) && !isCommit(n));
    for (const n of unsourced) {
      findings.push(
        `(b) ${label(commit)}: the number ${n} is in the body but not in the branch's diff and not on a "Told:" line. ` +
          `Fix: put it on a line "Told: ${n} <what it is>, <where it came from>" in a commit body on the branch, or take it out.`,
      );
    }
  }

  if (findings.length === 0) {
    const what = list.length === 0 ? `no ${PROTECTED}, so no protected files` : `every protected file changed is named in a body`;
    console.log(`PASS check-commits: ${commits.length} commit(s) ${where}${skippedNote}: ${what}, and every number in a body is in the diff or on a "Told:" line`);
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

main();
