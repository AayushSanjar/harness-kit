#!/usr/bin/env node
// The check that harness-kit's commands are written by their full names, and that no
// harness-kit skill is named like a Claude Code built-in.
//
//   node check-names.mjs --builtins FILE --skills DIR PATH...
//
// THE SKILLS are the folders DIR/*/ that hold a SKILL.md. A skill's name is its frontmatter
// `name`, or its folder's name when there is none: the plugin skill is typed
// /harness-kit:<name>, and its bare form runs only while no other command uses the name
// (code.claude.com/docs/en/skills), so a bare name can stop working, or run a built-in,
// whenever Claude Code adds a command.
// THE RETIRED NAMES (RETIRED, below) are names a harness-kit skill had before: plan, renamed
// to brief in v0.18.0, because Claude Code's built-in of that name enters plan mode.
// THE BUILT-IN LIST, FILE, holds Claude Code's commands, bundled skills and workflows and
// their aliases, one name per line without the slash, # comments and blank lines skipped.
// Its header names where it came from: a "# source: https://..." line and a
// "# claude-code: <version>" line.
//
// THE RULES, each problem printed as "FILE:LINE: rule: the line":
//   1. bare      in every text file under each PATH (a file, or a folder read through,
//                .git and node_modules left out), a slash followed by a skill's name, not
//                written as /harness-kit:<name>. A slash inside a path (skills/<name>/, or
//                .reports/<branch>.brief.md) does not count.
//   2. retired   the same for a retired name, bare or as /harness-kit:<name>.
//   3. built-in  a skill whose name is a line of the built-in list, ignoring case.
//   4. source    a built-in list without its source line or its claude-code line.
// Exit 0 with one line saying what was read; 1 with the problems; 2 on a usage error.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { basename, join } from "node:path";

const PREFIX = "harness-kit";
const RETIRED = ["plan"];
const TEXT = /\.(md|sh|mjs|js|cjs|json|txt|tsv|yml|yaml)$/;
const SKIP = new Set([".git", "node_modules"]);

const usage = (why) => {
  console.error(`check-names: ${why}\nusage: check-names.mjs --builtins FILE --skills DIR PATH...`);
  process.exit(2);
};

const args = process.argv.slice(2);
let builtinsFile = "";
let skillsDir = "";
const paths = [];
while (args.length > 0) {
  const arg = args.shift();
  if (arg === "--builtins") builtinsFile = args.shift() ?? "";
  else if (arg === "--skills") skillsDir = args.shift() ?? "";
  else paths.push(arg);
}
if (builtinsFile === "" || skillsDir === "" || paths.length === 0) usage("--builtins, --skills and at least one PATH are needed");
if (!existsSync(builtinsFile)) usage(`no built-in list at ${builtinsFile}`);
if (!existsSync(skillsDir)) usage(`no skills folder at ${skillsDir}`);

const problems = [];

// frontmatterName TEXT: the `name` in TEXT's frontmatter, or null.
const frontmatterName = (text) => {
  const lines = text.split(/\r?\n/);
  if (lines[0] !== "---") return null;
  for (const line of lines.slice(1)) {
    if (line === "---") return null;
    const m = /^name:\s*(.+?)\s*$/.exec(line);
    if (m) return m[1].replace(/^["']|["']$/g, "");
  }
  return null;
};

const skills = [];
for (const folder of readdirSync(skillsDir).sort()) {
  const file = join(skillsDir, folder, "SKILL.md");
  if (!existsSync(file)) continue;
  const name = frontmatterName(readFileSync(file, "utf8")) ?? folder;
  skills.push({ name, file });
}

// Rules 3 and 4: the built-in list.
const listText = readFileSync(builtinsFile, "utf8").split(/\r?\n/);
const source = listText.find((line) => /^#\s*source:\s*https:\/\/\S+/.test(line));
const version = listText.find((line) => /^#\s*claude-code:\s*[0-9]+\.[0-9]+\.[0-9]+\s*$/.test(line));
if (!source || !version) {
  problems.push(`${builtinsFile}:1: source: the list has no "# source: https://..." line or no "# claude-code: <version>" line, so no one can tell where or when it was read`);
}
const builtins = new Set(listText.map((line) => line.trim()).filter((line) => line !== "" && !line.startsWith("#")).map((line) => line.replace(/^\//, "").toLowerCase()));
for (const skill of skills) {
  if (builtins.has(skill.name.toLowerCase())) {
    problems.push(`${skill.file}:1: built-in: the skill "${skill.name}" is named like Claude Code's /${skill.name} (${builtinsFile}), so its bare name runs the built-in; rename it`);
  }
}

// Rules 1 and 2: the text files.
const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const edge = "(?:^|[^A-Za-z0-9_./:-])";
const end = "(?![A-Za-z0-9_-])";
const bareRules = skills.map(({ name }) => ({ name, re: new RegExp(`${edge}/${escape(name)}${end}`) }));
const retiredRules = RETIRED.map((name) => ({ name, re: new RegExp(`${edge}/(?:${escape(PREFIX)}:)?${escape(name)}${end}`) }));

const files = [];
const walk = (path) => {
  const stat = statSync(path);
  if (stat.isDirectory()) {
    for (const entry of readdirSync(path).sort()) if (!SKIP.has(entry)) walk(join(path, entry));
  } else if (stat.isFile() && TEXT.test(basename(path))) {
    files.push(path);
  }
};
for (const path of paths) {
  if (!existsSync(path)) usage(`no file or folder at ${path}`);
  walk(path);
}

for (const file of files) {
  readFileSync(file, "utf8").split(/\r?\n/).forEach((line, i) => {
    for (const { name, re } of bareRules) {
      if (re.test(line)) problems.push(`${file}:${i + 1}: bare: write /${PREFIX}:${name}, not the bare name: ${line.trim()}`);
    }
    for (const { name, re } of retiredRules) {
      if (re.test(line)) problems.push(`${file}:${i + 1}: retired: "${name}" is no longer a harness-kit command: ${line.trim()}`);
    }
  });
}

if (problems.length > 0) {
  console.log(problems.join("\n"));
  process.exit(1);
}
console.log(`check-names: ${files.length} files read, skills ${skills.map((s) => s.name).join(", ")}; no bare or retired name, no skill named like a built-in`);
