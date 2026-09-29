// The start-up picture: what session-start.mjs (the SessionStart hook) shows Claude about
// where the branch stands, after its other lines. startPicture(projectDir) returns (a promise
// of) the lines; outside a git repository there are none. Every line starts "harness-kit
// start-up:".
//
// THE LINES, in this order (at most 6 + STATE_LINES = 16):
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
//   3. The last full fault replay: the latest REPLAYED line in the same event log whose
//      detail is "all" (replay-faults.sh --full, every entry; a targeted replay, or one of
//      chosen ids, is not full), on any branch: how many whole days ago it ran, rounded down,
//      its date, branch and counts. Then, when the project names its CI replay in
//      .harness/ci-replay ("<workflow file><TAB><job name>", as harness-kit does), CI's last
//      full replay: the newest of the last CI_RUNS completed runs of that workflow on the base
//      branch (.harness/review-base, default main) whose job concluded success or failure (a
//      skipped job is no replay), read with gh under the start-ci-read limit (time-limit.mjs),
//      both calls together: "CI N days ago (<date>, run <id>, passed|failed)", "CI none (...)",
//      or "CI unknown (<why>)" when gh is missing, fails or does not answer in time.
//      THE NUDGE: from REPLAY_DAYS days on, by the newer of the known ages, and when neither
//      is known, it gives a command, never cut (the one exception to MAX_LINE, below: a cut
//      command is no command). With .harness/ci-replay it starts the full replay on CI
//      (gh workflow run <workflow> --ref <base>) and never names a local replay, which takes
//      far longer. Without it, the command is bash <this plugin's scripts/replay-faults.sh>
//      --full, always followed by how long it would take: "(took M minutes on <date>)", from
//      the TIMED "replay" line written with the newest full REPLAYED line; otherwise "(about
//      M minutes, estimated: R rounds of the last recorded baseline's B seconds, for N faults
//      on J CPUs)", R being ceil((N + 1) / J), as replay-faults.mjs pools its runs, and B the
//      baseline of the last full replay (a targeted one's ran only some checks); otherwise
//      "(time unknown: no full replay recorded here)". With no .harness/mutations.tsv there is
//      nothing to replay, so it says none and gives no command.
//   4. The last review: the latest line for the branch in the working tree's
//      .harness/reviews.tsv (review.sh has the format), with its verdict, items, date and
//      head.
//   5. Uncommitted changes: the number of paths git status shows (untracked files one by
//      one), by kind: modified, added, deleted, renamed, copied, unmerged, untracked. Paths
//      are not listed.
//   6. The state file: a line naming it, then its first STATE_LINES lines, each after
//      "harness-kit start-up: > ". The file is the first line of .harness/state-file, a path
//      from the project root, or DEFAULT_STATE when that file does not exist or its first
//      line is empty.
// A source that is missing (no brief, no event log or no CHECKED line for the branch, no full
// replay, no reviews.tsv or no line for the branch, git status failing, no state file, an empty one, or
// a path outside the project) is shown as "none" with the reason; nothing is guessed.
//
// Every line, its prefix included, is cut to MAX_LINE characters, the last of which is "…";
// the replay line's command, after its text, is never cut.
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { availableParallelism } from "node:os";
import { isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { limitSeconds, runLimited } from "./time-limit.mjs";

const PREFIX = "harness-kit start-up: ";
const STATE_LINES = 10;
const FAILING_NAMES = 5;
const MAX_LINE = 200;
const DEFAULT_STATE = "docs/STATE.md";
const REVIEWS = ".harness/reviews.tsv";
const STATE_FILE = ".harness/state-file";
const BRIEF_LIB = fileURLToPath(new URL("./brief-lib.sh", import.meta.url));
const TOOL_NAMES = { "stop-gate.mjs": "the Stop hook" };
const REPLAY_DAYS = 7;
const REPLAY_SCRIPT = fileURLToPath(new URL("./replay-faults.sh", import.meta.url));
const DAY_MS = 24 * 60 * 60 * 1000;
const CI_REPLAY = ".harness/ci-replay";
const CI_RUNS = 20; // the completed runs searched for the last full CI replay (the person's number)

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

// The base branch: the first line of .harness/review-base, default main (as ship.sh reads it).
const baseBranch = (top) => (readText(join(top, ".harness", "review-base")) ?? "").split(/\r?\n/)[0].replace(/\s/g, "") || "main";
const dateOf = (iso) => String(iso).slice(0, 10);
const minutes = (seconds) => Math.max(1, Math.round(seconds / 60));
const daysSince = (when, now) => Math.max(0, Math.floor((now - when) / DAY_MS));

// .harness/ci-replay: { workflow, job }, { problem }, or null when there is none.
const ciSpec = (top) => {
  const text = readText(join(top, CI_REPLAY));
  if (text === null) return null;
  const line = text.split(/\r?\n/).find((l) => l.trim() !== "" && !l.startsWith("#")) ?? "";
  const [workflow, job, ...rest] = line.split("\t").map((f) => f.trim());
  if (!workflow || !job || rest.length > 0) return { problem: `${CI_REPLAY} does not hold "<workflow file><TAB><job name>"` };
  return { workflow, job };
};

// CI's last full replay: { text, days } (days null when not known).
const ciReplay = async (top, spec, base, now) => {
  const limit = limitSeconds("start-ci-read");
  const late = { why: `gh did not answer within ${limit} seconds` };
  const began = Date.now();
  const gh = async (args) => {
    const left = limit - (Date.now() - began) / 1000;
    if (left <= 0) return late;
    const r = await runLimited("gh", args, { cwd: top, limit: left, grace: 1, capture: true });
    if (r.timedOut) return late;
    if (r.error) return { why: r.error.code === "ENOENT" ? "gh not found" : `gh could not start: ${r.error.message}` };
    if (r.status !== 0) return { why: `gh failed: ${firstLine(r.stderr) || `exit ${r.status}`}` };
    try {
      return { json: JSON.parse(r.stdout) };
    } catch {
      return { why: "gh printed output that is not the expected JSON" };
    }
  };
  const unknown = (why) => ({ text: `unknown (${why})`, days: null });
  const runs = await gh(["run", "list", "--workflow", spec.workflow, "--branch", base, "--status", "completed", "--limit", String(CI_RUNS), "--json", "databaseId,createdAt"]);
  if (runs.why) return unknown(runs.why);
  for (const run of Array.isArray(runs.json) ? runs.json : []) {
    const view = await gh(["run", "view", String(run.databaseId), "--json", "jobs"]);
    if (view.why) return unknown(view.why);
    const job = (view.json?.jobs ?? []).find((j) => j.name === spec.job && (j.conclusion === "success" || j.conclusion === "failure"));
    if (!job) continue;
    const when = Date.parse(job.completedAt || run.createdAt);
    if (!Number.isFinite(when)) continue;
    const days = daysSince(when, now);
    return { text: `${plural(days, "day", "days")} ago (${dateOf(job.completedAt || run.createdAt)}, run ${run.databaseId}, ${job.conclusion === "success" ? "passed" : "failed"})`, days };
  }
  return { text: `none (no completed ${spec.job} in the last ${CI_RUNS} runs on ${base})`, days: null };
};

// How long a local full replay would take, from the event log's rows and the entries.
const localTime = (top, rows, full) => {
  if (full) {
    const at = rows.indexOf(full);
    const timed = rows[at + 1];
    const s = timed && timed[1] === "replay-faults.sh" && timed[4] === "TIMED" && timed[5] === "replay" ? /^seconds=([0-9.]+)/.exec(timed[6]) : null;
    if (s) return `(took ${plural(minutes(Number(s[1])), "minute", "minutes")} on ${dateOf(timed[0])})`;
  }
  const baseline = rows
    .filter((f) => f[1] === "replay-faults.sh" && f[4] === "REPLAYED" && f[6] === "all")
    .map((f) => /(?:^|,)baseline=([0-9]+(?:\.[0-9]+)?)s(?:,|$)/.exec(f[5] ?? ""))
    .filter(Boolean)
    .at(-1);
  if (!baseline) return "(time unknown: no full replay recorded here)";
  const b = Number(baseline[1]);
  const n = tsvRows(readText(join(top, ".harness", "mutations.tsv")) ?? "").filter((f) => f.length === 5 && !f[0].startsWith("#")).length;
  const cpus = /^[1-9][0-9]*$/.test(process.env.HARNESS_KIT_REPLAY_CPUS ?? "") ? Number(process.env.HARNESS_KIT_REPLAY_CPUS) : availableParallelism();
  const rounds = Math.ceil((n + 1) / cpus);
  return `(about ${plural(minutes(rounds * b), "minute", "minutes")}, estimated: ${plural(rounds, "round", "rounds")} of the last recorded baseline's ` +
    `${Math.round(b * 10) / 10} seconds, for ${plural(n, "fault", "faults")} on ${plural(cpus, "CPU", "CPUs")})`;
};

// 3. The last full fault replay, here and on CI: { text, command }, the command "" when there
// is none.
const replayLine = async (top, now = Date.now()) => {
  if (!existsSync(join(top, ".harness", "mutations.tsv"))) return { text: "last full fault replay: none (there is no .harness/mutations.tsv)", command: "" };
  const common = git(["rev-parse", "--path-format=absolute", "--git-common-dir"], top)?.trim();
  const log = common ? readText(join(common, "harness-kit", "events.tsv")) : null;
  const rows = log === null ? [] : tsvRows(log).filter((f) => f.length === 7);
  const e = rows.filter((f) => f[1] === "replay-faults.sh" && f[4] === "REPLAYED" && f[6] === "all").at(-1);
  const when = e ? Date.parse(e[0]) : NaN;
  let local = "none (the local event log has no full replay)";
  let localDays = null;
  if (e && Number.isFinite(when)) {
    const [date, , branch, , , what] = e;
    const n = /^killed=(\d+),survived=(\d+)(?:,timeout=(\d+))?,error=(\d+)/.exec(what);
    const counts = n ? `${n[1]} KILLED, ${n[2]} SURVIVED, ${n[3] ?? 0} TIMEOUT, ${n[4]} ERROR` : what;
    localDays = daysSince(when, now);
    local = `${plural(localDays, "day", "days")} ago (${date}, branch ${branch}, ${counts})`;
  }
  const base = baseBranch(top);
  const spec = ciSpec(top);
  const ci = spec === null ? null : spec.problem ? { text: `unknown (${spec.problem})`, days: null } : await ciReplay(top, spec, base, now);
  const text = `last full fault replay: ${local}${ci ? `; CI ${ci.text}` : ""}`;
  const known = [localDays, ci?.days ?? null].filter((d) => d !== null);
  if (known.length > 0 && Math.min(...known) < REPLAY_DAYS) return { text, command: "" };
  const lead = known.length > 0 ? `; over ${REPLAY_DAYS} days: ` : "; ";
  if (spec?.problem) return { text, command: `${lead}fix ${CI_REPLAY} for the command that starts one on CI` };
  if (spec) return { text, command: `${lead}start one on CI with gh workflow run ${spec.workflow} --ref ${base}` };
  return { text, command: `${lead}run one with bash ${REPLAY_SCRIPT} --full ${localTime(top, rows, e)}` };
};

// 4. The last review.
const reviewLine = (top, branch, head) => {
  if (!branch) return "last review: none (HEAD is not on a branch)";
  const text = readText(join(top, REVIEWS));
  if (text === null) return `last review: none (there is no ${REVIEWS})`;
  const r = tsvRows(text).filter((f) => f.length === 9 && f[1] === branch).at(-1);
  if (!r) return `last review: none (${REVIEWS} has no line for ${branch})`;
  const [date, , , sha, , verdict, items] = r;
  return `last review: ${verdict} (${items}) on ${date}, for head ${headNote(sha, head)}`;
};

// 5. Uncommitted changes.
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

// 6. The state file.
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
export const startPicture = async (projectDir) => {
  const top = git(["rev-parse", "--show-toplevel"], projectDir)?.trim();
  if (!top) return [];
  const branch = git(["symbolic-ref", "--short", "-q", "HEAD"], top)?.trim() || "";
  const head = git(["rev-parse", "-q", "--verify", "HEAD"], top)?.trim() || "";
  const replay = await replayLine(top);
  return [
    briefLine(top, branch, head),
    checkLine(top, branch, head),
    replay,
    reviewLine(top, branch, head),
    changesLine(top),
    ...stateLines(top),
  ].map((line) => (line === replay ? cut(PREFIX + line.text) + line.command : cut(PREFIX + line)));
};
