// The start-up picture: what session-start.mjs (the SessionStart hook) shows Claude about
// where the branch stands, after its other lines. startPicture(projectDir) returns the lines;
// outside a git repository there are none. Every line starts "harness-kit start-up:".
//
// THE LINES, in this order (at most 5 + STATE_LINES = 15):
//   1. The branch and its brief. The brief's state comes from brief-lib.sh's brief_load, the
//      code ship.sh judges the approval with: approved, not approved, changed since it was
//      approved, or none. With a brief, the goal is its "# Brief:" title line. On a detached
//      HEAD the branch and the brief are none.
//   2. The last check: the latest CHECKED line for the branch in the local event log,
//      <git common dir>/harness-kit/events.tsv (events.sh has the format; the Stop hook,
//      land.sh, ship.sh and release.sh write it through harness_check_event). A CHECKED line
//      is written only when the result changes, so its date is shown as "since", and its
//      head is where the result changed, not where the check last ran. For FAIL it names the
//      first FAILING_NAMES failing checks, then "and N more".
//   3. The last review: the latest line for the branch in the working tree's
//      .harness/reviews.tsv (review.sh has the format), with its verdict, items, date and
//      head.
//   4. Uncommitted changes: the number of paths git status shows (untracked files one by
//      one), by kind: modified, added, deleted, renamed, copied, unmerged, untracked. Paths
//      are not listed.
//   5. The state file: a line naming it, then its first STATE_LINES lines, each after
//      "harness-kit start-up: > ". The file is the first line of .harness/state-file, a path
//      from the project root, or DEFAULT_STATE when that file does not exist or its first
//      line is empty.
// A source that is missing (no brief, no event log or no CHECKED line for the branch, no
// reviews.tsv or no line for the branch, git status failing, no state file, an empty one, or
// a path outside the project) is shown as "none" with the reason; nothing is guessed.
//
// Every line, its prefix included, is cut to MAX_LINE characters, the last of which is "…".
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const PREFIX = "harness-kit start-up: ";
const STATE_LINES = 10;
const FAILING_NAMES = 5;
const MAX_LINE = 200;
const DEFAULT_STATE = "docs/STATE.md";
const REVIEWS = ".harness/reviews.tsv";
const STATE_FILE = ".harness/state-file";
const BRIEF_LIB = fileURLToPath(new URL("./brief-lib.sh", import.meta.url));
const TOOL_NAMES = { "stop-gate.mjs": "the Stop hook" };

const git = (args, cwd) => {
  const r = spawnSync("git", args, { cwd, encoding: "utf8" });
  return r.status === 0 ? r.stdout : null;
};
const firstLine = (text) => String(text || "").split(/\r?\n/).find((line) => line.trim() !== "")?.trim() ?? "";
const readText = (path) => {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
};
const tsvRows = (text) => text.split("\n").map((line) => line.replace(/\r$/, "")).filter((line) => line !== "").map((line) => line.split("\t"));
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

// cut LINE: LINE, or its first MAX_LINE - 1 characters and "…" when it is longer.
export const cut = (line) => {
  const chars = Array.from(line);
  return chars.length > MAX_LINE ? chars.slice(0, MAX_LINE - 1).join("") + "…" : line;
};

// headNote SHA CURRENT: SHA shortened, and whether it is the current HEAD.
const headNote = (sha, current) => {
  if (!sha || sha === "none") return "before the first commit";
  const same = current && (current === sha || (sha.length >= 7 && current.startsWith(sha)));
  return `${sha.slice(0, 12)} (${same ? "the current HEAD" : "not the current HEAD"})`;
};

// 1. The branch and its brief.
const briefLine = (top, branch, head) => {
  if (!branch) return `branch: none (detached HEAD at ${head ? head.slice(0, 12) : "no commit"}); brief: none (HEAD is not on a branch)`;
  const r = spawnSync(
    "bash",
    ["-c", '. "$1" && if brief_load "$2" "$3"; then printf "%s\\t%s\\n" "$BRIEF_STATE" "$BRIEF"; else printf "error\\t%s\\n" "$BRIEF_ERROR"; fi',
      "harness-kit", BRIEF_LIB, top, branch],
    { cwd: top, encoding: "utf8" },
  );
  const [state, ...rest] = (r.status === 0 ? r.stdout : "").replace(/\n$/, "").split("\t");
  const brief = rest.join("\t");
  const where = `branch ${branch}; brief:`;
  if (!state) return `${where} none (brief-lib.sh could not be run: ${firstLine(r.stderr) || `exit ${r.status}`})`;
  if (state === "error") return `${where} none (${firstLine(brief)})`;
  if (state === "missing") return `${where} none (there is no ${brief})`;
  const said = { approved: "approved", unapproved: "not approved", changed: "changed since it was approved" }[state] ?? state;
  const title = (readText(join(top, brief)) ?? "").split(/\r?\n/).map((line) => line.match(/^# Brief:\s*(.*?)\s*$/)).find(Boolean);
  const goal = title && title[1] ? title[1] : 'none (the brief has no "# Brief:" title line)';
  return `${where} ${said} (${brief}); goal: ${goal}`;
};

// 2. The last check.
const checkLine = (top, branch, head) => {
  if (!branch) return "last check: none (HEAD is not on a branch)";
  const common = git(["rev-parse", "--path-format=absolute", "--git-common-dir"], top)?.trim();
  if (!common) return "last check: none (the git directory was not found, so there is no local event log)";
  const path = join(common, "harness-kit", "events.tsv");
  const rel = relative(top, path);
  const shown = rel.startsWith("..") || isAbsolute(rel) ? path : rel;
  const text = readText(path);
  if (text === null) return `last check: none (there is no local event log, ${shown})`;
  const e = tsvRows(text).filter((f) => f.length === 7 && f[2] === branch && f[4] === "CHECKED").at(-1);
  if (!e) return `last check: none (${shown} has no check result for ${branch})`;
  const [date, tool, , sha, , what, detail] = e;
  const by = `recorded by ${TOOL_NAMES[tool] ?? tool} at ${headNote(sha, head)}`;
  if (what !== "FAIL") return `last check: ${what} since ${date}, ${by}`;
  const colon = detail.indexOf(": ");
  const how = colon < 0 ? detail : detail.slice(0, colon);
  const named = colon < 0 ? "" : detail.slice(colon + 2);
  if (named === "" || named === "no FAIL lines") {
    return `last check: FAIL (${how}) since ${date}, ${by}; failing: not named (the check printed no FAIL lines)`;
  }
  const names = named.split("; ");
  const more = names.length > FAILING_NAMES ? ` and ${names.length - FAILING_NAMES} more` : "";
  return `last check: FAIL (${how}, ${plural(names.length, "failing check", "failing checks")}) since ${date}, ${by}; ` +
    `failing: ${names.slice(0, FAILING_NAMES).join("; ")}${more}`;
};

// 3. The last review.
const reviewLine = (top, branch, head) => {
  if (!branch) return "last review: none (HEAD is not on a branch)";
  const text = readText(join(top, REVIEWS));
  if (text === null) return `last review: none (there is no ${REVIEWS})`;
  const r = tsvRows(text).filter((f) => f.length === 9 && f[1] === branch).at(-1);
  if (!r) return `last review: none (${REVIEWS} has no line for ${branch})`;
  const [date, , , sha, , verdict, items] = r;
  return `last review: ${verdict} (${items}) on ${date}, for head ${headNote(sha, head)}`;
};

// 4. Uncommitted changes.
const KINDS = ["modified", "added", "deleted", "renamed", "copied", "unmerged", "untracked"];
const kindOf = (xy) => {
  if (xy === "??") return "untracked";
  if (xy.includes("U") || xy === "AA" || xy === "DD") return "unmerged";
  if (xy.includes("R")) return "renamed";
  if (xy.includes("C")) return "copied";
  if (xy[0] === "A") return "added";
  if (xy.includes("D")) return "deleted";
  return "modified";
};
const changesLine = (top) => {
  const r = spawnSync("git", ["status", "--porcelain=v1", "-z", "--untracked-files=all"], { cwd: top, encoding: "utf8" });
  if (r.status !== 0) return `uncommitted: none (git status failed: ${firstLine(r.stderr) || `exit ${r.status}`})`;
  const entries = r.stdout.split("\0").filter((entry) => entry !== "");
  const counts = new Map();
  let total = 0;
  for (let i = 0; i < entries.length; i++) {
    const xy = entries[i].slice(0, 2);
    if (xy === "!!") continue;
    // A rename or copy is followed by its original path, which is not another change.
    if (xy[0] === "R" || xy[0] === "C") i++;
    const kind = kindOf(xy);
    counts.set(kind, (counts.get(kind) ?? 0) + 1);
    total++;
  }
  if (total === 0) return "uncommitted: none";
  return `uncommitted: ${plural(total, "path", "paths")} (${KINDS.filter((k) => counts.has(k)).map((k) => `${counts.get(k)} ${k}`).join(", ")})`;
};

// 5. The state file.
const stateLines = (top) => {
  const configured = (readText(join(top, STATE_FILE)) ?? "").split(/\r?\n/)[0].trim();
  const name = configured || DEFAULT_STATE;
  const named = configured ? `; ${STATE_FILE} names it` : "";
  const rel = relative(top, resolve(top, name));
  if (rel === "" || rel.startsWith("..") || isAbsolute(rel)) return [`state: none (${STATE_FILE} names ${name}, which is outside the project)`];
  const path = join(top, rel);
  if (!existsSync(path)) return [`state: none (${rel} does not exist${named})`];
  if (!statSync(path).isFile()) return [`state: none (${rel} is not a file${named})`];
  const all = (readText(path) ?? "").split(/\r?\n/);
  if (all.at(-1) === "") all.pop();
  if (all.length === 0) return [`state: none (${rel} is empty${named})`];
  const shown = all.slice(0, STATE_LINES);
  const which = all.length > STATE_LINES ? `its first ${STATE_LINES} of ${all.length} lines` : `its ${plural(all.length, "line", "lines")}`;
  return [`state: ${rel}${configured ? ` (named by ${STATE_FILE})` : ""}, ${which}:`, ...shown.map((line) => `> ${line}`.trimEnd())];
};

// startPicture PROJECT_DIR: the picture's lines, each with its prefix and cut; [] outside a
// git repository.
export const startPicture = (projectDir) => {
  const top = git(["rev-parse", "--show-toplevel"], projectDir)?.trim();
  if (!top) return [];
  const branch = git(["symbolic-ref", "--short", "-q", "HEAD"], top)?.trim() || "";
  const head = git(["rev-parse", "-q", "--verify", "HEAD"], top)?.trim() || "";
  return [
    briefLine(top, branch, head),
    checkLine(top, branch, head),
    reviewLine(top, branch, head),
    changesLine(top),
    ...stateLines(top),
  ].map((line) => cut(PREFIX + line));
};
