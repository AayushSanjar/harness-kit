#!/usr/bin/env node
// CI check: .harness/defects.tsv is append-only, and every line the branch adds is well formed.
//
//   node check-defects.mjs             one PASS or FAIL line, then one line per finding;
//                                      exit 0 or 1
//   node check-defects.mjs --resolve   for readers: print the file with each "this" in the
//                                      fixing-commit field replaced by the commit it means
//                                      (below), or by "uncommitted"; exit 0 (1 with no file)
//
// Run from anywhere inside the project's git repository, in the project's check.sh and in
// CI. The base is found as check-reviewed.mjs finds it: .harness/review-base at HEAD (first
// line, default main), locally or as origin/<base>, and its merge-base with HEAD. In CI
// that needs the full history (actions/checkout with `fetch-depth: 0`).
//
// THE FILE, one escaped defect per line, written by /harness-kit:record-defect (its SKILL.md
// has the full format), tab-separated, # comments and blank lines allowed:
//   date  id  description  where-found  introducing-commit  test-added  fixing-commit
//   date                YYYY-MM-DD
//   id                  letters, digits, ".", "_" or "-", unique in the file (D1, D2, ...)
//   where-found         live, review, check or person
//   introducing-commit  a commit hash (7 to 40 hex digits) in this repository, or "unknown"
//   fixing-commit       a commit hash in this repository, or "this": the commit that adds
//                       this line, which also holds the fix
//   description, test-added   any text, not empty
//
// RESOLVING "this". A commit cannot name its own hash, and the file is append-only, so a
// fix and its line committed together say "this". Git resolves it: `git blame --porcelain
// -L <n>,<n> -- .harness/defects.tsv` names the commit that added line n (all zeros while
// the line is uncommitted). --resolve does that for every line; the check does it for the
// lines the branch adds.
//
// It reads the file as it is in the working tree: in CI that is HEAD, and locally an
// uncommitted edit fails at once, so the Stop hook catches it before it is committed.
//
// IT FAILS when:
//   (a) a line present at the merge-base was changed or removed, or a line was inserted
//       above it: the file at the merge-base must be the start of the file now, line for
//       line;
//   (b) a line added on the branch does not have the fields above (comment and blank lines
//       excepted), repeats an id, or names a commit that is not in the repository, or says
//       "this" and resolves to a commit that changes nothing but .harness/defects.tsv (so it
//       holds no fix: write the fixing commit's hash instead). An uncommitted "this" line
//       passes: the commit that adds it is not made yet.
// Lines already at the merge-base are not re-checked for (b): they cannot be fixed now.
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const DEFECTS = ".harness/defects.tsv";
const FIELDS = ["date", "id", "description", "where-found", "introducing-commit", "test-added", "fixing-commit"];
const WHERE = ["live", "review", "check", "person"];
const HASH = /^[0-9a-f]{7,40}$/;

const git = (args, { cwd, allowFail = false } = {}) => {
  const result = spawnSync("git", args, { cwd, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
  if (result.status !== 0 && !allowFail) {
    throw new Error(`git ${args.join(" ")} failed: ${(result.stderr || result.error?.message || "").trim()}`);
  }
  return result.status === 0 ? result.stdout : null;
};

const fail = (message) => {
  console.log(`FAIL check-defects: ${message}`);
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

// The commit that added line N (1-based) of the working tree's file, or null while it is
// uncommitted (or the file is not tracked).
const addedBy = (root, n) => {
  const out = git(["blame", "--porcelain", "-L", `${n},${n}`, "--", DEFECTS], { cwd: root, allowFail: true });
  const hash = out?.split(" ")[0] ?? "";
  return /^[0-9a-f]{40}$/.test(hash) && !/^0+$/.test(hash) ? hash : null;
};

// Files a commit changes (against its first parent, or everything for a root commit).
const changedBy = (root, hash) =>
  (git(["diff-tree", "--no-commit-id", "--name-only", "-r", "--root", hash], { cwd: root, allowFail: true }) ?? "")
    .split("\n")
    .filter(Boolean);

const linesOf = (text) => {
  const lines = (text ?? "").split("\n");
  if (lines[lines.length - 1] === "") lines.pop();
  return lines;
};

const resolve = () => {
  const root = git(["rev-parse", "--show-toplevel"]).trim();
  const path = join(root, DEFECTS);
  if (!existsSync(path)) {
    console.log(`check-defects --resolve: there is no ${DEFECTS}`);
    process.exit(1);
  }
  linesOf(readFileSync(path, "utf8")).forEach((line, i) => {
    const fields = line.split("\t");
    if (line.startsWith("#") || fields.length !== FIELDS.length || fields[6] !== "this") {
      console.log(line);
      return;
    }
    fields[6] = addedBy(root, i + 1) ?? "uncommitted";
    console.log(fields.join("\t"));
  });
  process.exit(0);
};

const main = () => {
  if (process.argv.includes("--resolve")) resolve();
  let state;
  try {
    state = branchState();
  } catch (error) {
    fail(`${error.message}. Nothing was checked.`);
  }
  const { root, baseRef, mergeBase } = state;
  const where = `merge-base ${mergeBase.slice(0, 12)} with ${baseRef}`;
  const path = join(root, DEFECTS);
  const before = linesOf(git(["show", `${mergeBase}:${DEFECTS}`], { cwd: root, allowFail: true }));
  const now = linesOf(existsSync(path) ? readFileSync(path, "utf8") : null);
  if (before.length === 0 && now.length === 0) {
    console.log(`PASS check-defects: no ${DEFECTS} at the ${where} or now, so there is nothing to check`);
    process.exit(0);
  }

  const findings = [];
  // (a) Append-only.
  for (let i = 0; i < before.length; i += 1) {
    if (now[i] === before[i]) continue;
    const what = i >= now.length ? "removed" : "changed (or a line was inserted above it)";
    findings.push(
      `(a) line ${i + 1} as of the ${where} was ${what}. It was: ${before[i]}` +
        `${i < now.length ? `\n      now: ${now[i]}` : ""}` +
        `\n      Fix: restore the lines the file had at the merge-base exactly (git show ${mergeBase.slice(0, 12)}:${DEFECTS}) and only add new lines below them.`,
    );
    break;
  }

  // (b) The lines added on the branch.
  const ids = new Set();
  const resolved = [];
  const commitExists = (hash) =>
    git(["rev-parse", "--verify", "--quiet", `${hash}^{commit}`], { cwd: root, allowFail: true }) !== null;
  now.forEach((line, i) => {
    const text = line.replace(/\r$/, "");
    if (text.trim() === "" || text.startsWith("#")) return;
    const fields = text.split("\t");
    const record = Object.fromEntries(FIELDS.map((name, j) => [name, fields[j] ?? ""]));
    const problems = [];
    if (fields.length !== FIELDS.length) {
      problems.push(`it has ${fields.length} tab-separated fields, not ${FIELDS.length} (${FIELDS.join(", ")})`);
    } else {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(record.date)) problems.push(`the date "${record.date}" is not YYYY-MM-DD`);
      if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(record.id)) problems.push(`the id "${record.id}" must be letters, digits, ".", "_" or "-"`);
      else if (ids.has(record.id)) problems.push(`the id ${record.id} is used by an earlier line`);
      for (const name of ["description", "test-added"]) if (record[name].trim() === "") problems.push(`${name} is empty`);
      if (!WHERE.includes(record["where-found"])) {
        problems.push(`where-found is "${record["where-found"]}", not one of ${WHERE.join(", ")}`);
      }
      for (const [name, word] of [["introducing-commit", "unknown"], ["fixing-commit", "this"]]) {
        const value = record[name];
        if (value === word) {
          if (word !== "this" || i < before.length) continue;
          const hash = addedBy(root, i + 1);
          if (hash === null) continue;
          const others = changedBy(root, hash).filter((file) => file !== DEFECTS);
          if (others.length === 0) {
            problems.push(`fixing-commit "this" resolves to ${hash.slice(0, 12)}, which changes only ${DEFECTS}, so it holds no fix; write the fixing commit's hash instead`);
          } else {
            resolved.push(`${record.id}: "this" is ${hash.slice(0, 12)}`);
          }
          continue;
        }
        if (!HASH.test(value)) problems.push(`${name} is "${value}", not a commit hash or "${word}"`);
        else if (!commitExists(value)) problems.push(`${name} ${value} is not a commit in this repository`);
      }
    }
    if (fields.length === FIELDS.length) ids.add(record.id);
    if (i < before.length || problems.length === 0) return;
    findings.push(`(b) line ${i + 1} (${record.id || "no id"}): ${problems.join("; ")}`);
  });

  const added = now.length - before.length;
  if (findings.length === 0) {
    console.log(
      `PASS check-defects: ${DEFECTS} keeps its ${before.length} line(s) from the ${where}, and ` +
        `${added > 0 ? `the ${added} line(s) added since are well formed` : "no line was added since"}` +
        `${resolved.length > 0 ? ` (${resolved.join("; ")})` : ""}`,
    );
    process.exit(0);
  }
  console.log(`FAIL check-defects: ${findings.length} finding(s) in ${DEFECTS} (append-only since the ${where})`);
  for (const finding of findings) console.log(`  ${finding}`);
  process.exit(1);
};

main();
