#!/usr/bin/env node
// The parts of replay-faults.sh and land.sh that read tables and text; see replay-faults.sh
// for the formats and what a replay is.
//
//   node replay-faults.mjs list MUTATIONS [ID...]
//       Checks every entry of MUTATIONS and prints "<id>\t<file>\t<check>" for each one
//       asked for (all when no ID is given), in file order. Exit 2, with every problem on
//       stderr, when the file is unusable or an ID is not in it.
//   node replay-faults.mjs apply MUTATIONS ID ROOT
//       Replaces the entry's text in ROOT/<file>. Exit 0 when replaced; exit 1, printing
//       why (the ERROR reason), when the file is missing or the text is not found exactly
//       once.
//   node replay-faults.mjs baseline CHECK LOG STATUS
//       Without the fault: exit 0 when LOG has a PASS line for CHECK and no FAIL line for it;
//       otherwise exit 1, printing why.
//   node replay-faults.mjs verdict CHECK LOG STATUS
//       With the fault: prints KILLED when LOG has a FAIL line for CHECK and STATUS (the
//       check command's exit status) is not 0; otherwise SURVIVED and why.
//   node replay-faults.mjs select MUTATIONS CHECK_FILES CHANGED
//       For land.sh: prints, one per line, the IDs of the entries whose own file is among
//       the paths in CHANGED (a file of paths, one per line), or whose check has a
//       CHECK_FILES path among them. Notes on stderr name the checks with no CHECK_FILES
//       line. Exit 2, as list does, when MUTATIONS is unusable.
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

const FIELDS = ["id", "file", "find", "replacement", "check"];
const ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

const read = (path) => (existsSync(path) ? readFileSync(path, "utf8") : null);
const escape = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

// Table lines: "# comment" and blank lines skipped; CR stripped. Returns [lineNumber, fields].
const rows = (text) =>
  (text ?? "")
    .split("\n")
    .map((line, i) => [i + 1, line.replace(/\r$/, "")])
    .filter(([, line]) => line.trim() !== "" && !line.startsWith("#"))
    .map(([n, line]) => [n, line.split("\t")]);

const mutations = (path) => {
  const text = read(path);
  if (text === null) return { entries: [], problems: [`${path} does not exist`] };
  const entries = [];
  const problems = [];
  const seen = new Set();
  for (const [n, fields] of rows(text)) {
    const where = `${path} line ${n}`;
    if (fields.length !== FIELDS.length) {
      problems.push(`${where} has ${fields.length} tab-separated fields, not ${FIELDS.length} (id, file, find, replacement, check)`);
      continue;
    }
    const entry = Object.fromEntries(FIELDS.map((name, i) => [name, fields[i]]));
    if (!ID.test(entry.id)) problems.push(`${where}: the id "${entry.id}" must be letters, digits, ".", "_" or "-"`);
    else if (seen.has(entry.id)) problems.push(`${where}: the id ${entry.id} is used twice`);
    seen.add(entry.id);
    if (entry.file === "" || isAbsolute(entry.file) || entry.file.split("/").includes("..")) {
      problems.push(`${where}: the file "${entry.file}" must be a path inside the project, relative to its root`);
    }
    if (entry.find === "") problems.push(`${where}: the text to find is empty`);
    if (entry.find === entry.replacement) problems.push(`${where}: the replacement is the text to find, so there is no fault`);
    if (entry.check.trim() === "") problems.push(`${where}: the check name is empty`);
    entries.push(entry);
  }
  if (problems.length === 0 && entries.length === 0) problems.push(`${path} has no entries`);
  return { entries, problems };
};

// A line reporting CHECK with WORD (PASS or FAIL): the word, whitespace, then the name,
// then the end of the line, whitespace, ":" or "(". So "FAIL  lint  (exit 1)",
// "FAIL lint: 2 errors" and "FAIL lint" all report lint; "FAIL lint-extra" does not.
const reports = (word, check, log) => {
  const re = new RegExp(`^\\s*${word}\\s+${escape(check)}(?:$|[\\s:(])`);
  return (read(log) ?? "").split("\n").some((line) => re.test(line.replace(/\r$/, "")));
};

const die = (message, code = 2) => {
  process.stderr.write(`${message}\n`);
  process.exit(code);
};

const [command, ...args] = process.argv.slice(2);

if (command === "list") {
  const [path, ...ids] = args;
  const { entries, problems } = mutations(path);
  const byId = new Map(entries.map((e) => [e.id, e]));
  for (const id of ids) if (!byId.has(id)) problems.push(`no entry with the id "${id}" in ${path}`);
  if (problems.length > 0) die(problems.join("\n"));
  const wanted = ids.length === 0 ? entries : entries.filter((e) => ids.includes(e.id));
  for (const e of wanted) console.log(`${e.id}\t${e.file}\t${e.check}`);
} else if (command === "apply") {
  const [path, id, root] = args;
  const entry = mutations(path).entries.find((e) => e.id === id);
  if (!entry) die(`no entry with the id "${id}" in ${path}`);
  const target = join(root, entry.file);
  const text = read(target);
  if (text === null) {
    console.log(`${entry.file} does not exist`);
    process.exit(1);
  }
  const count = text.split(entry.find).length - 1;
  if (count !== 1) {
    console.log(
      count === 0
        ? `the text to find is not in ${entry.file}`
        : `the text to find is in ${entry.file} ${count} times, not once; make it longer so it names one place`,
    );
    process.exit(1);
  }
  writeFileSync(target, text.replace(entry.find, () => entry.replacement));
} else if (command === "baseline") {
  const [check, log, status] = args;
  if (reports("FAIL", check, log)) {
    console.log(`the check "${check}" already fails without the fault (exit ${status}), so a failure with it would prove nothing`);
    process.exit(1);
  }
  if (!reports("PASS", check, log)) {
    console.log(`without the fault the check command printed no PASS line for "${check}" (exit ${status}); is the name right?`);
    process.exit(1);
  }
} else if (command === "verdict") {
  const [check, log, status] = args;
  const failed = reports("FAIL", check, log);
  if (failed && status !== "0") console.log("KILLED");
  else if (failed) console.log(`SURVIVED\tit printed FAIL for "${check}" but the check command exited 0, so nothing would stop`);
  else console.log(`SURVIVED\t"${check}" did not fail with the fault in place (the check command exited ${status})`);
} else if (command === "select") {
  const [path, checkFiles, changedList] = args;
  const { entries, problems } = mutations(path);
  if (problems.length > 0) die(problems.join("\n"));
  const files = new Map();
  for (const [, fields] of rows(read(checkFiles))) {
    if (fields.length !== 2 || fields[0] === "" || fields[1] === "") continue;
    const [name, file] = fields;
    if (!files.has(name)) files.set(name, []);
    files.get(name).push(file.replace(/^\.\//, ""));
  }
  const changed = (read(changedList) ?? "").split("\n").filter(Boolean);
  const touches = (entry) => changed.some((p) => entry.endsWith("/") ? p.startsWith(entry) : p === entry);
  const unmapped = new Set();
  for (const e of entries) {
    const mapped = files.get(e.check);
    if (!mapped) unmapped.add(e.check);
    if (changed.includes(e.file) || (mapped ?? []).some(touches)) console.log(e.id);
  }
  for (const check of unmapped) {
    process.stderr.write(`note: .harness/check-files has no line for the check "${check}", so only a change to an entry's own file starts its replays\n`);
  }
} else {
  die("usage: replay-faults.mjs list|apply|baseline|verdict|select ...");
}
