#!/usr/bin/env node
// Measure the harness: six numbers for a period, computed on demand from the project's own
// records, each printed with its source.
//
//   node harness-metrics.mjs [--since REF|YYYY-MM-DD] [--until YYYY-MM-DD]
//       print the table for the period: from --since (default: the tag pre-harness; a ref
//       means its commit's committer date, a date means 00:00 UTC that day) to the end of
//       --until's day in UTC (default: now)
//   node harness-metrics.mjs --baseline
//       compute the same numbers, where the old records allow, for everything before the
//       tag pre-harness, and write them ONCE to .harness/baseline.tsv
//
// Run in a consumer project, from anywhere inside its git repository, in the person's own
// terminal. It stores nothing except the baseline, and never runs in CI, so it adds no CI
// minutes. Its only call outside git is one read-only `gh run list`.
//
// NOT FOUND. A number whose source does not exist (a missing file or event log, gh failing) is NOT FOUND,
// never 0: 0 means the source exists and holds nothing for the period. Nothing is estimated.
//
// THE EVENT LOG (numbers 2 and 6) is <git common dir>/harness-kit/events.tsv, written by
// land.sh, ship.sh and replay-faults.sh (events.sh has the format). It is inside .git, so
// it is never committed: it covers this machine only, from when it was first written.
//
// THE NUMBERS. Files are read from the working tree (for --baseline: as they are at the tag
// pre-harness). A line whose date is a day (defects.tsv) is in the period when its day is
// on or after the start's UTC day; a timestamp (reviews.tsv, CI runs) when it is at or after
// the start. Each number, and what would make it misleading:
//   1. Escaped defects: the lines of .harness/defects.tsv dated in the period, by
//      where-found.
//      Misleading: only defects recorded with the record-defect skill are counted, so a low
//      number can mean escaped bugs went unrecorded rather than that fewer escaped.
//   2. Planted faults caught: the KILLED count of the last replay-faults.sh run of every
//      entry dated in the period, out of the entries it replayed, from the local event log
//      (the last run of some entries when there is no full one, and it says so). Labelled
//      "local record, this machine only". The source also gives the count planted now in
//      .harness/mutations.tsv. No log, or no run in the period: NOT FOUND.
//      Misleading: the log holds only this machine's runs since it was added, so the last
//      run it shows may be older than the code now (a check changed since can have stopped
//      catching a fault) and runs elsewhere, such as in CI, are not seen.
//   3. Reviews not PASS on the first try: of the branches whose first line in
//      .harness/reviews.tsv is in the period, those whose first verdict is not PASS, and
//      why (the items marked F, with their text from .harness/review-checklist.md).
//      Misleading: a review that crashed or hit its limits appends nothing, so such a first
//      attempt is invisible, and a branch name used twice is judged by its first use only.
//   4. Branches whose first CI run was green: from `gh run list` (read-only; the
//      workflow in .harness/ci-workflow only, if that file exists), each branch but the
//      base (.harness/review-base, default main) is judged by the runs for the first
//      commit it ran CI on; green when all of them concluded success. A branch counts when
//      its first run started in the period; one still running is listed, not counted.
//      Misleading: gh shows only a run's latest attempt, so a red first run re-run to green
//      counts as green, and runs beyond gh's limit (1000 here) or deleted from GitHub are
//      not seen.
//   5. Review cost and time per branch, and the cost per calendar month (UTC): the cost and
//      duration columns of the .harness/reviews.tsv lines dated in the period.
//      Misleading: reviews that failed before recording, and eval-reviewer.sh runs, cost
//      money but are not in reviews.tsv, so the cost is a floor; the time is the
//      reviewer's run time, not how long the person waited.
//   6. land.sh and ship.sh stops per branch: the STOPPED lines of land.sh and ship.sh in
//      the local event log dated in the period, over the branches with any land.sh or
//      ship.sh line there, with each branch's reasons. Labelled "local record, this machine
//      only". No log: NOT FOUND.
//      Misleading: only this machine's runs since the log was added are there, and a run
//      ended some other way (Ctrl-C, a crash, a usage error) leaves no line, so a branch
//      landed or shipped elsewhere looks like one that never stopped.
//
// THE BASELINE (--baseline) covers everything before the tag's commit: numbers 1, 3 and 5
// from the files as they are at the tag (NOT FOUND when a file did not exist there), 4
// from `gh run list` (runs whose branch's first run started before the tag; the base and
// ci-workflow as they are now), 2 and 6 NOT FOUND: the event log is not in git, so the
// files at the tag hold no record of either. It is written once: when
// .harness/baseline.tsv exists, --baseline refuses and changes nothing. The table then
// shows it next to each number.
//
// Exit status: 0 printed (and, with --baseline, written); 1 the baseline exists already or
// could not be written; 2 usage (an unknown option, no tag pre-harness without --since, a
// bad date).
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { isAbsolute, join, relative } from "node:path";

const TAG = "pre-harness";
const NOT_FOUND = "NOT FOUND";
const BASELINE = ".harness/baseline.tsv";
const DEFECTS = ".harness/defects.tsv";
const MUTATIONS = ".harness/mutations.tsv";
const REVIEWS = ".harness/reviews.tsv";
const CHECKLIST = ".harness/review-checklist.md";
const GH_LIMIT = 1000;
const WHERE = ["live", "review", "check", "person"];
const EVENT_FIELDS = ["date", "tool", "branch", "head", "event", "what", "detail"];
const LOCAL = "local record, this machine only";
const REVIEW_FIELDS = ["date", "branch", "base", "head", "diff", "verdict", "items", "cost", "duration"];
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const USAGE = "usage: harness-metrics.mjs [--since REF|YYYY-MM-DD] [--until YYYY-MM-DD] | --baseline";

const usage = (message) => {
  console.error(`harness-kit harness-metrics.mjs: ${message}`);
  process.exit(2);
};

const git = (args, cwd) => {
  const result = spawnSync("git", args, { cwd, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
  return result.status === 0 ? result.stdout : null;
};

const firstLine = (text) => (text ?? "").split(/\r?\n/).map((l) => l.trim()).find(Boolean) ?? "";

// Table lines: "# comment" and blank lines skipped; CR stripped; split on tabs.
const rows = (text) =>
  text
    .split("\n")
    .map((line) => line.replace(/\r$/, ""))
    .filter((line) => line.trim() !== "" && !line.startsWith("#"))
    .map((line) => line.split("\t"));

const notFound = (source) => ({ value: NOT_FOUND, source });
const skippedNote = (n, what) => (n > 0 ? `; ${n} line(s) not in the ${what} format were not counted` : "");
const dollars = (x) => `$${x.toFixed(2)}`;
const seconds = (x) => `${Math.round(x)}s`;
const dayOf = (date) => date.toISOString().slice(0, 10);

// ---------------------------------------------------------------------------------------
// The period: [start, end), either end open.
// ---------------------------------------------------------------------------------------
const period = (start, end, label) => ({
  label,
  contains: (timestamp) => {
    const t = new Date(timestamp);
    return !Number.isNaN(t.getTime()) && (!start || t >= start) && (!end || t < end);
  },
  containsDay: (day) => (!start || day >= dayOf(start)) && (!end || day < dayOf(end)),
});

// The committer date of REF's commit, or null.
const commitDate = (root, ref) => {
  const out = git(["log", "-1", "--format=%cI", `${ref}^{commit}`, "--"], root);
  return out ? new Date(out.trim()) : null;
};

const parseDay = (text, flag) => {
  const date = new Date(`${text}T00:00:00Z`);
  if (!DAY.test(text) || Number.isNaN(date.getTime())) usage(`${flag} takes a date as YYYY-MM-DD, not "${text}"`);
  return date;
};

// ---------------------------------------------------------------------------------------
// Where the files come from: the working tree, or the tag (for the baseline).
// ---------------------------------------------------------------------------------------
const workingTree = (root) => ({
  where: "",
  read: (path) => (existsSync(join(root, path)) ? readFileSync(join(root, path), "utf8") : null),
});
const atTag = (root) => ({
  where: ` at ${TAG}`,
  read: (path) => git(["show", `${TAG}^{commit}:${path}`], root),
});

// ---------------------------------------------------------------------------------------
// The local event log (numbers 2 and 6): { shown, events, skipped }, or { missing: why }.
// ---------------------------------------------------------------------------------------
const readEvents = (root) => {
  const common = git(["rev-parse", "--path-format=absolute", "--git-common-dir"], root)?.trim();
  if (!common) return { missing: "the git directory was not found, so there is no local event log" };
  const path = join(common, "harness-kit", "events.tsv");
  const rel = relative(root, path);
  const shown = rel.startsWith("..") || isAbsolute(rel) ? path : rel;
  if (!existsSync(path)) return { missing: `there is no local event log (${shown}): nothing has been recorded on this machine` };
  const all = rows(readFileSync(path, "utf8"));
  const events = all
    .filter((fields) => fields.length === EVENT_FIELDS.length)
    .map((fields) => Object.fromEntries(EVENT_FIELDS.map((name, i) => [name, fields[i]])))
    .filter((e) => !Number.isNaN(new Date(e.date).getTime()));
  return { shown, events, skipped: all.length - events.length };
};
const NO_LOG_AT_TAG = { missing: "the local event log is not in git, so the files at the tag hold no record of it" };

// ---------------------------------------------------------------------------------------
// 1. Escaped defects.
// ---------------------------------------------------------------------------------------
const escapedDefects = (src, when) => {
  const text = src.read(DEFECTS);
  if (text === null) return notFound(`${DEFECTS} did not exist${src.where}`);
  let skipped = 0;
  const counts = new Map();
  for (const fields of rows(text)) {
    if (fields.length !== 7 || !DAY.test(fields[0])) {
      skipped += 1;
      continue;
    }
    if (!when.containsDay(fields[0])) continue;
    counts.set(fields[3], (counts.get(fields[3]) ?? 0) + 1);
  }
  const total = [...counts.values()].reduce((a, b) => a + b, 0);
  const order = [...WHERE, ...[...counts.keys()].filter((w) => !WHERE.includes(w)).sort()];
  const parts = order.filter((w) => counts.has(w)).map((w) => `${w} ${counts.get(w)}`);
  return {
    value: total === 0 ? "0" : `${total} (${parts.join(", ")})`,
    source: `${DEFECTS}${src.where}: lines dated ${when.label}, by where-found${skippedNote(skipped, "7-field")}`,
  };
};

// ---------------------------------------------------------------------------------------
// 2. Planted faults caught.
// ---------------------------------------------------------------------------------------
const REPLAYED = /^killed=(\d+),survived=(\d+),error=(\d+)$/;
const plantedFaults = (src, when, log) => {
  const text = src.read(MUTATIONS);
  let planted = `${MUTATIONS} did not exist${src.where}`;
  if (text !== null) {
    const all = rows(text);
    const n = all.filter((fields) => fields.length === 5).length;
    planted = `${MUTATIONS}${src.where} plants ${n} (planted, not caught)${skippedNote(all.length - n, "5-field")}`;
  }
  if (log.missing) return notFound(`${log.missing}; ${planted}`);
  const runs = log.events.filter((e) => e.tool === "replay-faults.sh" && e.event === "REPLAYED" &&
    REPLAYED.test(e.what) && when.contains(e.date));
  const logNote = skippedNote(log.skipped, "7-field");
  if (runs.length === 0) {
    return notFound(`${LOCAL}: no replay-faults.sh run in ${log.shown} dated ${when.label}${logNote}; ${planted}`);
  }
  const full = runs.filter((e) => e.detail === "all");
  const last = (full.length > 0 ? full : runs)[(full.length > 0 ? full : runs).length - 1];
  const [killed, survived, errors] = REPLAYED.exec(last.what).slice(1).map(Number);
  const missed = [survived ? `${survived} SURVIVED` : "", errors ? `${errors} ERROR` : ""].filter(Boolean).join(", ");
  return {
    value: `${killed} of ${killed + survived + errors} caught${missed ? ` (${missed})` : ""}`,
    source:
      `${LOCAL}: the last ${full.length > 0 ? "full " : ""}replay-faults.sh run in ${log.shown} dated ${when.label} ` +
      `(${last.date}, head ${last.head.slice(0, 12)}${full.length > 0 ? "" : `, ${last.detail}; no run of every entry in the period`})` +
      `${logNote}; ${planted}`,
  };
};

// ---------------------------------------------------------------------------------------
// 3 and 5. Reviews.
// ---------------------------------------------------------------------------------------
const readReviews = (src) => {
  const text = src.read(REVIEWS);
  if (text === null) return null;
  const all = rows(text);
  const reviews = all
    .filter((fields) => fields.length === REVIEW_FIELDS.length)
    .map((fields) => Object.fromEntries(REVIEW_FIELDS.map((name, i) => [name, fields[i]])))
    .filter((r) => !Number.isNaN(new Date(r.date).getTime()) && Number.isFinite(Number(r.cost)) &&
      Number.isFinite(Number(r.duration)));
  return { reviews, skipped: all.length - reviews.length };
};

// Checklist item ID -> its text, as review-lib.sh reads the checklist.
const checklistItems = (src) => {
  const items = new Map();
  for (const line of (src.read(CHECKLIST) ?? "").split(/\r?\n/)) {
    const m = /^\s*(?:[-*]\s+)?\**([A-Za-z][A-Za-z0-9_-]*[0-9])\**:\s+(.*)$/.exec(line);
    if (m) items.set(m[1], m[2].trim());
  }
  return items;
};

const failedItems = (items) =>
  items.split(",").filter((pair) => pair.endsWith("=F")).map((pair) => pair.slice(0, -2));

const firstReviews = (src, when) => {
  const read = readReviews(src);
  if (read === null) return notFound(`${REVIEWS} did not exist${src.where}`);
  const first = new Map();
  for (const review of read.reviews) if (!first.has(review.branch)) first.set(review.branch, review);
  const branches = [...first.values()].filter((r) => when.contains(r.date));
  const notPass = branches.filter((r) => r.verdict !== "PASS");
  const why = new Map();
  for (const review of notPass) for (const id of failedItems(review.items)) why.set(id, (why.get(id) ?? 0) + 1);
  const whyText = [...why].map(([id, n]) => `${id} on ${n}`).join(", ");
  const text = checklistItems(src);
  return {
    value: `${notPass.length} of ${branches.length} branches${whyText ? `; failed: ${whyText}` : ""}`,
    source:
      `${REVIEWS}${src.where}: each branch's first review line, for branches first reviewed ${when.label}` +
      skippedNote(read.skipped, "9-field"),
    details: notPass.length === 0 ? null : {
      title: "3. First reviews that were not PASS, and why",
      rows: [
        ["branch", "date", "verdict", "failed items"],
        ...notPass.map((r) => {
          const ids = failedItems(r.items);
          return [r.branch, r.date, r.verdict,
            ids.length === 0 ? "none marked F" : ids.map((id) => (text.has(id) ? `${id}: ${text.get(id)}` : id)).join("; ")];
        }),
      ],
    },
  };
};

const reviewCost = (src, when) => {
  const read = readReviews(src);
  if (read === null) {
    const missing = notFound(`${REVIEWS} did not exist${src.where}`);
    return [missing, missing];
  }
  const inPeriod = read.reviews.filter((r) => when.contains(r.date));
  const byBranch = new Map();
  const byMonth = new Map();
  for (const r of inPeriod) {
    const b = byBranch.get(r.branch) ?? { reviews: 0, cost: 0, time: 0 };
    byBranch.set(r.branch, { reviews: b.reviews + 1, cost: b.cost + Number(r.cost), time: b.time + Number(r.duration) });
    const month = new Date(r.date).toISOString().slice(0, 7);
    const m = byMonth.get(month) ?? { reviews: 0, cost: 0 };
    byMonth.set(month, { reviews: m.reviews + 1, cost: m.cost + Number(r.cost) });
  }
  const n = byBranch.size;
  const total = [...byBranch.values()].reduce((a, b) => a + b.cost, 0);
  const time = [...byBranch.values()].reduce((a, b) => a + b.time, 0);
  const source = `${REVIEWS}${src.where}: cost-usd and duration-s of the lines dated ${when.label}${skippedNote(read.skipped, "9-field")}`;
  const months = [...byMonth].sort(([a], [b]) => (a < b ? -1 : 1));
  return [
    {
      value: n === 0 ? "0 branches" : `${dollars(total / n)} and ${seconds(time / n)} per branch (mean of ${n}); ${dollars(total)} in all`,
      source,
      details: n === 0 ? null : {
        title: "5. Review cost and time, per branch",
        rows: [
          ["branch", "reviews", "cost", "time"],
          ...[...byBranch].map(([branch, b]) => [branch, String(b.reviews), dollars(b.cost), seconds(b.time)]),
        ],
      },
    },
    {
      value: months.length === 0 ? "0 months" : months.map(([month, m]) => `${month} ${dollars(m.cost)}`).join(", "),
      source,
    },
  ];
};

// ---------------------------------------------------------------------------------------
// 4. First CI runs.
// ---------------------------------------------------------------------------------------
const firstCiRuns = (root, when) => {
  const read = (name) => firstLine(existsSync(join(root, name)) ? readFileSync(join(root, name), "utf8") : "");
  const base = read(".harness/review-base") || "main";
  const workflow = read(".harness/ci-workflow");
  const args = ["run", "list", "--limit", String(GH_LIMIT),
    "--json", "databaseId,headBranch,headSha,status,conclusion,createdAt,workflowName"];
  if (workflow) args.push("--workflow", workflow);
  const result = spawnSync("gh", args, { cwd: root, encoding: "utf8", timeout: 120000, maxBuffer: 256 * 1024 * 1024 });
  if (result.error || result.status !== 0) {
    return notFound(`gh run list failed: ${firstLine(result.stderr) || result.error?.message || `exit ${result.status}`}`);
  }
  let runs;
  try {
    runs = JSON.parse(result.stdout);
  } catch {
    runs = null;
  }
  if (!Array.isArray(runs)) return notFound("gh run list did not print a JSON list");

  const byBranch = new Map();
  for (const run of runs) {
    if (!run || typeof run.headBranch !== "string" || run.headBranch === "" || run.headBranch === base) continue;
    if (Number.isNaN(new Date(run.createdAt).getTime())) continue;
    byBranch.set(run.headBranch, [...(byBranch.get(run.headBranch) ?? []), run]);
  }
  const judged = [];
  for (const [branch, list] of byBranch) {
    list.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt) || (a.databaseId ?? 0) - (b.databaseId ?? 0));
    const first = list[0];
    if (!when.contains(first.createdAt)) continue;
    const firstRuns = list.filter((run) => run.headSha === first.headSha);
    const result = firstRuns.some((run) => run.status !== "completed")
      ? "still running"
      : firstRuns.every((run) => run.conclusion === "success")
        ? "green"
        : `not green: ${firstRuns.map((run) => `${run.workflowName ?? "?"} ${run.conclusion || "no conclusion"}`).join(", ")}`;
    judged.push([branch, String(first.headSha ?? "").slice(0, 12), first.createdAt, result]);
  }
  const running = judged.filter((j) => j[3] === "still running").length;
  const green = judged.filter((j) => j[3] === "green").length;
  return {
    value: `${green} of ${judged.length - running} branches${running ? `; ${running} still running, not counted` : ""}`,
    source:
      `gh run list (read-only${workflow ? `, workflow ${workflow} from .harness/ci-workflow` : ""}): every branch but ${base}, ` +
      `by the runs for its first commit, for branches whose first run started ${when.label}` +
      (runs.length >= GH_LIMIT ? `; gh returned its limit of ${GH_LIMIT} runs, so older runs were not seen` : ""),
    details: judged.length === 0 ? null : {
      title: "4. First CI runs, per branch",
      rows: [["branch", "commit", "started", "result"], ...judged],
    },
  };
};

// ---------------------------------------------------------------------------------------
// 6. land.sh and ship.sh stops.
// ---------------------------------------------------------------------------------------
const stops = (when, log) => {
  if (log.missing) return notFound(log.missing);
  const byBranch = new Map();
  for (const e of log.events) {
    if ((e.tool !== "land.sh" && e.tool !== "ship.sh") || !when.contains(e.date)) continue;
    const b = byBranch.get(e.branch) ?? { "land.sh": 0, "ship.sh": 0, LANDED: 0, SHIPPED: 0, why: new Map() };
    if (e.event === "STOPPED") {
      b[e.tool] += 1;
      b.why.set(e.what, (b.why.get(e.what) ?? 0) + 1);
    } else if (e.event === "LANDED" || e.event === "SHIPPED") {
      b[e.event] += 1;
    }
    byBranch.set(e.branch, b);
  }
  const n = byBranch.size;
  const land = [...byBranch.values()].reduce((a, b) => a + b["land.sh"], 0);
  const ship = [...byBranch.values()].reduce((a, b) => a + b["ship.sh"], 0);
  return {
    value: n === 0 ? "0 branches" : `${((land + ship) / n).toFixed(1)} per branch (mean of ${n}; land.sh ${land}, ship.sh ${ship})`,
    source:
      `${LOCAL}: the STOPPED lines of land.sh and ship.sh in ${log.shown} dated ${when.label}, ` +
      `over the branches with any land.sh or ship.sh line${skippedNote(log.skipped, "7-field")}`,
    details: n === 0 ? null : {
      title: "6. land.sh and ship.sh, per branch (local record, this machine only)",
      rows: [
        ["branch", "land.sh stops", "ship.sh stops", "landed", "shipped", "why"],
        ...[...byBranch].map(([branch, b]) => [branch, String(b["land.sh"]), String(b["ship.sh"]), String(b.LANDED),
          String(b.SHIPPED), [...b.why].map(([what, k]) => `${what} ${k}`).join(", ") || "-"]),
      ],
    },
  };
};

// ---------------------------------------------------------------------------------------
// All of them.
// ---------------------------------------------------------------------------------------
const measure = (root, src, when, log) => {
  const [cost, monthly] = reviewCost(src, when);
  return [
    ["1", "escaped defects", escapedDefects(src, when)],
    ["2", "planted faults caught", plantedFaults(src, when, log)],
    ["3", "reviews not PASS on the first try", firstReviews(src, when)],
    ["4", "branches whose first CI run was green", firstCiRuns(root, when)],
    ["5a", "review cost and time per branch", cost],
    ["5b", "review cost per month", monthly],
    ["6", "land.sh and ship.sh stops per branch", stops(when, log)],
  ];
};

const table = (lines, indent = "") => {
  const widths = lines[0].map((_, i) => Math.max(...lines.map((line) => line[i].length)));
  return lines
    .map((line) => indent + line.map((cell, i) => (i === line.length - 1 ? cell : cell.padEnd(widths[i]))).join("  "))
    .join("\n");
};

const oneLine = (text) => text.replace(/[\t\r\n]+/g, " ");

const main = () => {
  const args = process.argv.slice(2);
  let since = null;
  let until = null;
  let baseline = false;
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--baseline") baseline = true;
    else if ((args[i] === "--since" || args[i] === "--until") && args[i + 1] !== undefined) {
      if (args[i] === "--since") since = args[i + 1];
      else until = args[i + 1];
      i += 1;
    } else usage(`unknown or incomplete argument "${args[i]}". ${USAGE}`);
  }
  if (baseline && (since !== null || until !== null)) usage(`--baseline takes no other option; it always covers everything before the tag ${TAG}. ${USAGE}`);

  const root = git(["rev-parse", "--show-toplevel"])?.trim();
  if (!root) usage("not inside a git repository");

  if (baseline) {
    const path = join(root, BASELINE);
    if (existsSync(path)) {
      console.error(`harness-kit harness-metrics.mjs: ${BASELINE} exists already, and the baseline is written once; nothing was changed. Delete it yourself only if it is wrong.`);
      process.exit(1);
    }
    const tagDate = commitDate(root, TAG);
    if (!tagDate) usage(`there is no tag ${TAG}; tag the last commit before the harness (git tag ${TAG} <commit>), then run --baseline`);
    const sha = git(["rev-parse", `${TAG}^{commit}`], root).trim();
    const results = measure(root, atTag(root), period(null, tagDate, `before ${tagDate.toISOString()}`), NO_LOG_AT_TAG);
    const text = [
      `# harness-kit baseline: the numbers for everything before the tag ${TAG} (commit ${sha}, ${tagDate.toISOString()}),`,
      `# written once by harness-metrics.mjs --baseline on ${new Date().toISOString()}. ${NOT_FOUND} means the old records`,
      `# cannot show it; nothing is estimated. Tab-separated: number, value, source.`,
      ...results.map(([id, , r]) => [id, oneLine(r.value), oneLine(r.source)].join("\t")),
    ].join("\n") + "\n";
    try {
      writeFileSync(path, text, { flag: "wx" });
    } catch (error) {
      console.error(`harness-kit harness-metrics.mjs: could not write ${BASELINE}: ${error.message}`);
      process.exit(1);
    }
    console.log(`harness-metrics: before the tag ${TAG} (commit ${sha.slice(0, 12)}, ${tagDate.toISOString()})\n`);
    console.log(table([["#", "number", "value", "source"], ...results.map(([id, name, r]) => [id, name, r.value, r.source])]));
    console.log(`\nWrote ${BASELINE}. Commit it; it is written once.`);
    process.exit(0);
  }

  let start;
  let startLabel;
  if (since === null || !DAY.test(since)) {
    const ref = since ?? TAG;
    start = commitDate(root, ref);
    if (!start) {
      usage(since === null
        ? `there is no tag ${TAG}, the default start; tag the last commit before the harness (git tag ${TAG} <commit>), or pass --since REF|YYYY-MM-DD`
        : `--since "${since}" is neither a date (YYYY-MM-DD) nor a commit in this repository`);
    }
    const sha = git(["rev-parse", `${ref}^{commit}`], root).trim().slice(0, 12);
    startLabel = `${start.toISOString()} (${since === null ? `the tag ${TAG}` : ref}, commit ${sha})`;
  } else {
    start = parseDay(since, "--since");
    startLabel = start.toISOString();
  }
  const end = until === null ? null : new Date(parseDay(until, "--until").getTime() + 24 * 3600 * 1000);
  if (end && end <= start) usage("--until is before the start of the period");
  const endLabel = end ? end.toISOString() : "now";
  const results = measure(root, workingTree(root), period(start, end, `from ${dayOf(start)} ${end ? `to ${until}` : "on"}`),
    readEvents(root));

  const saved = new Map();
  const savedText = workingTree(root).read(BASELINE);
  if (savedText !== null) for (const fields of rows(savedText)) if (fields.length >= 2) saved.set(fields[0], fields[1]);
  const header = savedText === null ? ["#", "number", "value", "source"] : ["#", "number", "value", "baseline", "source"];
  const lines = results.map(([id, name, r]) =>
    savedText === null ? [id, name, r.value, r.source] : [id, name, r.value, saved.get(id) ?? NOT_FOUND, r.source]);

  console.log(`harness-metrics: from ${startLabel} to ${endLabel}\n`);
  console.log(table([header, ...lines]));
  for (const [, , r] of results) {
    if (r.details) console.log(`\n${r.details.title}:\n${table(r.details.rows, "  ")}`);
  }
  console.log(savedText === null
    ? `\nNo ${BASELINE}: run harness-metrics.mjs --baseline once to write the numbers from before the tag ${TAG}.`
    : `\nbaseline: ${BASELINE}, everything before the tag ${TAG}.`);
  process.exit(0);
};

main();
