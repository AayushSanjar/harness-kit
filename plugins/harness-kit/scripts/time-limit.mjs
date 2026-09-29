#!/usr/bin/env node
// The one time-limit helper: every long-running process harness-kit starts runs through it
// (check-limits.mjs checks that), under a named limit, with a hard stop and cleanup.
//
//   node time-limit.mjs run --limit NAME|SECONDS [--name LABEL] [--merge] -- COMMAND ARGS...
//       Runs COMMAND in its own process group under the limit. Its stdout and stderr come
//       through (with --merge, its stderr goes to its stdout, in order, as `2>&1` would);
//       stdin is passed on as it is, so give a command that must not read the terminal
//       </dev/null. Exits with COMMAND's status (128 + the signal's number when a signal
//       ended it), or 124 on a TIMEOUT, with one line on stderr:
//         harness-kit LABEL: TIMEOUT: `COMMAND` ran longer than its limit of S seconds (NAME);
//         it was stopped: SIGTERM to its process group, then SIGKILL G seconds later if it
//         had not ended
//       When this process gets SIGINT, SIGTERM or SIGHUP, it stops the group the same way
//       and exits 130, 143 or 129; when its own output pipe is closed (EPIPE), 141. A Ctrl-C
//       reaches it, as it runs in the terminal's process group, and it passes the stop on to
//       COMMAND's group, which the terminal does not signal.
//   node time-limit.mjs limit NAME
//       Prints NAME's limit in seconds.
//   node time-limit.mjs register --owner PID path PATH
//   node time-limit.mjs register --owner PID worktree REPO PATH
//       Records a temporary folder or file, or a git worktree of REPO, as in use by the
//       process PID (THE REGISTRY) and prints the record's path; its owner deletes the
//       record when it removes PATH itself.
//   node time-limit.mjs sweep
//       THE SWEEP, on its own.
// Every command sweeps first.
//
// THE HARD STOP. When a limit runs out, the process's whole group is sent SIGTERM; if the
// group's first process has not ended when the grace period ends, the whole group is sent
// SIGKILL. When the first process ends, for any reason, anything left in its group is killed
// (SIGKILL), so nothing it started outlives it.
//
// THE LIMITS, in seconds, each overridden by its environment variable (a number above 0;
// the tests set tiny ones). The values and their evidence are in the v0.17.0 brief
// (.reports/inc-time-audit.brief.md, New thresholds).
//   check           540  HARNESS_KIT_LIMIT_CHECK_SECONDS  the project's check, index and
//                                                         pre-deploy commands
//   review          900  REVIEW_MAX_SECONDS               one reviewer run (review.sh,
//                                                         eval-reviewer.sh)
//   ci-run          900  SHIP_CI_RUN_SECONDS              one gh run watch (ci-lib.sh)
//   gh-read          60  SHIP_GH_READ_SECONDS             one gh read (ci-lib.sh)
//   git             300  HARNESS_KIT_LIMIT_GIT_SECONDS    one git push, fetch or ls-remote
//   plugin-command  120  UPGRADE_PLUGIN_SECONDS           claude plugin marketplace add and
//                                                         claude plugin update (upgrade.sh)
//   init            120  UPGRADE_INIT_SECONDS             the headless session (upgrade.sh)
//   the grace period 10  HARNESS_KIT_LIMIT_GRACE_SECONDS  from SIGTERM to SIGKILL
//
// THE REGISTRY, in $TMPDIR/harness-kit-live/: one JSON record per process group this helper
// runs, and per temporary folder or worktree a harness script has in use, each naming its
// owner (the process that must clean it up) by process id and start time (`ps -o lstart=`),
// and a group's first process by process id and start time. A record is deleted when its
// owner has cleaned up.
//
// THE SWEEP, each time the helper starts: every record whose owner is gone (no such process,
// or its process id now has another start time) was left by a run that was force-killed.
// Its group is stopped (SIGTERM, the grace period, then SIGKILL), unless the group's first
// process is alive with another start time (its process id was reused, so the group is
// gone); its folder is removed (only under the OS temp folder), or its worktree (git
// worktree remove --force, then prune); and the record is deleted. One line on stderr says
// what was cleaned up. A record whose owner is alive is never touched.
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { constants, tmpdir } from "node:os";
import { join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

export const LIMITS = {
  check: { env: "HARNESS_KIT_LIMIT_CHECK_SECONDS", seconds: 540 },
  review: { env: "REVIEW_MAX_SECONDS", seconds: 900 },
  "ci-run": { env: "SHIP_CI_RUN_SECONDS", seconds: 900 },
  "gh-read": { env: "SHIP_GH_READ_SECONDS", seconds: 60 },
  git: { env: "HARNESS_KIT_LIMIT_GIT_SECONDS", seconds: 300 },
  "plugin-command": { env: "UPGRADE_PLUGIN_SECONDS", seconds: 120 },
  init: { env: "UPGRADE_INIT_SECONDS", seconds: 120 },
};
export const GRACE = { env: "HARNESS_KIT_LIMIT_GRACE_SECONDS", seconds: 10 };

const positive = (value) => (/^[0-9]+(\.[0-9]+)?$/.test(value ?? "") && Number(value) > 0 ? Number(value) : null);

// A limit's seconds: a named limit (its environment variable, else its default), or a
// number of seconds. Throws for anything else.
export const limitSeconds = (limit) => {
  if (typeof limit === "number" && limit > 0) return limit;
  const named = LIMITS[limit];
  if (named) return positive(process.env[named.env]) ?? named.seconds;
  const seconds = positive(String(limit));
  if (seconds === null) throw new Error(`"${limit}" is neither a limit's name (${Object.keys(LIMITS).join(", ")}) nor a number of seconds above 0`);
  return seconds;
};
export const graceSeconds = () => positive(process.env[GRACE.env]) ?? GRACE.seconds;

// Seconds as printed: at most one decimal.
const secs = (n) => String(Math.round(n * 10) / 10);

// ---------------------------------------------------------------------------------------
// The registry and the sweep.
// ---------------------------------------------------------------------------------------
const LIVE = () => join(tmpdir(), "harness-kit-live");

// A process's start time as ps prints it, or "" when there is no such process.
const startOf = (pid) => {
  const r = spawnSync("ps", ["-o", "lstart=", "-p", String(pid)], { encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : "";
};
const exists = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
};
// Is PID alive and the same process that started at START?
const sameProcess = (pid, start) => exists(pid) && start !== "" && startOf(pid) === start;

let myStart = null;
const ownStart = () => (myStart ??= startOf(process.pid));

let serial = 0;
const writeRecord = (record) => {
  mkdirSync(LIVE(), { recursive: true });
  const path = join(LIVE(), `${record.kind}.${record.owner}.${Date.now()}.${serial++}.${Math.random().toString(36).slice(2, 8)}.json`);
  writeFileSync(path, `${JSON.stringify(record)}\n`);
  return path;
};
const dropRecord = (path) => rmSync(path, { force: true });

// Temp roots a swept folder must be under: the OS temp folder and /tmp, as given and resolved.
const tempRoots = () => {
  const real = (p) => {
    try {
      return realpathSync(p);
    } catch {
      return resolve(p);
    }
  };
  return [...new Set([tmpdir(), "/tmp"].flatMap((root) => [resolve(root), real(root)]))];
};
const underTemp = (path) => tempRoots().some((root) => resolve(path).startsWith(`${root}${sep}`));

const sleepSync = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

const signalGroup = (pgid, signal) => {
  try {
    process.kill(-pgid, signal);
    return true;
  } catch {
    return false; // gone
  }
};

// THE SWEEP. Returns what it cleaned up; prints one line on stderr when it cleaned anything.
export const sweep = () => {
  swept = true;
  let names;
  try {
    names = readdirSync(LIVE()).filter((n) => n.endsWith(".json"));
  } catch {
    return { groups: 0, folders: 0, worktrees: 0 };
  }
  const left = [];
  for (const name of names) {
    const path = join(LIVE(), name);
    let record;
    try {
      record = JSON.parse(readFileSync(path, "utf8"));
    } catch {
      continue; // being written, or not ours to judge
    }
    if (sameProcess(record.owner, record.ownerStart)) continue;
    left.push({ path, record });
  }
  const done = { groups: 0, folders: 0, worktrees: 0 };
  // The groups: SIGTERM to all first, one grace period, then SIGKILL.
  const groups = left.filter(({ record }) => record.kind === "group" && Number.isInteger(record.pgid) && record.pgid > 1);
  const stopping = groups.filter(({ record }) => {
    // A first process alive with another start time: its id was reused, so the group is gone.
    if (exists(record.pgid) && startOf(record.pgid) !== record.leaderStart) return false;
    return signalGroup(record.pgid, "SIGTERM");
  });
  if (stopping.length > 0) {
    const until = Date.now() + graceSeconds() * 1000;
    while (Date.now() < until && stopping.some(({ record }) => exists(record.pgid))) sleepSync(100);
    for (const { record } of stopping) signalGroup(record.pgid, "SIGKILL");
    done.groups = stopping.length;
  }
  for (const { record } of left) {
    if (record.kind === "path" && typeof record.path === "string" && underTemp(record.path) && existsSync(record.path)) {
      rmSync(record.path, { recursive: true, force: true });
      done.folders += 1;
    } else if (record.kind === "worktree" && typeof record.path === "string" && typeof record.repo === "string") {
      if (existsSync(record.path)) {
        spawnSync("git", ["-C", record.repo, "worktree", "remove", "--force", record.path], { stdio: "ignore" });
        if (underTemp(record.path)) rmSync(record.path, { recursive: true, force: true });
        done.worktrees += 1;
      }
      spawnSync("git", ["-C", record.repo, "worktree", "prune"], { stdio: "ignore" });
    }
  }
  for (const { path } of left) dropRecord(path);
  if (done.groups + done.folders + done.worktrees > 0) {
    process.stderr.write(
      `harness-kit time-limit: cleaned up after an earlier run that was killed: ${done.groups} process group(s) stopped, ` +
        `${done.folders} temporary folder(s) and ${done.worktrees} worktree(s) removed\n`,
    );
  }
  return done;
};

// Records PATH (kind "path") or the worktree PATH of REPO (kind "worktree") as in use by the
// process OWNER (default: this one). Returns the record's path.
export const register = (kind, path, { repo = null, owner = process.pid } = {}) =>
  writeRecord({ kind, owner, ownerStart: owner === process.pid ? ownStart() : startOf(owner), path: resolve(path), ...(repo ? { repo } : {}) });
export const unregister = dropRecord;

let swept = false;
const sweepOnce = () => {
  if (swept) return;
  swept = true;
  sweep();
};

// ---------------------------------------------------------------------------------------
// Starting a process under a limit.
// ---------------------------------------------------------------------------------------
const live = new Set();

// startLimited: starts COMMAND with ARGS in its own process group (THE HARD STOP).
//   options: cwd, env, stdio (as spawn's; default ["ignore", "pipe", "pipe"]), limit (a
//   limit's name or seconds, or null for none yet), grace (seconds; default the grace
//   period), capture (true: collect piped stdout and stderr into the result), onTimeout
//   (called when the limit runs out, before the stop).
// Returns a handle: child; began (ms); setLimit(limit) (from the start; replaces any
// earlier limit); stop() (SIGTERM to the group, then SIGKILL when the grace period ends);
// kill() (SIGKILL to the group now); result, a promise of { code, signal, status (the exit
// status, 128 + the signal's number for a signal, 127 when it could not start), timedOut,
// stopped, seconds, stdout, stderr, error }.
export const startLimited = (command, args = [], options = {}) => {
  sweepOnce();
  const { cwd, env, stdio = ["ignore", "pipe", "pipe"], limit = null, capture = false, onTimeout = null } = options;
  const grace = options.grace ?? graceSeconds();
  const child = spawn(command, args, { cwd, env, stdio, detached: true });
  const handle = { child, began: Date.now(), timedOut: false, stopped: false, limitSeconds: null };
  let timer = null;
  let graceTimer = null;
  let record = null;
  let out = "";
  let err = "";
  if (capture) {
    child.stdout?.setEncoding("utf8").on("data", (d) => (out += d));
    child.stderr?.setEncoding("utf8").on("data", (d) => (err += d));
  }
  const group = (signal) => child.pid !== undefined && signalGroup(child.pid, signal);
  let ended = false;
  handle.stop = () => {
    if (ended) return;
    handle.stopped = true;
    group("SIGTERM");
    graceTimer ??= setTimeout(() => group("SIGKILL"), grace * 1000);
  };
  handle.kill = () => {
    if (ended) return;
    handle.stopped = true;
    group("SIGKILL");
  };
  handle.setLimit = (next) => {
    clearTimeout(timer);
    if (next === null) return;
    const seconds = limitSeconds(next);
    handle.limitSeconds = seconds;
    const left = seconds * 1000 - (Date.now() - handle.began);
    timer = setTimeout(() => {
      if (ended || handle.timedOut) return;
      handle.timedOut = true;
      onTimeout?.(handle);
      handle.stop();
    }, Math.max(0, left));
  };
  if (child.pid !== undefined) {
    live.add(handle);
    try {
      record = writeRecord({ kind: "group", owner: process.pid, ownerStart: ownStart(), pgid: child.pid, leaderStart: startOf(child.pid), command: [command, ...args].join(" ").slice(0, 300) });
    } catch {
      record = null; // a registry that cannot be written costs only the sweep
    }
  }
  handle.setLimit(limit);
  handle.result = new Promise((resolveResult) => {
    let exit = null;
    const finish = (error = null) => {
      ended = true;
      clearTimeout(timer);
      clearTimeout(graceTimer);
      live.delete(handle);
      if (record) dropRecord(record);
      const [code, signal] = exit ?? [null, null];
      const status = error ? 127 : code ?? 128 + (constants.signals[signal] ?? 15);
      resolveResult({ code, signal, status, timedOut: handle.timedOut, stopped: handle.stopped, seconds: (Date.now() - handle.began) / 1000, stdout: out, stderr: err, error });
    };
    child.on("exit", (code, signal) => {
      exit = [code, signal];
      // The first process has ended: anything left in its group goes too.
      group("SIGKILL");
    });
    child.on("close", () => finish());
    child.on("error", (error) => {
      if (exit === null && child.pid === undefined) finish(error);
    });
  });
  return handle;
};

// runLimited: startLimited, then its result.
export const runLimited = (command, args = [], options = {}) => startLimited(command, args, options).result;

// stopAllAndExit CODE: stops every group still running (SIGTERM, then SIGKILL when the grace
// period ends), waits for them, then exits CODE.
let exiting = false;
export const stopAllAndExit = async (code) => {
  if (exiting) return;
  exiting = true;
  const handles = [...live];
  for (const h of handles) h.stop();
  const wait = new Promise((r) => setTimeout(r, (graceSeconds() + 2) * 1000));
  await Promise.race([Promise.all(handles.map((h) => h.result)), wait]);
  for (const h of handles) h.kill();
  process.exit(code);
};

// exitOnSignals: SIGINT, SIGTERM and SIGHUP, and EPIPE on this process's stdout or stderr,
// stop every group and exit 130, 143, 129 or 141.
export const exitOnSignals = () => {
  for (const [signal, code] of [["SIGINT", 130], ["SIGTERM", 143], ["SIGHUP", 129]]) process.on(signal, () => stopAllAndExit(code));
  for (const stream of [process.stdout, process.stderr]) {
    stream.on("error", (error) => {
      if (error.code === "EPIPE") stopAllAndExit(141);
    });
  }
};

// A TIMEOUT's line, as `run` prints it.
export const timeoutLine = (label, shown, seconds, name, grace) =>
  `harness-kit ${label}: TIMEOUT: \`${shown}\` ran longer than its limit of ${secs(seconds)} seconds` +
  `${name ? ` (${name})` : ""}; it was stopped: SIGTERM to its process group, then SIGKILL ${secs(grace)} seconds later if it had not ended`;

// ---------------------------------------------------------------------------------------
// The command line.
// ---------------------------------------------------------------------------------------
const cli = async (argv) => {
  const usage = () => {
    process.stderr.write(
      "usage: time-limit.mjs run --limit NAME|SECONDS [--name LABEL] [--merge] -- COMMAND ARGS...\n" +
        "       time-limit.mjs limit NAME\n" +
        "       time-limit.mjs register --owner PID path PATH | worktree REPO PATH\n" +
        "       time-limit.mjs sweep\n",
    );
    process.exit(2);
  };
  const [sub, ...rest] = argv;
  if (sub === "sweep") {
    sweep();
    return 0;
  }
  if (sub === "limit") {
    if (rest.length !== 1) usage();
    try {
      process.stdout.write(`${limitSeconds(rest[0])}\n`);
    } catch (error) {
      process.stderr.write(`harness-kit time-limit: ${error.message}\n`);
      return 2;
    }
    return 0;
  }
  if (sub === "register") {
    sweep();
    const [flag, owner, kind, ...paths] = rest;
    if (flag !== "--owner" || !/^[1-9][0-9]*$/.test(owner ?? "")) usage();
    if (kind === "path" && paths.length === 1) process.stdout.write(`${register("path", paths[0], { owner: Number(owner) })}\n`);
    else if (kind === "worktree" && paths.length === 2) process.stdout.write(`${register("worktree", paths[1], { repo: paths[0], owner: Number(owner) })}\n`);
    else usage();
    return 0;
  }
  if (sub !== "run") usage();
  let limit = null;
  let label = "time-limit";
  let merge = false;
  let i = 0;
  for (; i < rest.length && rest[i] !== "--"; i++) {
    if (rest[i] === "--limit") limit = rest[++i];
    else if (rest[i] === "--name") label = rest[++i];
    else if (rest[i] === "--merge") merge = true;
    else usage();
  }
  const command = rest.slice(i + 1);
  if (limit === undefined || limit === null || label === undefined || rest[i] !== "--" || command.length === 0) usage();
  let seconds;
  try {
    seconds = limitSeconds(limit);
  } catch (error) {
    process.stderr.write(`harness-kit ${label}: ${error.message}\n`);
    return 2;
  }
  exitOnSignals();
  // Through a pipe, the output is copied, so that a closed pipe is seen here (EPIPE); to a
  // terminal it is passed on as it is.
  const piped = !process.stdout.isTTY;
  const [file, args] = merge ? ["/bin/sh", ["-c", 'exec 2>&1; exec "$@"', "harness-kit-limit", ...command]] : [command[0], command.slice(1)];
  const handle = startLimited(file, args, { stdio: ["inherit", piped ? "pipe" : "inherit", "inherit"], limit: seconds });
  if (piped) handle.child.stdout?.on("data", (d) => process.stdout.write(d));
  const result = await handle.result;
  // A signal or a closed pipe is being handled: stopAllAndExit exits with its own status.
  if (exiting) await new Promise(() => {});
  if (result.error) {
    process.stderr.write(`harness-kit ${label}: could not start ${command[0]}: ${result.error.message}\n`);
    return 127;
  }
  if (result.timedOut) {
    const shown = command.join(" ").replace(/\s+/g, " ").slice(0, 200);
    process.stderr.write(`${timeoutLine(label, shown, seconds, LIMITS[limit] ? limit : null, graceSeconds())}\n`);
    return 124;
  }
  return result.status;
};

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const code = await cli(process.argv.slice(2));
  // Let the last output drain before exiting.
  if (process.stdout.writableLength > 0) process.stdout.once("drain", () => process.exit(code));
  else process.exit(code);
}
