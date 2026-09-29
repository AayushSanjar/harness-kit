#!/usr/bin/env node
// The parts of replay-faults.sh and land.sh that read tables and text, and run the checks;
// see replay-faults.sh for the formats and what a replay is.
//
//   node replay-faults.mjs list MUTATIONS [ID...]
//       Checks every entry of MUTATIONS and prints "<id>\t<file>\t<check>" for each one
//       asked for (all when no ID is given), in file order. Exit 2, with every problem on
//       stderr, when the file is unusable or an ID is not in it.
//   node replay-faults.mjs run MUTATIONS OUT PROJECT SNAPSHOT PART CHECK [ID...]
//       Runs part of a replay of the entries asked for (all when no ID is given) and keeps
//       each run's result in the folder OUT, for judge. PART is "all" (the baseline and
//       every entry), "baseline" (the baseline only) or "I/N" (shard I of N: the entries at
//       positions I, I+N, I+2N... of those asked for, without the baseline). Each run is the
//       check command CHECK in a fresh worktree of the commit SNAPSHOT of the repository
//       PROJECT, with the entry's fault put in (none for the baseline), as replay-faults.sh
//       says, up to the job count at once (below). A fragile entry is not run. Writes, in
//       OUT: <id>.log and <id>.status (the output and exit status of a run; baseline.log
//       and baseline.status for the baseline), <id>.error (why an entry could not run: a
//       worktree that could not be made, or text to find missing or repeated), and
//       part.<label>.json (the snapshot's tree, the ids asked for, the entries this part
//       ran and whether it ran the baseline), baseline.seconds (how long the baseline ran)
//       and <id>.timeout (a run stopped by a time limit, below). With
//       HARNESS_KIT_REPLAY_BASELINE_FROM set to the results folder of a baseline part of the
//       same snapshot (as harness-kit's CI shards do), its baseline.seconds sets the run
//       limit from the start. Progress goes to stderr. On SIGINT or SIGTERM it stops every
//       running check (its whole process group), removes every worktree and exits 130 or
//       143. Exit 0 when every run ended; 2 when OUT cannot be written, the baseline folder
//       cannot be used, or the baseline ran longer than its limit (every other run is then
//       stopped: no verdict can be read without the baseline).
//   node replay-faults.mjs judge MUTATIONS TREE COUNTS DIR...
//       Judges the results that run left in the folders DIR (one for a whole run; one per
//       part, or one they were all copied into, for parts run apart). Prints one line per
//       entry asked for, in file order: KILLED, SURVIVED, TIMEOUT or ERROR, the id and what
//       happened, then "replay-faults: N replayed: K KILLED, S SURVIVED, T TIMEOUT, E ERROR".
//       Writes to the file COUNTS "killed=K,survived=S,timeout=T,error=E,baseline=Bs" (B:
//       the baseline's seconds) and a line with "all" or "ids: <the ids asked for>", for the
//       event log. Exit 0 every entry KILLED, 1 otherwise; exit 2, judging
//       nothing, when the results are not one whole replay of the working tree whose tree
//       is TREE: no results, parts from different snapshots or with different ids asked for,
//       not exactly one baseline, an entry run by two parts, or a baseline that could not run
//       or ran longer than its limit.
//   node replay-faults.mjs select MUTATIONS CHECK_FILES CHANGED [BEFORE]
//       For land.sh: prints, one per line, the IDs of the entries whose own file is among
//       the paths in CHANGED (a file of paths, one per line), or whose check has a
//       CHECK_FILES path among them, or that the patch added or changed: no entry in
//       BEFORE (MUTATIONS as it was before the patch; missing means empty) has the same id
//       with the same fields. Notes on stderr name the checks with no CHECK_FILES line.
//       Exit 2, as list does, when MUTATIONS is unusable.
//
// THE JOB COUNT. At most as many checks run at once as the machine has CPUs
// (os.availableParallelism()). HARNESS_KIT_REPLAY_JOBS, a whole number of 1 or more, lowers
// it; it never raises it above the CPU count. HARNESS_KIT_REPLAY_CPUS stands in for the
// CPU count, for tests only. Worktrees are made and removed one at a time, by this process,
// so that parallel jobs never race on git's worktree locks; the baseline is one job of the
// pool, running alongside the entries.
//
// THE TIME LIMITS. Every check run has one; when it runs out, the run's process group is
// sent SIGTERM and the run is a TIMEOUT. They come from the harness settings below (each
// overridden by the environment variable of the same name; the tests set tiny values):
//   a fault's run    M times the baseline's measured seconds in this session, and never
//                    less than F. A run that started before the baseline ended gets its
//                    limit when the baseline ends (and is stopped at once if already past it).
//   the baseline     M times the last baseline recorded in this repository's event log (the
//                    baseline= field of the last REPLAYED line), or the fallback when there
//                    is none. A baseline that passes its limit stops the whole session (exit 2).
//   the session      HARNESS_KIT_REPLAY_SESSION_SECONDS when set; otherwise the baseline's
//                    limit (when this part runs the baseline) plus the number of rounds (the
//                    faults' runs divided by the job count, rounded up) times the run limit.
//                    Until the baseline ends, that run limit is taken from the last recorded
//                    baseline, or is the fallback; it is worked out again when the baseline
//                    ends. When the session's limit runs out, every run still going is
//                    stopped (SIGKILL: this limit is hard) and is a TIMEOUT, and so is every
//                    entry not started.
// Each limit is printed on stderr when it is set.
//
// The verdicts, for each entry in file order, the first that applies:
//   fragile      its text to find holds a version (v?digits.digits.digits) or a date
//                (YYYY-MM-DD): ERROR, "fragile entry", as a release or a new date changes
//                that text and the replay breaks for no fault of the check.
//   baseline     without the fault, the check printed a FAIL line for the entry's check, or
//                no PASS line for it: ERROR, as a failure with the fault would prove nothing.
//   could not run  <id>.error: ERROR, with why.
//   TIMEOUT      <id>.timeout: its run passed its limit, the session's limit ran out while
//                it ran, or before it started.
//   no result    no part ran it (a part's results are missing): ERROR.
//   KILLED       with the fault, a FAIL line for the entry's check and a non-zero exit.
//   SURVIVED     otherwise.
import { spawn, spawnSync } from "node:child_process";
import { closeSync, existsSync, mkdirSync, mkdtempSync, openSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { availableParallelism, tmpdir } from "node:os";
import { dirname, isAbsolute, join } from "node:path";

const FIELDS = ["id", "file", "find", "replacement", "check"];
const VERSION = /v?\d+\.\d+\.\d+/;
const DATE = /\d{4}-\d{2}-\d{2}/;
const ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const BASELINE = "baseline";

// The harness settings for the time limits (THE TIME LIMITS, above), with their defaults.
// An environment variable of the same name, a number above 0, overrides each one.
const SETTINGS = {
  HARNESS_KIT_REPLAY_LIMIT_MULTIPLE: 3, // M: a limit, as a multiple of a baseline's seconds
  HARNESS_KIT_REPLAY_LIMIT_FLOOR_SECONDS: 120, // F: the smallest limit a fault's run has
  HARNESS_KIT_REPLAY_BASELINE_FALLBACK_SECONDS: 1200, // the baseline's limit with none recorded
  HARNESS_KIT_REPLAY_SESSION_SECONDS: null, // set: replaces the session formula
};
const setting = (name) => {
  const value = process.env[name] ?? "";
  return /^[0-9]+(\.[0-9]+)?$/.test(value) && Number(value) > 0 ? Number(value) : SETTINGS[name];
};
// Seconds as printed: at most one decimal.
const secs = (n) => String(Math.round(n * 10) / 10);

const read = (path) => (existsSync(path) ? readFileSync(path, "utf8") : null);
const escape = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const say = (message) => process.stderr.write(`harness-kit replay-faults.sh: ${message}\n`);

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

// The entries asked for, in file order: all of them when ids is empty.
const askedFor = (entries, ids) => (ids.length === 0 ? entries : entries.filter((e) => ids.includes(e.id)));

// A line reporting CHECK with WORD (PASS or FAIL): the word, whitespace, then the name,
// then the end of the line, whitespace, ":" or "(". So "FAIL  lint  (exit 1)",
// "FAIL lint: 2 errors" and "FAIL lint" all report lint; "FAIL lint-extra" does not.
const reports = (word, check, log) => {
  const re = new RegExp(`^\\s*${word}\\s+${escape(check)}(?:$|[\\s:(])`);
  return (read(log) ?? "").split("\n").some((line) => re.test(line.replace(/\r$/, "")));
};

// Why an entry is fragile (the ERROR reason), or null.
const fragile = (entry) => {
  const found = entry.find.match(VERSION)?.[0];
  const date = entry.find.match(DATE)?.[0];
  if (!found && !date) return null;
  return (
    `fragile entry: its text to find holds the ${found ? `version "${found}"` : `date "${date}"`}, which the next ` +
    `${found ? "release" : "edit"} changes, so the replay would break without any fault in the check. ` +
    `Find text that names the code instead`
  );
};

// Puts the entry's fault into the copy at root. Returns why it could not (the ERROR
// reason), or null.
const apply = (entry, root) => {
  const target = join(root, entry.file);
  const text = read(target);
  if (text === null) return `${entry.file} does not exist`;
  const count = text.split(entry.find).length - 1;
  if (count === 0) return `the text to find is not in ${entry.file}`;
  if (count > 1) return `the text to find is in ${entry.file} ${count} times, not once; make it longer so it names one place`;
  writeFileSync(target, text.replace(entry.find, () => entry.replacement));
  return null;
};

// Without the fault: why the baseline proves nothing for this check (the ERROR reason),
// or null when it has a PASS line for it and no FAIL line.
const baselineProblem = (check, log, status) => {
  if (reports("FAIL", check, log)) {
    return `the check "${check}" already fails without the fault (exit ${status}), so a failure with it would prove nothing`;
  }
  if (!reports("PASS", check, log)) {
    return `without the fault the check command printed no PASS line for "${check}" (exit ${status}); is the name right?`;
  }
  return null;
};

// With the fault: [verdict, what happened].
const verdict = (entry, log, status) => {
  const failed = reports("FAIL", entry.check, log);
  if (failed && status !== "0") return ["KILLED", `"${entry.check}" failed with the fault in ${entry.file}`];
  if (failed) return ["SURVIVED", `it printed FAIL for "${entry.check}" but the check command exited 0, so nothing would stop`];
  return ["SURVIVED", `"${entry.check}" did not fail with the fault in place (the check command exited ${status})`];
};

// A whole number of 1 or more from the environment, or null.
const count = (name) => (/^[1-9][0-9]*$/.test(process.env[name] ?? "") ? Number(process.env[name]) : null);

const git = (args) => spawnSync("git", args, { encoding: "utf8" });

const die = (message, code = 2) => {
  process.stderr.write(`${message}\n`);
  process.exit(code);
};

// The seconds of the last baseline recorded in the project's event log (the baseline= field
// of its last REPLAYED line from replay-faults.sh), or null.
const recordedBaseline = (project) => {
  const common = git(["-C", project, "rev-parse", "--path-format=absolute", "--git-common-dir"]).stdout.trim();
  const log = common === "" ? null : read(join(common, "harness-kit/events.tsv"));
  let seconds = null;
  for (const line of (log ?? "").split("\n")) {
    const f = line.split("\t");
    const found = f[1] === "replay-faults.sh" && f[4] === "REPLAYED" ? /(?:^|,)baseline=([0-9]+(?:\.[0-9]+)?)s(?:,|$)/.exec(f[5] ?? "") : null;
    if (found) seconds = Number(found[1]);
  }
  return seconds;
};

// run: one part of a replay. See the header.
const run = ([path, out, project, snapshot, part, check, ...ids]) => {
  const asked = askedFor(mutations(path).entries, ids);
  const shard = /^([1-9][0-9]*)\/([1-9][0-9]*)$/.exec(part);
  if (part !== "all" && part !== BASELINE && !(shard && Number(shard[1]) <= Number(shard[2]))) {
    die(`the part must be all, baseline or I/N (shard I of N, 1 <= I <= N), not "${part}"`);
  }
  const mine = part === BASELINE ? [] : asked.filter((_, k) => !shard || k % Number(shard[2]) === Number(shard[1]) - 1);
  const withBaseline = part === "all" || part === BASELINE;
  const only = existsSync(join(project, ".harness/check-only"));
  const cpus = count("HARNESS_KIT_REPLAY_CPUS") ?? availableParallelism();
  const jobs = Math.min(cpus, count("HARNESS_KIT_REPLAY_JOBS") ?? cpus);
  const nodeModules = (process.env.HARNESS_KIT_REPLAY_NODE_MODULES ?? "").split("\n").filter(Boolean);
  const tree = git(["-C", project, "rev-parse", `${snapshot}^{tree}`]).stdout.trim();

  // The baseline's seconds, when a baseline part's results are given (a CI shard).
  let measured = null;
  const baselineFrom = process.env.HARNESS_KIT_REPLAY_BASELINE_FROM ?? "";
  if (baselineFrom !== "") {
    if (withBaseline) die("a baseline folder is for a shard, which does not run the baseline");
    const baselinePart = read(join(baselineFrom, `part.${BASELINE}.json`));
    const seconds = read(join(baselineFrom, `${BASELINE}.seconds`));
    if (baselinePart === null || seconds === null) die(`${baselineFrom} holds no finished baseline part (part.${BASELINE}.json and ${BASELINE}.seconds)`);
    if (JSON.parse(baselinePart).tree !== tree) die(`the baseline in ${baselineFrom} is from another snapshot, not this working tree (tree ${tree})`);
    measured = Number(seconds);
  }

  try {
    mkdirSync(out, { recursive: true });
    const label = shard ? `${shard[1]}-of-${shard[2]}` : part;
    const record = { tree, asked: ids.length === 0 ? null : ids, entries: mine.map((e) => e.id), baseline: withBaseline };
    writeFileSync(join(out, `part.${label}.json`), `${JSON.stringify(record)}\n`);
  } catch (error) {
    die(`cannot write the results to ${out}: ${error.message}`);
  }
  if (only) say(`each entry runs only its own check (.harness/check-only): ${check} --only <check>`);
  say(`up to ${jobs} checks at once (${cpus} CPUs)`);

  // The runs, in order: the baseline first, then the entries, fragile ones left out.
  const tasks = [
    ...(withBaseline ? [{ id: BASELINE }] : []),
    ...mine.filter((e) => fragile(e) === null).map((e) => ({ id: e.id, entry: e, n: asked.indexOf(e) + 1 })),
  ];

  // The time limits (THE TIME LIMITS, in the header), in seconds.
  const multiple = setting("HARNESS_KIT_REPLAY_LIMIT_MULTIPLE");
  const floor = setting("HARNESS_KIT_REPLAY_LIMIT_FLOOR_SECONDS");
  const fallback = setting("HARNESS_KIT_REPLAY_BASELINE_FALLBACK_SECONDS");
  const fixedSession = setting("HARNESS_KIT_REPLAY_SESSION_SECONDS");
  const recorded = recordedBaseline(project);
  const runLimit = (baseline) => Math.max(floor, multiple * baseline);
  const runHow = (baseline) =>
    multiple * baseline >= floor
      ? `${secs(multiple)} times the baseline's ${secs(baseline)} seconds`
      : `the floor; ${secs(multiple)} times the baseline's ${secs(baseline)} seconds is less`;
  const baselineLimit = recorded !== null ? multiple * recorded : fallback;
  let perRun = measured !== null ? runLimit(measured) : null;
  const rounds = Math.ceil(tasks.filter((t) => t.entry).length / jobs);
  const sessionLimit = () => {
    if (fixedSession !== null) return [fixedSession, "HARNESS_KIT_REPLAY_SESSION_SECONDS"];
    const each = perRun ?? (recorded !== null ? runLimit(recorded) : fallback);
    const sum = (withBaseline ? baselineLimit : 0) + rounds * each;
    const baselinePart = withBaseline ? `the baseline's limit of ${secs(baselineLimit)} seconds plus ` : "";
    return [sum, `${baselinePart}${rounds} round(s) of the run limit of ${secs(each)} seconds`];
  };
  if (withBaseline) {
    say(
      `time limit for the baseline: ${secs(baselineLimit)} seconds (` +
        (recorded !== null ? `${secs(multiple)} times the last recorded baseline's ${secs(recorded)} seconds)` : "no baseline recorded: the fallback)"),
    );
  }
  if (perRun !== null) say(`time limit per run: ${secs(perRun)} seconds (${runHow(measured)})`);
  else if (tasks.some((t) => t.entry)) say("time limit per run: set when the baseline ends");

  const began = Date.now();
  const elapsed = (since) => (Date.now() - since) / 1000;
  const running = new Map();
  let next = 0;
  let finished = 0;
  let stopping = null;
  let baselineOver = null;
  let sessionTimer = null;

  const removeWorktree = (worktree) => {
    git(["-C", project, "worktree", "remove", "--force", worktree]);
    rmSync(worktree, { recursive: true, force: true });
    git(["-C", project, "worktree", "prune"]);
  };

  // A fresh worktree of the snapshot, with a symlink to each of the project's node_modules
  // folders; returns its path, or throws with why.
  const newWorktree = () => {
    const worktree = mkdtempSync(join(tmpdir(), "harness-kit-replay-wt."));
    const added = git(["-C", project, "-c", "core.hooksPath=/dev/null", "worktree", "add", "--detach", "--quiet", worktree, snapshot]);
    if (added.status !== 0) {
      removeWorktree(worktree);
      throw new Error(`could not create a worktree: ${(added.stderr || added.stdout).trim()}`);
    }
    for (const rel of nodeModules) {
      const link = join(worktree, rel);
      if (existsSync(dirname(link)) && !existsSync(link)) symlinkSync(join(project, rel), link);
    }
    return worktree;
  };

  const signalGroup = (job, signal) => {
    try {
      process.kill(-job.child.pid, signal);
    } catch {
      // Already gone.
    }
  };

  const done = () => {
    if (running.size > 0) return;
    clearTimeout(sessionTimer);
    if (stopping !== null) {
      say("interrupted; the checks were stopped and their worktrees removed");
      process.exit(stopping);
    }
    if (baselineOver !== null) {
      say(`the check without any fault ran longer than ${baselineOver}, so no verdict can be read; every other run was stopped. Nothing was judged`);
      process.exit(2);
    }
    if (next >= tasks.length) process.exit(0);
  };

  // A run that passes its limit: its process group gets SIGTERM, and it is a TIMEOUT.
  const overLimit = (job, limit, how) => {
    if (job.over) return;
    job.over = { kind: "run", limit, how };
    signalGroup(job, "SIGTERM");
  };
  const limitRun = (job, limit, how) => {
    clearTimeout(job.timer);
    job.timer = setTimeout(() => overLimit(job, limit, how), Math.max(0, (limit - elapsed(job.began)) * 1000));
  };

  // The session's limit, from when this part began.
  const limitSession = () => {
    const [limit, how] = sessionLimit();
    say(`time limit for the session: ${secs(limit)} seconds (${how})`);
    clearTimeout(sessionTimer);
    sessionTimer = setTimeout(() => {
      say(`the session's limit of ${secs(limit)} seconds ran out; every run still going is stopped`);
      for (const task of tasks.slice(next)) {
        writeFileSync(join(out, `${task.id}.timeout`), `${JSON.stringify({ kind: "not-started", limit })}\n`);
        if (task.id === BASELINE) baselineOver = `the session's limit of ${secs(limit)} seconds`;
      }
      next = tasks.length;
      for (const job of running.values()) {
        job.over ??= { kind: "session", limit };
        signalGroup(job, "SIGKILL");
      }
      done();
    }, Math.max(0, (limit - elapsed(began)) * 1000));
  };

  const start = (task) => {
    const { id, entry } = task;
    if (entry) say(`replaying ${id} (${task.n} of ${asked.length}): ${entry.file}, which "${entry.check}" must catch`);
    else say(`running the check without any fault: ${check}`);
    let worktree;
    try {
      worktree = newWorktree();
      const problem = entry ? apply(entry, worktree) : null;
      if (problem !== null) throw new Error(problem);
    } catch (error) {
      if (worktree) removeWorktree(worktree);
      writeFileSync(join(out, `${id}.error`), `${error.message}\n`);
      finished += 1;
      return;
    }
    const log = openSync(join(out, `${id}.log`), "w");
    const targeted = only && entry;
    const child = spawn("/bin/sh", ["-c", targeted ? `${check} --only "$1"` : check, "harness-kit-replay", ...(targeted ? [entry.check] : [])], {
      cwd: worktree,
      detached: true,
      stdio: ["ignore", log, log],
      env: { ...process.env, HARNESS_KIT_REPLAY: "1" },
    });
    closeSync(log);
    const job = { child, worktree, task, began: Date.now(), timer: null, over: null };
    running.set(child.pid, job);
    if (!entry) limitRun(job, baselineLimit, "the baseline's limit");
    else if (perRun !== null) limitRun(job, perRun, runHow(measured));
    const end = (status) => {
      if (!running.has(child.pid)) return;
      running.delete(child.pid);
      clearTimeout(job.timer);
      removeWorktree(worktree);
      finished += 1;
      const seconds = elapsed(job.began);
      if (stopping === null && job.over !== null) {
        writeFileSync(join(out, `${id}.timeout`), `${JSON.stringify({ ...job.over, seconds })}\n`);
        say(`TIMEOUT ${id} after ${secs(seconds)} seconds (${finished} of ${tasks.length} runs)`);
        if (!entry) {
          baselineOver ??= job.over.kind === "run" ? `its limit of ${secs(job.over.limit)} seconds` : `the session's limit of ${secs(job.over.limit)} seconds`;
          next = tasks.length;
          for (const other of running.values()) signalGroup(other, "SIGTERM");
        }
      } else if (stopping === null) {
        writeFileSync(join(out, `${id}.status`), `${status}\n`);
        say(`done ${id} (${finished} of ${tasks.length} runs)`);
        if (!entry) {
          // The baseline's seconds set the run limit, and the session's.
          measured = seconds;
          writeFileSync(join(out, `${BASELINE}.seconds`), `${seconds}\n`);
          perRun = runLimit(measured);
          if (tasks.some((t) => t.entry)) {
            say(`time limit per run: ${secs(perRun)} seconds (${runHow(measured)})`);
            for (const other of running.values()) limitRun(other, perRun, runHow(measured));
            if (fixedSession === null) limitSession();
          }
        }
      }
      startMore();
      done();
    };
    child.on("exit", (code, signal) => end(code ?? 128 + (signal === "SIGKILL" ? 9 : 15)));
    child.on("error", (error) => {
      writeFileSync(join(out, `${id}.error`), `the check could not start: ${error.message}\n`);
      end(127);
    });
  };

  const startMore = () => {
    while (stopping === null && baselineOver === null && running.size < jobs && next < tasks.length) start(tasks[next++]);
  };

  const stop = (code) => {
    if (stopping !== null) return;
    stopping = code;
    for (const { child } of running.values()) {
      try {
        process.kill(-child.pid, "SIGTERM");
      } catch {
        // Already gone.
      }
    }
    done();
  };
  process.on("SIGINT", () => stop(130));
  process.on("SIGTERM", () => stop(143));

  limitSession(); // the session's limit, from the start
  startMore();
  done();
};

// judge: the verdicts on the results in dirs. See the header.
const judge = ([path, tree, countsFile, ...dirs]) => {
  const refuse = (message) => die(`harness-kit replay-faults.sh: ${message}. Nothing was judged.`);
  const parts = dirs.flatMap((dir) =>
    (existsSync(dir) ? readdirSync(dir) : [])
      .filter((name) => /^part\..+\.json$/.test(name))
      .map((name) => ({ where: join(dir, name), ...JSON.parse(readFileSync(join(dir, name), "utf8")) })),
  );
  if (parts.length === 0) refuse(`there are no replay results in ${dirs.join(", ")}`);
  for (const p of parts) {
    if (p.tree !== tree) {
      refuse(`${p.where} is from another snapshot (tree ${p.tree}), not this working tree (tree ${tree}); judge results only with the working tree they were run on`);
    }
  }
  const asked = JSON.stringify(parts[0].asked);
  const other = parts.find((p) => JSON.stringify(p.asked) !== asked);
  if (other) refuse(`${other.where} and ${parts[0].where} replayed different entries`);
  const baselines = parts.filter((p) => p.baseline);
  if (baselines.length !== 1) refuse(`the results hold ${baselines.length} baseline runs, not 1 (${parts.map((p) => p.where).join(", ")})`);
  const ranBy = new Map();
  for (const p of parts) {
    for (const id of p.entries) {
      if (ranBy.has(id)) refuse(`the entry ${id} was run by two parts, ${ranBy.get(id)} and ${p.where}`);
      ranBy.set(id, p.where);
    }
  }
  // A result file, from whichever folder holds it.
  const result = (name) => dirs.map((dir) => join(dir, name)).find((file) => existsSync(file)) ?? null;
  const text = (name) => (result(name) === null ? null : readFileSync(result(name), "utf8").trim());
  if (text(`${BASELINE}.error`) !== null) refuse(`the check could not run without a fault: ${text(`${BASELINE}.error`)}`);
  if (text(`${BASELINE}.timeout`) !== null) {
    const over = JSON.parse(text(`${BASELINE}.timeout`));
    refuse(`the check without any fault ran longer than ${over.kind === "run" ? "its" : "the session's"} limit of ${secs(over.limit)} seconds, so no verdict can be read`);
  }
  const baselineStatus = text(`${BASELINE}.status`);
  if (baselineStatus === null) refuse("the baseline run has no result (it was interrupted, or its results are missing)");
  const baselineLog = result(`${BASELINE}.log`);
  const baselineSeconds = text(`${BASELINE}.seconds`);
  // A TIMEOUT's reason, from its <id>.timeout.
  const timedOut = (over) =>
    over.kind === "run"
      ? `ran longer than its limit of ${secs(over.limit)} seconds (${over.how}); stopped after ${secs(over.seconds)} seconds`
      : over.kind === "session"
        ? `still running when the session's limit of ${secs(over.limit)} seconds ran out; stopped after ${secs(over.seconds)} seconds`
        : `not started before the session's limit of ${secs(over.limit)} seconds ran out`;

  const ids = parts[0].asked ?? [];
  const tally = { KILLED: 0, SURVIVED: 0, TIMEOUT: 0, ERROR: 0 };
  const entries = askedFor(mutations(path).entries, ids);
  for (const entry of entries) {
    const status = text(`${entry.id}.status`);
    let line;
    const why = fragile(entry) ?? baselineProblem(entry.check, baselineLog, baselineStatus) ?? text(`${entry.id}.error`);
    const over = text(`${entry.id}.timeout`);
    if (why !== null) line = ["ERROR", why];
    else if (over !== null) line = ["TIMEOUT", timedOut(JSON.parse(over))];
    else if (status === null) line = ["ERROR", "no result: no part of the replay ran it (a part's results are missing)"];
    else line = verdict(entry, result(`${entry.id}.log`), status);
    tally[line[0]] += 1;
    console.log(`${line[0]} ${entry.id}: ${line[1]}`);
  }
  console.log(
    `replay-faults: ${entries.length} replayed: ${tally.KILLED} KILLED, ${tally.SURVIVED} SURVIVED, ${tally.TIMEOUT} TIMEOUT, ${tally.ERROR} ERROR`,
  );
  const counts = `killed=${tally.KILLED},survived=${tally.SURVIVED},timeout=${tally.TIMEOUT},error=${tally.ERROR}`;
  const baselineField = baselineSeconds === null ? "" : `,baseline=${Number(baselineSeconds).toFixed(2)}s`;
  writeFileSync(countsFile, `${counts}${baselineField}\n${ids.length === 0 ? "all" : `ids: ${ids.join(" ")}`}\n`);
  process.exit(tally.SURVIVED === 0 && tally.TIMEOUT === 0 && tally.ERROR === 0 ? 0 : 1);
};

const [command, ...args] = process.argv.slice(2);

if (command === "list") {
  const [path, ...ids] = args;
  const { entries, problems } = mutations(path);
  const byId = new Map(entries.map((e) => [e.id, e]));
  for (const id of ids) if (!byId.has(id)) problems.push(`no entry with the id "${id}" in ${path}`);
  if (problems.length > 0) die(problems.join("\n"));
  for (const e of askedFor(entries, ids)) console.log(`${e.id}\t${e.file}\t${e.check}`);
} else if (command === "run") {
  run(args);
} else if (command === "judge") {
  judge(args);
} else if (command === "select") {
  const [path, checkFiles, changedList, beforePath] = args;
  const { entries, problems } = mutations(path);
  if (problems.length > 0) die(problems.join("\n"));
  // The entries as they were before the patch, by id, as their fields joined; a file that
  // was unusable before counts as far as its well-formed lines go.
  const before = new Map(
    rows(beforePath ? read(beforePath) : "")
      .filter(([, fields]) => fields.length === FIELDS.length)
      .map(([, fields]) => [fields[0], fields.join("\t")]),
  );
  const addedOrChanged = (e) => before.get(e.id) !== FIELDS.map((name) => e[name]).join("\t");
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
    if (changed.includes(e.file) || (mapped ?? []).some(touches) || addedOrChanged(e)) console.log(e.id);
  }
  for (const check of unmapped) {
    process.stderr.write(`note: .harness/check-files has no line for the check "${check}", so only a change to an entry's own file starts its replays\n`);
  }
} else {
  die("usage: replay-faults.mjs list|run|judge|select ...");
}
