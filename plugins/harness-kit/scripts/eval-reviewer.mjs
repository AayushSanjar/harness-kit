#!/usr/bin/env node
// The parts of eval-reviewer.sh that are easier in JavaScript. See eval-reviewer.sh for what
// the cases, the grades and the totals mean.
//
//   node eval-reviewer.mjs cases CASES_TSV PROJECT READ_COUNT
//       Check every case; print them one per line, tab-separated, with every empty field
//       as "-" and a spec replacement as an absolute path. Exit 1 with the problems if any.
//   node eval-reviewer.mjs grade REVIEW_TXT KIND FILE_RE KEYWORD_RE VERDICT ITEMS
//       Print CAUGHT or MISSED for a defect, CLEAN or FALSE ALARM for a control.
//   node eval-reviewer.mjs cost OUT_JSON
//       Print "cost duration" from a run's JSON output, 0 for what it lacks: a run that
//       failed still spent money.
//   node eval-reviewer.mjs summary RESULTS_TSV REPEAT
//       Print one line per run, then the totals.
import { existsSync, readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";

const cases = (file, project, readCount) => {
  const problems = [];
  const seen = new Set();
  const out = [];
  readFileSync(file, "utf8").split(/\r?\n/).forEach((raw, i) => {
    const where = `cases.tsv line ${i + 1}`;
    if (raw.trim() === "" || raw.trimStart().startsWith("#")) return;
    const f = raw.split("\t").map((field) => field.trim()).map((field) => (field === "-" ? "" : field));
    if (f.length < 6 || f.length > 7) {
      problems.push(`${where}: ${f.length} fields, not 6 or 7`);
      return;
    }
    const [id, kind, base, head, fileRe, keywordRe, spec = ""] = f;
    if (!/^[A-Za-z0-9._-]+$/.test(id)) problems.push(`${where}: the id "${id}" is not letters, digits, ".", "_" and "-"`);
    else if (seen.has(id)) problems.push(`${where}: the id "${id}" is used twice`);
    seen.add(id);
    if (kind !== "defect" && kind !== "control") problems.push(`${where}: kind "${kind}" is not defect or control`);
    if (!base || !head) problems.push(`${where}: base and head commits are required`);
    if (kind === "defect") {
      for (const [what, re] of [["file", fileRe], ["keyword", keywordRe]]) {
        if (!re) {
          problems.push(`${where}: a defect needs a ${what} regex`);
          continue;
        }
        try {
          new RegExp(re, "i");
        } catch (error) {
          problems.push(`${where}: the ${what} regex does not compile: ${error.message}`);
        }
      }
    }
    let specPath = "";
    if (spec) {
      specPath = resolve(project, spec);
      if (!existsSync(specPath) || !statSync(specPath).isFile()) problems.push(`${where}: the spec replacement ${spec} does not exist`);
      if (readCount === "0") problems.push(`${where}: a spec replacement needs a spec: list it first in .harness/review-reads`);
    }
    out.push([id, kind, base, head, fileRe || "-", keywordRe || "-", specPath || "-"].join("\t"));
  });
  if (out.length === 0) problems.push("cases.tsv has no cases");
  if (problems.length) {
    console.error(problems.join("\n"));
    process.exit(1);
  }
  console.log(out.join("\n"));
};

// A defect is CAUGHT only if the verdict is not PASS and a FAILED item's text or a
// finding's text matches both regexes.
const grade = (file, kind, fileRe, keywordRe, verdict, items) => {
  if (kind === "control") return verdict === "PASS" ? "CLEAN" : "FALSE ALARM";
  if (verdict === "PASS") return "MISSED";
  const lines = readFileSync(file, "utf8").split(/\r?\n/);
  const isHeading = (l) => /^#{1,2}\s/.test(l);
  const headingAt = (name) => lines.findIndex((l) => isHeading(l) && new RegExp(`^#{1,2}\\s+${name}\\b`, "i").test(l));
  const section = (name) => {
    const start = headingAt(name);
    if (start < 0) return null;
    const end = lines.findIndex((l, i) => i > start && isHeading(l));
    return lines.slice(start + 1, end < 0 ? lines.length : end);
  };
  const findingsAt = headingAt("Findings");

  // Item blocks: a line that starts with a checklist ID begins one, and the lines below it
  // belong to it. The VERDICT line says which items FAILED.
  const pairs = items.split(",").map((pair) => pair.split("="));
  const failed = new Set(pairs.filter(([, v]) => v === "F").map(([id]) => id));
  const idOf = (l) => {
    const bare = l.replace(/^\s*(?:[-*+]\s+)?[*_`]*/, "");
    return pairs.map(([id]) => id).find((id) => bare.startsWith(id) && !/[A-Za-z0-9_-]/.test(bare[id.length] ?? ""));
  };
  const texts = [];
  let item = null;
  for (const l of section("Items") ?? lines.slice(0, findingsAt < 0 ? lines.length : findingsAt)) {
    if (l.startsWith("VERDICT")) break;
    const id = idOf(l);
    if (id) {
      item = failed.has(id) ? [l] : null;
      if (item) texts.push(item);
    } else if (item) item.push(l);
  }
  // Findings: each bullet, numbered point or sub-heading begins one.
  let finding = null;
  for (const l of section("Findings") ?? []) {
    if (finding === null || /^\s*(?:[-*+]|\d+[.)]|#{3,})\s/.test(l)) {
      finding = [l];
      texts.push(finding);
    } else finding.push(l);
  }
  const fileMatch = new RegExp(fileRe, "i");
  const keywordMatch = new RegExp(keywordRe, "i");
  return texts.map((t) => t.join("\n")).some((t) => fileMatch.test(t) && keywordMatch.test(t)) ? "CAUGHT" : "MISSED";
};

const cost = (file) => {
  let out = {};
  try {
    out = JSON.parse(readFileSync(file, "utf8"));
  } catch {
    // No JSON: nothing to count.
  }
  const usd = Number(out.total_cost_usd);
  const ms = Number(out.duration_ms);
  console.log(`${(Number.isFinite(usd) ? usd : 0).toFixed(4)} ${(Number.isFinite(ms) ? ms / 1000 : 0).toFixed(1)}`);
};

const summary = (file, repeatArg) => {
  const repeat = Number(repeatArg);
  const rows = readFileSync(file, "utf8").trim().split("\n").slice(1).map((l) => {
    const [id, run, kind, verdict, outcome, cost, duration] = l.split("\t");
    return {
      label: repeat > 1 ? `${id}#${run}` : id, id, kind, verdict, outcome, cost: Number(cost), duration: Number(duration),
    };
  });
  const width = Math.max(4, ...rows.map((r) => r.label.length));
  const line = (...f) =>
    `${f[0].padEnd(width)}  ${f[1].padEnd(7)}  ${f[2].padEnd(9)}  ${f[3].padEnd(11)}  ${f[4].padStart(9)}  ${f[5].padStart(7)}`;
  console.log(line("id", "kind", "verdict", "outcome", "cost", "seconds"));
  for (const r of rows) console.log(line(r.label, r.kind, r.verdict, r.outcome, `$${r.cost.toFixed(4)}`, r.duration.toFixed(1)));

  const right = (r) => r.outcome === (r.kind === "defect" ? "CAUGHT" : "CLEAN");
  const pct = (a, b) => (b === 0 ? "n/a" : `${((100 * a) / b).toFixed(1)}%`);
  const defects = rows.filter((r) => r.kind === "defect");
  const controls = rows.filter((r) => r.kind === "control");
  const caught = defects.filter(right).length;
  const alarms = controls.filter((r) => !right(r)).length;
  console.log("");
  console.log(`catch rate:        ${pct(caught, defects.length)} (${caught} of ${defects.length} defect runs CAUGHT)`);
  console.log(`false-alarm rate:  ${pct(alarms, controls.length)} (${alarms} of ${controls.length} control runs FALSE ALARM or ERROR)`);
  if (repeat > 1) {
    const byCase = new Map();
    for (const r of rows) byCase.set(r.id, [...(byCase.get(r.id) ?? []), r]);
    const report = (label, test) => {
      const parts = ["defect", "control"].map((kind) => {
        const of = [...byCase.values()].filter((runs) => runs[0].kind === kind);
        const ok = of.filter(test).length;
        return `${kind}s ${pct(ok, of.length)} (${ok} of ${of.length})`;
      });
      console.log(`${`${label}:`.padEnd(19)}${parts.join(", ")}`);
    };
    report(`pass@${repeat}`, (runs) => runs.some(right));
    report(`pass^${repeat}`, (runs) => runs.every(right));
  }
  console.log(`errors:            ${rows.filter((r) => r.outcome === "ERROR").length} of ${rows.length} runs`);
  console.log(`total cost:        $${rows.reduce((s, r) => s + r.cost, 0).toFixed(4)}`);
  console.log(`total time:        ${rows.reduce((s, r) => s + r.duration, 0).toFixed(1)}s`);
};

const [command, ...args] = process.argv.slice(2);
if (command === "cases") cases(...args);
else if (command === "grade") console.log(grade(...args));
else if (command === "cost") cost(...args);
else if (command === "summary") summary(...args);
else {
  console.error(`eval-reviewer.mjs: unknown command "${command}"`);
  process.exit(1);
}
