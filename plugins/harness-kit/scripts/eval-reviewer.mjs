#!/usr/bin/env node
// The parts of eval-reviewer.sh that are easier in JavaScript. See eval-reviewer.sh for what
// the cases, the grades and the totals mean.
//
//   node eval-reviewer.mjs cases CASES_TSV PROJECT READ_COUNT ID_LIST
//       Check every case against the checklist's IDs (ID_LIST, "R1,R2,..."); print them
//       one per line, 9 tab-separated fields, with every empty field as "-" and a spec
//       replacement as an absolute path. Exit 1 with the problems if any.
//   node eval-reviewer.mjs grade REVIEW_TXT KIND FILE_RE KEYWORD_RE VERDICT ITEMS NA_ITEMS EXPECTED_ITEM
//       Print CAUGHT or MISSED for a defect, CLEAN or FALSE ALARM for a control.
//   node eval-reviewer.mjs result TRANSCRIPT OUT_JSON
//       Write the last "result" event of a stream-json transcript to OUT_JSON, the same
//       JSON `--output-format json` prints; write nothing if there is none.
//   node eval-reviewer.mjs cost OUT_JSON
//       Print "cost duration" from a run's JSON output, 0 for what it lacks: a run that
//       failed still spent money.
//   node eval-reviewer.mjs summary RESULTS_TSV REPEAT
//       Print one line per run, then the totals.
//   node eval-reviewer.mjs regrade RESULTS_DIR < CASES
//       Grade the saved runs in RESULTS_DIR again, with this grader and CASES (the output
//       of `cases`); write RESULTS_DIR/regraded.tsv and print its summary. Exit 1 if a run
//       is an ERROR.
import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const cases = (file, project, readCount, idList) => {
  const ids = new Set(idList.split(","));
  const problems = [];
  const seen = new Set();
  const out = [];
  readFileSync(file, "utf8").split(/\r?\n/).forEach((raw, i) => {
    const where = `cases.tsv line ${i + 1}`;
    if (raw.trim() === "" || raw.trimStart().startsWith("#")) return;
    const f = raw.split("\t").map((field) => field.trim()).map((field) => (field === "-" ? "" : field));
    if (f.length < 6 || f.length > 9) {
      problems.push(`${where}: ${f.length} fields, not 6 to 9`);
      return;
    }
    const [id, kind, base, head, fileRe, keywordRe, spec = "", naItems = "", expected = ""] = f;
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
    const na = naItems ? naItems.split(",").map((i) => i.trim()) : [];
    for (const i of na) if (!ids.has(i)) problems.push(`${where}: na_items names "${i}", which is not a checklist item (${idList})`);
    if (expected) {
      if (kind !== "defect") problems.push(`${where}: expected_item is for a defect, not a ${kind}`);
      if (!ids.has(expected)) problems.push(`${where}: expected_item "${expected}" is not a checklist item (${idList})`);
      if (na.includes(expected)) problems.push(`${where}: expected_item "${expected}" is also in na_items`);
    }
    let specPath = "";
    if (spec) {
      specPath = resolve(project, spec);
      if (!existsSync(specPath) || !statSync(specPath).isFile()) problems.push(`${where}: the spec replacement ${spec} does not exist`);
      if (readCount === "0") problems.push(`${where}: a spec replacement needs a spec: list it first in .harness/review-reads`);
    }
    out.push([id, kind, base, head, fileRe || "-", keywordRe || "-", specPath || "-", na.join(",") || "-", expected || "-"].join("\t"));
  });
  if (out.length === 0) problems.push("cases.tsv has no cases");
  if (problems.length) {
    console.error(problems.join("\n"));
    process.exit(1);
  }
  console.log(out.join("\n"));
};

// Split a review into its item blocks and its findings. An item block begins at a line
// that starts with a checklist ID and holds the lines below it; its text has the leading
// "ID — STATUS —" prefix stripped, so the status word is never matched as the defect's
// keyword. A finding begins at each bullet, numbered point or sub-heading of the Findings
// section.
const parseReview = (text, ids) => {
  const lines = text.split(/\r?\n/);
  const isHeading = (l) => /^#{1,2}\s/.test(l);
  const headingAt = (name) => lines.findIndex((l) => isHeading(l) && new RegExp(`^#{1,2}\\s+${name}\\b`, "i").test(l));
  const section = (name) => {
    const start = headingAt(name);
    if (start < 0) return null;
    const end = lines.findIndex((l, i) => i > start && isHeading(l));
    return lines.slice(start + 1, end < 0 ? lines.length : end);
  };
  const findingsAt = headingAt("Findings");

  const items = [];
  let item = null;
  for (const l of section("Items") ?? lines.slice(0, findingsAt < 0 ? lines.length : findingsAt)) {
    if (l.startsWith("VERDICT")) break;
    const bare = l.replace(/^\s*(?:[-*+]\s+)?[*_`]*/, "");
    const id = ids.find((i) => bare.startsWith(i) && !/[A-Za-z0-9_-]/.test(bare[i.length] ?? ""));
    if (id) {
      const rest = bare
        .slice(id.length)
        .replace(/^[*_`]*\s*(?:[—–:|-]+\s*)?[*_`]*(?:PASS|FAIL|NA|P|F)\b[*_`]*\s*(?:[—–:|-]+\s*)?/i, "");
      item = { id, lines: [rest] };
      items.push(item);
    } else if (item) item.lines.push(l);
  }
  const findings = [];
  let finding = null;
  for (const l of section("Findings") ?? []) {
    if (finding === null || /^\s*(?:[-*+]|\d+[.)]|#{3,})\s/.test(l)) {
      finding = [l];
      findings.push(finding);
    } else finding.push(l);
  }
  return {
    items: items.map((i) => ({ id: i.id, text: i.lines.join("\n") })),
    findings: findings.map((f) => f.join("\n")),
  };
};

// Rule A: a defect is CAUGHT only if the verdict is not PASS and the file regex and the
// keyword regex both match inside ONE failed item's text or ONE finding's text; or, with
// an expected item, if that item FAILED and its text matches the keyword regex. A control
// is CLEAN on PASS, or when every FAILED item is in its na_items and there is no finding
// ("None." is not one): a FAIL on an item the input said to mark NA is not a false alarm.
const gradeRun = ({ text, kind, fileRe, keywordRe, verdict, items, naItems, expectedItem }) => {
  const pairs = items.split(",").map((pair) => pair.split("="));
  const failed = new Set(pairs.filter(([, v]) => v === "F").map(([id]) => id));
  const review = parseReview(text, pairs.map(([id]) => id));
  if (kind === "control") {
    if (verdict === "PASS") return "CLEAN";
    const na = new Set(naItems && naItems !== "-" ? naItems.split(",") : []);
    const realFindings = review.findings.filter((f) => f.trim() !== "" && !/^\s*(?:[-*+]\s+)?none\b/i.test(f));
    const onlyNa = failed.size > 0 && [...failed].every((id) => na.has(id));
    return onlyNa && realFindings.length === 0 ? "CLEAN" : "FALSE ALARM";
  }
  if (verdict === "PASS") return "MISSED";
  const fileMatch = new RegExp(fileRe, "i");
  const keywordMatch = new RegExp(keywordRe, "i");
  const failedTexts = review.items.filter((i) => failed.has(i.id)).map((i) => i.text);
  if ([...failedTexts, ...review.findings].some((t) => fileMatch.test(t) && keywordMatch.test(t))) return "CAUGHT";
  if (expectedItem && expectedItem !== "-" && failed.has(expectedItem) &&
    review.items.some((i) => i.id === expectedItem && keywordMatch.test(i.text))) return "CAUGHT";
  return "MISSED";
};

const grade = (file, kind, fileRe, keywordRe, verdict, items, naItems = "-", expectedItem = "-") =>
  gradeRun({ text: readFileSync(file, "utf8"), kind, fileRe, keywordRe, verdict, items, naItems, expectedItem });

const result = (transcript, outFile) => {
  let last = null;
  for (const line of readFileSync(transcript, "utf8").split("\n")) {
    try {
      const event = JSON.parse(line);
      if (event?.type === "result") last = event;
    } catch {
      // Not a JSON line: skip it.
    }
  }
  if (last) writeFileSync(outFile, JSON.stringify(last));
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

const regrade = (dir) => {
  const byId = new Map();
  for (const line of readFileSync(0, "utf8").split("\n").filter(Boolean)) {
    const [id, kind, , , fileRe, keywordRe, , naItems, expectedItem] = line.split("\t");
    byId.set(id, { kind, fileRe, keywordRe, naItems, expectedItem });
  }
  const rows = readFileSync(`${dir}/results.tsv`, "utf8").trim().split("\n").slice(1);
  const out = ["id\trun\tkind\tverdict\toutcome\tcost-usd\tduration-s"];
  let repeat = 1;
  for (const row of rows) {
    const [id, run, , , , cost, duration] = row.split("\t");
    const c = byId.get(id);
    if (!c) {
      console.error(`eval-reviewer.mjs: ${id} run ${run} is left out: case "${id}" is no longer in cases.tsv`);
      continue;
    }
    repeat = Math.max(repeat, Number(run));
    const runDir = `${dir}/runs/${id}.${run}`;
    let verdict = "-";
    let outcome = "ERROR";
    if (existsSync(`${runDir}/record.tsv`) && existsSync(`${runDir}/review.txt`)) {
      let items;
      [verdict, items] = readFileSync(`${runDir}/record.tsv`, "utf8").split("\t");
      outcome = gradeRun({ text: readFileSync(`${runDir}/review.txt`, "utf8"), ...c, verdict, items });
    }
    out.push([id, run, c.kind, verdict, outcome, cost, duration].join("\t"));
  }
  writeFileSync(`${dir}/regraded.tsv`, out.join("\n") + "\n");
  summary(`${dir}/regraded.tsv`, String(repeat));
  if (out.some((l) => l.split("\t")[4] === "ERROR")) process.exit(1);
};

const [command, ...args] = process.argv.slice(2);
if (command === "cases") cases(...args);
else if (command === "grade") console.log(grade(...args));
else if (command === "result") result(...args);
else if (command === "cost") cost(...args);
else if (command === "regrade") regrade(...args);
else if (command === "summary") summary(...args);
else {
  console.error(`eval-reviewer.mjs: unknown command "${command}"`);
  process.exit(1);
}
