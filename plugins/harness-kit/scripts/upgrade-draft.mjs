#!/usr/bin/env node
// The commit message draft for a harness-kit pin move, written by upgrade.sh.
//
//   node upgrade-draft.mjs OLD NEW REPO LOG PATH...
//
// OLD and NEW are the pin's refs before and after (v0.12.0, v0.13.0), REPO the GitHub
// repository (owner/name), LOG a file of harness-kit's own commits from OLD to NEW, oldest
// first, as `git log --reverse --format=%H%x1f%s%x1f%b%x1e` prints them, and PATH... the
// files the upgrade changed in the project. Prints the draft on stdout.
//
// THE DRAFT, in the form check-commits.mjs checks (and the commit-msg hook enforces). The
// word "Decision:" appears nowhere in it, so no decisions index can take one of
// harness-kit's decisions for the project's:
//   - the subject: "Pin harness-kit to NEW (was OLD)";
//   - one line per changed PATH, naming it in full with its reason:
//     .claude/settings.json (the pin), .harness/protected.lock (re-recorded by the
//     approval command), any other path (changed by the approval command);
//   - harness-kit's commits, each subject as a "- " line, with each of its "Breaks:" lines
//     kept as written and each "Decision:" line relabelled "Upstream:" (with the lines
//     each continues onto): harness-kit's decisions are not this project's, and a
//     "Decision:" line would enter the project's decisions index as its own. The rest of
//     each body (harness-kit's own file reasons and "Told:" lines) is left out;
//   - a "Told:" line holding every number in those carried lines, saying they are quoted
//     from harness-kit's commit messages, since the project's diff does not show them.
import { readFileSync } from "node:fs";

const [OLD, NEW, REPO, LOG, ...PATHS] = process.argv.slice(2);
if (!OLD || !NEW || !REPO || !LOG) {
  console.error("usage: node upgrade-draft.mjs OLD NEW REPO LOG PATH...");
  process.exit(2);
}

// As in check-commits.mjs.
const NUMBER = /(?<![\p{L}\p{N}_.])(?<![\p{L}\p{N}]-)\d+(?:\.\d+)*(?![\p{L}\p{N}_]|\.\d)/gu;
const WORD_LINE = /^\s*(?:[-*]\s+)?[\p{L}][\p{L}\p{N}_-]*:/u;
const TRAILER = /^[A-Za-z][A-Za-z0-9-]*:\s.*<[^<>\s]+@[^<>\s]+>\s*$/;
const BREAKS = /^\s*(?:[-*]\s+)?Breaks:/;
const DECISION = /^(\s*(?:[-*]\s+)?)Decision:/;

const commits = readFileSync(LOG, "utf8")
  .split("\x1e")
  .map((record) => record.replace(/^\n/, ""))
  .filter(Boolean)
  .map((record) => {
    const [hash, subject, body = ""] = record.split("\x1f");
    return { hash, subject, body };
  });

// The Breaks: and Decision: blocks of BODY, Decision: relabelled Upstream:, each line
// trimmed.
const carried = (body) => {
  const kept = [];
  let keeping = false;
  for (const line of body.split(/\r?\n/)) {
    if (TRAILER.test(line) || line.trim() === "") {
      keeping = false;
    } else if (BREAKS.test(line) || DECISION.test(line)) {
      keeping = true;
      kept.push(line.replace(DECISION, "$1Upstream:").trim());
    } else if (WORD_LINE.test(line)) {
      keeping = false;
    } else if (keeping) {
      kept.push(line.trim());
    }
  }
  return kept;
};

const reason = (path) => {
  if (path === ".claude/settings.json") {
    return `${path}: pins the harness-kit marketplace to ${NEW} (was ${OLD}); upgrade.sh moved the pin, re-added the marketplace at ${NEW}, updated the plugin and saw a new session load it.`;
  }
  if (path === ".harness/protected.lock") {
    return `${path}: re-recorded by the approval command (.harness/approve-command) that upgrade.sh ran, which the person answered after reading the diff.`;
  }
  return `${path}: changed by the approval command (.harness/approve-command) while upgrade.sh ran.`;
};

const upstream = [];
for (const commit of commits) {
  upstream.push(`- ${commit.subject}`);
  for (const line of carried(commit.body)) upstream.push(`  ${line}`);
}

// Every number in the carried lines, in order of first appearance, on continuation lines
// of the one Told: line (indented, so each continues it), at most 90 characters each.
const numbers = [...new Set(upstream.join("\n").match(NUMBER) ?? [])];
const told = [];
if (numbers.length > 0) {
  told.push(
    `Told: ${numbers.length === 1 ? "the number" : "the numbers"} in harness-kit's commits above are quoted from its commit messages ` +
      `(git log ${OLD}..${NEW} in github.com/${REPO}), not from this project's diff:`,
  );
  let line = " ";
  for (const n of numbers) {
    if (line.length > 1 && line.length + n.length + 1 > 90) {
      told.push(line);
      line = " ";
    }
    line += ` ${n}`;
  }
  told.push(line);
}

const lines = [
  `Pin harness-kit to ${NEW} (was ${OLD})`,
  "",
  ...PATHS.map(reason),
  "",
  commits.length === 0
    ? `harness-kit has no commits from ${OLD} to ${NEW} (github.com/${REPO}).`
    : `harness-kit's own commits from ${OLD} to ${NEW} (github.com/${REPO}), with each Breaks: line as written and each of its decisions relabelled Upstream:, because they are harness-kit's decisions, not this project's:`,
  ...(commits.length === 0 ? [] : ["", ...upstream]),
  ...(told.length === 0 ? [] : ["", ...told]),
];
process.stdout.write(lines.join("\n") + "\n");
