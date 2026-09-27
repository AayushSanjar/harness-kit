#!/usr/bin/env node
// CI check: the branch's current diff was reviewed by review.sh, and the verdict was PASS.
//
//   node check-reviewed.mjs          run the check; one PASS or FAIL line, exit 0 or 1
//   node check-reviewed.mjs --hash   print "<base ref>\t<merge-base>\t<diff hash>" (review.sh
//                                    uses this, so both compute the hash the same way)
//
// Run from anywhere inside the project's git repository. Reads .harness/review-base (first
// line, default main) and .harness/reviews.tsv, both as committed at HEAD: CI sees commits,
// so a review line that is not committed yet does not count.
//
// THE DIFF HASH. sha256 of git's raw diff from the merge-base to HEAD, with full blob ids,
// no rename detection, NUL-separated, excluding .harness/reviews.tsv itself (committing a
// review line must not change the hash it records). The raw form names exactly the content
// the patch does, but does not change with a person's diff settings (algorithm, context,
// prefixes, colour), so a laptop and CI agree. An empty diff hashes to "none".
//
// PASS when:
//   - reviews.tsv at HEAD keeps every line it had at the merge-base, unchanged and in order
//     (the file is append-only), and
//   - the diff is empty, or the LATEST line whose diff hash matches says PASS. A later
//     review of the same diff overrides an earlier one, so a PASS followed by a STOP fails.
//
// IN CI the base branch and full history must be present: actions/checkout needs
// `fetch-depth: 0`. For pull requests, check out the branch head
// (`ref: ${{ github.event.pull_request.head.sha }}`), not the default merge commit, whose
// diff against the base is not the diff that was reviewed.
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";

const REVIEWS = ".harness/reviews.tsv";
const RERUN = "Run scripts/review.sh in your own terminal.";
const FIELDS = ["date", "branch", "base", "head", "diff", "verdict", "items", "cost", "duration"];

const git = (args, { cwd, allowFail = false } = {}) => {
  const result = spawnSync("git", args, { cwd, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
  if (result.status !== 0 && !allowFail) {
    throw new Error(`git ${args.join(" ")} failed: ${(result.stderr || result.error?.message || "").trim()}`);
  }
  return result.status === 0 ? result.stdout : null;
};

const fail = (message) => {
  console.log(`FAIL check-reviewed: ${message}`);
  process.exit(1);
};

// The base ref, its merge-base with HEAD, and the diff hash. Throws with a message a person
// can act on.
const branchState = (cwd = process.cwd()) => {
  const root = git(["rev-parse", "--show-toplevel"], { cwd }).trim();
  const configured = (git(["show", `HEAD:.harness/review-base`], { cwd: root, allowFail: true }) ?? "")
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
  const raw = git(
    ["-c", "core.quotePath=true", "diff", "--raw", "-z", "--full-index", "--no-renames", "--no-relative",
      "--no-ext-diff", "--no-textconv", mergeBase, "HEAD", "--", ".", `:(exclude)${REVIEWS}`],
    { cwd: root },
  );
  const hash = raw === "" ? "none" : createHash("sha256").update(raw).digest("hex");
  return { root, baseRef, mergeBase, hash };
};

const linesOf = (text) => {
  const lines = (text ?? "").split("\n");
  if (lines[lines.length - 1] === "") lines.pop();
  return lines;
};

const main = () => {
  let state;
  try {
    state = branchState();
  } catch (error) {
    fail(`${error.message}. Nothing was checked.`);
  }
  const { root, baseRef, mergeBase, hash } = state;

  if (process.argv.includes("--hash")) {
    console.log(`${baseRef}\t${mergeBase}\t${hash}`);
    process.exit(0);
  }

  const before = linesOf(git(["show", `${mergeBase}:${REVIEWS}`], { cwd: root, allowFail: true }));
  const now = linesOf(git(["show", `HEAD:${REVIEWS}`], { cwd: root, allowFail: true }));
  for (let i = 0; i < before.length; i += 1) {
    if (now[i] !== before[i]) {
      const what = i >= now.length ? "removed" : "changed";
      fail(
        `${REVIEWS} is append-only, but line ${i + 1} as of the merge-base ${mergeBase.slice(0, 12)} was ${what} on this branch. ` +
          `Restore the earlier lines exactly and only add new ones below them.`,
      );
    }
  }

  if (hash === "none") {
    console.log(`PASS check-reviewed: no diff against ${baseRef} (merge-base ${mergeBase.slice(0, 12)}), so there is nothing to review`);
    process.exit(0);
  }

  const reviews = now
    .map((line) => line.split("\t"))
    .filter((fields) => fields.length === FIELDS.length)
    .map((fields) => Object.fromEntries(FIELDS.map((name, i) => [name, fields[i]])));
  const matching = reviews.filter((review) => review.diff === hash);

  if (matching.length === 0) {
    const last = reviews[reviews.length - 1];
    const why = last
      ? `the diff changed since the last review (reviewed ${last.diff.slice(0, 12)} at ${last.head.slice(0, 12)}, now ${hash.slice(0, 12)})`
      : `${REVIEWS} has no reviews`;
    fail(`no review of this branch's current diff (${hash.slice(0, 12)} against ${baseRef}): ${why}. ${RERUN}`);
  }
  const latest = matching[matching.length - 1];
  if (latest.verdict !== "PASS") {
    fail(
      `the latest review of this diff (${latest.date}, head ${latest.head.slice(0, 12)}) says ${latest.verdict}` +
        `${latest.items ? ` (${latest.items})` : ""}, not PASS. Fix what it reports, then: ${RERUN}`,
    );
  }
  console.log(
    `PASS check-reviewed: diff ${hash.slice(0, 12)} against ${baseRef} was reviewed ${latest.date} at head ${latest.head.slice(0, 12)}: PASS`,
  );
  process.exit(0);
};

main();
