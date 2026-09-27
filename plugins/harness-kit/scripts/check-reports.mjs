#!/usr/bin/env node
// CI check: no file under .reports/ is tracked by git.
//
//   node check-reports.mjs     one PASS or FAIL line, exit 0 or 1
//
// Run from anywhere inside the project's git repository. .reports/ holds Claude's final
// report for each branch (report-path.sh); it is for the person to read and must never be
// committed. "Tracked" means in the index (staged, or committed and not removed) or in
// HEAD's tree, so a report that was committed and then only `git rm --cached` still fails
// until that removal is committed.
import { spawnSync } from "node:child_process";

const DIR = ".reports";

const git = (args, cwd) => {
  const result = spawnSync("git", args, { cwd, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  return result.status === 0 ? result.stdout : null;
};

const root = git(["rev-parse", "--show-toplevel"])?.trim();
if (!root) {
  console.log("FAIL check-reports: not inside a git repository. Nothing was checked.");
  process.exit(1);
}

const split = (out) => (out ?? "").split("\0").filter(Boolean);
const tracked = new Set([
  ...split(git(["ls-files", "-z", "--cached", "--", DIR], root)),
  ...split(git(["rev-parse", "-q", "--verify", "HEAD"], root) === null
    ? ""
    : git(["ls-tree", "-r", "-z", "--name-only", "HEAD", "--", DIR], root)),
]);

if (tracked.size > 0) {
  const files = [...tracked].sort();
  console.log(
    `FAIL check-reports: git tracks ${files.length} file(s) under ${DIR}/, which holds reports for the person and must never be committed: ` +
      `${files.join(", ")}. Run: git rm -r --cached ${DIR} && git commit -m "Stop tracking ${DIR}/"`,
  );
  process.exit(1);
}
console.log(`PASS check-reports: git tracks nothing under ${DIR}/`);
process.exit(0);
