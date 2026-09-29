#!/usr/bin/env bash
# Tests for the triggers of the CI fault replay in .github/workflows/validate.yml: the
# weekly schedule, and a branch push that changes the replay machinery (the validate job's
# plan step, from replay-faults.sh --plan). The workflow is read as text, as tests/validate.sh's
# CI-shape check (z) reads it; nothing is run and GitHub is not called. Prints one PASS or
# FAIL line per case and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/validate.yml"
failures=0

result() {
  local label="$1" ok="$2" detail="$3"
  if [ "$ok" = yes ]; then
    echo "PASS $label"
  else
    echo "FAIL $label"
    sed 's/^/    /' <<<"$detail"
    failures=$((failures + 1))
  fi
}

# problems WHAT: the problems node finds in the workflow for WHAT (schedule or machinery),
# one per line; nothing when there are none.
problems() {
  node -e '
    const [file, what] = process.argv.slice(1);
    const text = require("fs").readFileSync(file, "utf8");
    // The top-level "on:" block, and each job under "jobs:" (two-space names), as text.
    const on = /^on:\n((?:[ \t].*\n|\n)*)/m.exec(text)?.[1] ?? "";
    const jobs = {};
    let name = null;
    for (const line of text.split("\n")) {
      const header = /^  ([A-Za-z0-9_-]+):\s*$/.exec(line);
      if (header) { name = header[1]; jobs[name] = ""; continue; }
      if (/^\S/.test(line)) name = null;
      if (name) jobs[name] += line + "\n";
    }
    const replayJobs = ["replay-baseline", "replay-shard", "replay-verdicts"];
    const ifOf = (job) => /^    if: (.*)$/m.exec(jobs[job] ?? "")?.[1] ?? "";
    const needsOf = (job) => /^    needs: (.*)$/m.exec(jobs[job] ?? "")?.[1] ?? "";
    const out = [];
    for (const job of replayJobs) if (!jobs[job]) out.push(`no ${job} job`);
    if (what === "schedule") {
      if (!/^  schedule:\n    - cron: "0 3 \* \* 1"$/m.test(on)) out.push(`"on:" has no schedule with cron "0 3 * * 1" (Mondays at 03:00 UTC)`);
      for (const job of replayJobs) {
        if (!/github\.event_name == .schedule./.test(ifOf(job))) out.push(`${job} does not run for the schedule (if: ${ifOf(job)})`);
      }
    } else {
      const validate = jobs.validate ?? "";
      if (!/^    outputs:\n      machinery: \$\{\{ steps\.plan\.outputs\.machinery \}\}$/m.test(validate)) out.push("the validate job has no output machinery from its plan step");
      if (!/^        id: plan$/m.test(validate)) out.push("the validate job has no step with id plan");
      if (!/replay-faults\.sh --plan/.test(validate)) out.push("the plan step does not run replay-faults.sh --plan");
      if (!/\*"machinery changed:"\*\) echo "machinery=true" >>"\$GITHUB_OUTPUT"/.test(validate)) out.push("the plan step does not set machinery=true when the Replay line says machinery changed");
      for (const job of replayJobs) {
        if (!/github\.event_name == .push. && \(github\.ref == .refs\/heads\/main. \|\| needs\.validate\.outputs\.machinery == .true.\)/.test(ifOf(job))) {
          out.push(`${job} does not run for a branch push whose plan says machinery changed (if: ${ifOf(job)})`);
        }
        if (!needsOf(job).split(/[\s,\[\]]+/).includes("validate")) out.push(`${job} does not need validate, so it cannot read its output (needs: ${needsOf(job)})`);
      }
    }
    if (out.length > 0) console.log(out.join("\n"));
  ' "$WORKFLOW" "$1" 2>&1
}

# 1. The weekly full replay: "on:" has the schedule, Mondays at 03:00 UTC, and every replay
# job runs for it.
out="$(problems schedule)"
if [ -z "$out" ]; then
  result "validate.yml: a Monday 03:00 UTC schedule runs the replay jobs" yes ""
else
  result "validate.yml: a Monday 03:00 UTC schedule runs the replay jobs" no "$out"
fi

# 2. The machinery trigger: the validate job runs replay-faults.sh --plan and sets its
# output machinery from the Replay line; every replay job needs validate and runs for a
# push to main, or a push whose machinery output is true.
out="$(problems machinery)"
if [ -z "$out" ]; then
  result "validate.yml: a branch push whose plan names changed machinery runs the replay jobs; the validate job sets that output from replay-faults.sh --plan" yes ""
else
  result "validate.yml: a branch push whose plan names changed machinery runs the replay jobs; the validate job sets that output from replay-faults.sh --plan" no "$out"
fi

[ "$failures" -eq 0 ]
