#!/usr/bin/env bash
# Repository-level checks for harness-kit. Prints one PASS or FAIL line per
# check and exits non-zero if any check fails.
#
#   bash tests/validate.sh                    every check (CI runs this)
#   bash tests/validate.sh --skip-reviewed    the same: this repository records no reviews,
#                                             so there is no review check to skip. The flag
#                                             is accepted so that .harness/check-command can
#                                             carry it, as land.sh and replay-faults.sh
#                                             require.
#   bash tests/validate.sh --only NAME        only the test files (tests/*.test.sh) that
#                                             .harness/check-files lists for the check NAME,
#                                             exiting non-zero if any fails: what a targeted
#                                             replay runs (replay-faults.sh, with
#                                             .harness/check-only, which this repository does
#                                             not have, so its replays run every check). For a
#                                             NAME with no test file there, every check runs.
# Any other argument is refused.
set -u

only=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-reviewed) ;;
    --only)
      [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "validate.sh: --only needs a check's name" >&2; exit 2; }
      only="$2"
      shift
      ;;
    *)
      echo "validate.sh: unknown argument \"$1\"; the only ones are --skip-reviewed and --only NAME" >&2
      exit 2
      ;;
  esac
  shift
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --only NAME: the test files check-files lists for NAME (its other files are the code the
# check covers, not tests), each run as the whole check runs it.
if [ -n "$only" ]; then
  tests="$(awk -F'\t' -v name="$only" '!/^#/ && NF == 2 && $1 == name && $2 ~ /^tests\/[^\/]+\.test\.sh$/ { print $2 }' \
    "$ROOT/.harness/check-files" 2>/dev/null | sort -u)"
  if [ -n "$tests" ]; then
    status=0
    for test in $tests; do
      bash "$ROOT/$test" </dev/null || status=1
    done
    exit "$status"
  fi
  echo "validate.sh: .harness/check-files lists no test file for \"$only\", so the whole check runs" >&2
fi
PLUGIN="$ROOT/plugins/harness-kit"
failures=0

check() {
  local label="$1" log="$2" status="$3"
  if [ "$status" -eq 0 ]; then
    echo "PASS $label"
  else
    echo "FAIL $label"
    sed 's/^/    /' <<<"$log"
    failures=$((failures + 1))
  fi
}

# (a) Marketplace and plugin validation. A marketplace run does not open the
# plugin's hook, skill, agent or command files, so the plugin folder is
# validated separately.
out="$(claude plugin validate "$ROOT" --strict 2>&1)"
check "claude plugin validate --strict (marketplace: repository root)" "$out" $?

out="$(claude plugin validate "$PLUGIN" --strict 2>&1)"
check "claude plugin validate --strict (plugin: plugins/harness-kit)" "$out" $?

# (b) The SessionStart script prints exactly the expected line and exits 0. It runs in an
# empty folder outside any git repository, so there is no report line, no start-up picture
# and no .reports/ folder is made here, and without HARNESS_KIT_EVAL, so there is no warning (tests/ship.test.sh
# covers both).
expected="harness-kit $(node -p 'require(process.argv[1]).version' "$PLUGIN/.claude-plugin/plugin.json" 2>&1) loaded"
empty="$(mktemp -d)"
out="$(cd "$empty" && env -u HARNESS_KIT_EVAL -u CLAUDE_PROJECT_DIR GIT_CEILING_DIRECTORIES="$(dirname "$empty")" \
  node "$PLUGIN/scripts/session-start.mjs" </dev/null 2>&1)"
status=$?
rm -rf "$empty"
if [ "$status" -eq 0 ] && [ "$out" = "$expected" ]; then
  check "session-start.mjs prints \"$expected\"" "" 0
else
  check "session-start.mjs prints \"$expected\"" \
    "exit $status; got: $out" 1
fi

# (d) and (e) read both manifests. The marketplace entry is found by its
# source, not its name, so a renamed plugin cannot hide the mismatch.
manifest_field() {
  node -e '
    const fs = require("fs");
    const [root, what] = process.argv.slice(1);
    const plugin = JSON.parse(fs.readFileSync(root + "/plugins/harness-kit/.claude-plugin/plugin.json", "utf8"));
    const market = JSON.parse(fs.readFileSync(root + "/.claude-plugin/marketplace.json", "utf8"));
    const entry = (market.plugins || []).find((p) => p.source === "./plugins/harness-kit");
    if (!entry) { console.log("no marketplace entry with source ./plugins/harness-kit"); process.exit(1); }
    if (what === "name") {
      if (plugin.name === entry.name) process.exit(0);
      console.log(`plugin.json name "${plugin.name}" != marketplace entry name "${entry.name}"`);
      process.exit(1);
    }
    if (what === "version") {
      const problems = [];
      if (typeof plugin.version !== "string" || plugin.version === "") problems.push("plugin.json has no version");
      if ("version" in entry) problems.push(`marketplace entry sets version "${entry.version}" (plugin.json wins silently)`);
      if (problems.length === 0) process.exit(0);
      console.log(problems.join("; "));
      process.exit(1);
    }
  ' "$ROOT" "$1" 2>&1
}

# (d) The plugin name matches the marketplace entry name. `claude plugin
# validate` does not check this.
out="$(manifest_field name)"
check "plugin.json name matches marketplace.json entry name" "$out" $?

# (e) version is set in plugin.json only (research/05 section 2).
out="$(manifest_field version)"
check "version set in plugin.json and not in the marketplace entry" "$out" $?

# (f) The Stop hook's behaviour cases. The test prints its own PASS or FAIL
# line per case; this check fails if any of them failed.
bash "$ROOT/tests/stop-gate.test.sh"
check "tests/stop-gate.test.sh (all cases)" "" $?

# (g) The secrets guard's behaviour cases, printed one per line by the test.
bash "$ROOT/tests/guard-secrets.test.sh"
check "tests/guard-secrets.test.sh (all cases)" "" $?

# (h) This repository is public: no tracked file may hold a secret-shaped
# string, including the guard and its test.
out="$(cd "$ROOT" && node "$PLUGIN/scripts/guard-secrets.mjs" --scan 2>&1)"
check "guard-secrets.mjs --scan on this repository: no findings" "$out" $?

# (i) The pre-deploy gate's and deploy.sh's behaviour cases, one per line.
bash "$ROOT/tests/predeploy-gate.test.sh"
check "tests/predeploy-gate.test.sh (all cases)" "" $?

# (j) The reviewer's cases: review.sh (with a fake claude, no API calls; its input's BRIEF
# section too), check-reviewed.mjs and the reviewer guard hook, one per line.
bash "$ROOT/tests/review.test.sh"
check "tests/review.test.sh (all cases)" "" $?

# (k) The reviewer evaluation's cases: eval-reviewer.sh (with a fake claude, no API calls)
# grades, cleans up its worktrees and never writes .harness/reviews.tsv, one per line.
bash "$ROOT/tests/eval-reviewer.test.sh"
check "tests/eval-reviewer.test.sh (all cases)" "" $?

# (l) The person's own steps: report-path.sh, session-start.mjs's report, commit draft,
# commit and blast-radius lines, stale reports, drafts and briefs, the HARNESS_KIT_EVAL
# warning, check-reports.mjs, land.sh, ship.sh (its brief gate, its saved check output, its
# notifications, the review line it commits and the index it refreshes), approve-brief.sh
# (in a pseudo-terminal from python3's pty module, and without one) and install-hooks.sh's
# pre-push and commit-msg hooks (with a fake gh, a fake osascript and a local bare
# repository as the remote, nothing touches GitHub), one per line.
bash "$ROOT/tests/ship.test.sh"
check "tests/ship.test.sh (all cases)" "" $?

# (n) check-commits.mjs's cases: protected files need a reason in a commit body, numbers
# in a body need the diff or a "Told:" line (continued onto the lines after it), replay
# snapshots are exempt, commit references and "v" versions, a Decision: line must not name
# a removed path, --warn, and --message (the commit-msg hook's check), one per line.
bash "$ROOT/tests/check-commits.test.sh"
check "tests/check-commits.test.sh (all cases)" "" $?

# (o) upgrade.sh's cases (with a fake claude and a local repository as harness-kit's
# history, nothing touches GitHub), including the hooks it installs and the pin commit
# draft it writes and proves, one per line.
bash "$ROOT/tests/upgrade.test.sh"
check "tests/upgrade.test.sh (all cases)" "" $?

# (p) replay-faults.sh's and land.sh's replay cases (fake checks in temporary repositories):
# fragile entries, .harness/check-only, entries a patch adds or changes, runs in parallel
# (held on named pipes, never timed), parts judged together, and this script's --only, one
# per line.
bash "$ROOT/tests/replay-faults.test.sh"
check "tests/replay-faults.test.sh (all cases)" "" $?

# (q) check-defects.mjs's cases, one per line.
bash "$ROOT/tests/check-defects.test.sh"
check "tests/check-defects.test.sh (all cases)" "" $?

# (s) harness-metrics.mjs's cases (a fake gh; nothing touches GitHub), one per line.
bash "$ROOT/tests/harness-metrics.test.sh"
check "tests/harness-metrics.test.sh (all cases)" "" $?

# (t) release.sh's cases (a fake gh, a fake osascript and a local bare repository as the
# remote; nothing touches GitHub), one per line.
bash "$ROOT/tests/release.test.sh"
check "tests/release.test.sh (all cases)" "" $?

# (u) git-guard.mjs's cases: git push, destructive git and the person's scripts denied in
# the real working tree and allowed in scratch copies under the temp folder (commands are
# given to the hook, never run), one per line.
bash "$ROOT/tests/git-guard.test.sh"
check "tests/git-guard.test.sh (all cases)" "" $?

# (w) The guards that keep Claude from writing a brief's approval (*.brief.approved):
# brief-guard.mjs on the file tools and git-guard.mjs on Bash, in the real working tree and
# in scratch copies (calls are given to the hooks, never run), one per line.
bash "$ROOT/tests/brief-guard.test.sh"
check "tests/brief-guard.test.sh (all cases)" "" $?

# (x) The SessionStart hook's start-up picture (start-picture.mjs), with fake sources in
# temporary repositories, one per line.
bash "$ROOT/tests/session-start.test.sh"
check "tests/session-start.test.sh (all cases)" "" $?

# (aa) The time-limit helper's cases (time-limit.mjs: the hard stop, its signals, its
# registry and sweep) and check-limits.mjs's, with tiny limits, one per line.
bash "$ROOT/tests/time-limit.test.sh"
check "tests/time-limit.test.sh (all cases)" "" $?

# (ab) background-guard.mjs's cases: background Bash calls given to the hook, never run.
bash "$ROOT/tests/background-guard.test.sh"
check "tests/background-guard.test.sh (all cases)" "" $?

# (ac) Nothing in the plugin starts long work without the time-limit helper, and every
# script that makes a temporary file cleans it up on any exit (check-limits.mjs).
out="$(node "$PLUGIN/scripts/check-limits.mjs" 2>&1)"
check "check-limits.mjs on the plugin's scripts: no long work without the time-limit helper" "$out" $?

# (ad) The hooks that run a check fail closed on time: the check's own limit
# (HOOK_CHECK_MAX_SECONDS, in stop-gate.mjs and predeploy-gate.mjs) plus the helper's grace
# period (time-limit.mjs) is below the hook's timeout in hooks.json, so the hook stops its
# check and decides before Claude Code gives up on it (a hook that times out decides
# nothing, and the stop or the deploy would go ahead).
out="$(node -e '
  const fs = require("fs");
  const [hooksFile, scripts] = process.argv.slice(1);
  const hooks = JSON.parse(fs.readFileSync(hooksFile, "utf8")).hooks;
  const grace = Number(/export const GRACE = \{ env: "[A-Z_]+", seconds: ([0-9]+) \}/.exec(fs.readFileSync(`${scripts}/time-limit.mjs`, "utf8"))?.[1]);
  const problems = [];
  if (!(grace > 0)) problems.push("no grace period (GRACE) in time-limit.mjs");
  for (const [event, script] of [["Stop", "stop-gate.mjs"], ["PreToolUse", "predeploy-gate.mjs"]]) {
    const hook = hooks[event]?.flatMap((m) => m.hooks).find((h) => (h.args ?? []).some((a) => a.endsWith(`/${script}`)));
    const limit = Number(/const HOOK_CHECK_MAX_SECONDS = ([0-9]+);/.exec(fs.readFileSync(`${scripts}/${script}`, "utf8"))?.[1]);
    if (!hook) problems.push(`hooks.json runs no ${script} on ${event}`);
    else if (!(hook.timeout > 0)) problems.push(`the hook running ${script} has no timeout in hooks.json`);
    if (!(limit > 0)) problems.push(`${script} has no HOOK_CHECK_MAX_SECONDS`);
    else if (hook && !(limit + grace < hook.timeout)) problems.push(`${script}: its check limit of ${limit} seconds plus the grace period of ${grace} is not below its hook timeout of ${hook.timeout} seconds`);
  }
  if (problems.length > 0) { console.log(problems.join("\n")); process.exit(1); }
' "$PLUGIN/hooks/hooks.json" "$PLUGIN/scripts" 2>&1)"
check "hooks.json: the Stop hook's check limit plus the grace period is below its timeout; predeploy-gate's likewise" "$out" $?

# (y) This repository checks its own escaped defects (the person's decision):
# check-defects.mjs on .harness/defects.tsv, which must stay append-only, with every line
# the branch adds well formed. check-defects.mjs finds the base (main, or origin/main) and
# its merge-base with HEAD, so in CI it needs the full history, which is why
# .github/workflows/validate.yml checks out with fetch-depth: 0. --skip-reviewed does not
# skip it.
out="$(cd "$ROOT" && node "$PLUGIN/scripts/check-defects.mjs" 2>&1)"
check "this repository's .harness/defects.tsv passes check-defects.mjs (append-only, well-formed lines)" "$out" $?

# (z) The CI fault replay's shape in .github/workflows/validate.yml: a replay-baseline job
# running the baseline part; a replay-shard job that needs it, whose matrix lists exactly the
# shards 1 to 8 (the person's choice), each running --part <shard>/8 with the baseline's
# results (--baseline-from); and a replay-verdicts job that needs both and judges. A shard
# missing from the matrix would leave its entries unreplayed. And the time limits: each
# replay job's timeout-minutes is above the harness's baseline fallback (read from
# replay-faults.mjs), and the workflow's HARNESS_KIT_REPLAY_SESSION_SECONDS is below every
# replay job's timeout, so that the harness reports a hang as TIMEOUT before GitHub cancels.
out="$(node -e '
  const text = require("fs").readFileSync(process.argv[1], "utf8");
  const jobs = {};
  let name = null;
  for (const line of text.split("\n")) {
    const header = /^  ([A-Za-z0-9_-]+):\s*$/.exec(line);
    if (header) { name = header[1]; jobs[name] = ""; continue; }
    if (/^\S/.test(line)) name = null;
    if (name) jobs[name] += line + "\n";
  }
  const problems = [];
  const baseline = jobs["replay-baseline"], shard = jobs["replay-shard"], verdicts = jobs["replay-verdicts"];
  if (!baseline) problems.push("no replay-baseline job");
  else if (!/replay-faults\.sh --part baseline --out /.test(baseline)) problems.push("replay-baseline does not run replay-faults.sh --part baseline --out");
  if (!shard) problems.push("no replay-shard job");
  else {
    const shardNeeds = /^\s+needs: \[([^\]]*)\]/m.exec(shard)?.[1].split(",").map((n) => n.trim()) ?? [];
    if (!shardNeeds.includes("replay-baseline")) problems.push("replay-shard does not need replay-baseline");
    if (!/--baseline-from /.test(shard)) problems.push("replay-shard does not pass --baseline-from");
    const listed = /^\s+shard: \[([0-9, ]*)\]\s*$/m.exec(shard);
    const part = /replay-faults\.sh --part \$\{\{ matrix\.shard \}\}\/([0-9]+) --out /.exec(shard);
    if (!part) problems.push("replay-shard does not run replay-faults.sh --part ${{ matrix.shard }}/N --out");
    else if (part[1] !== "8") problems.push(`replay-shard runs --part <shard>/${part[1]}, not /8`);
    const want = Array.from({ length: 8 }, (_, i) => i + 1).join(",");
    const got = listed ? listed[1].split(",").map((n) => n.trim()).join(",") : "(no shard: [...] line)";
    if (got !== want) problems.push(`replay-shard matrix shards are ${got}, not ${want}`);
  }
  if (!verdicts) problems.push("no replay-verdicts job");
  else {
    const needs = /^\s+needs: \[([^\]]*)\]/m.exec(verdicts)?.[1].split(",").map((n) => n.trim()) ?? [];
    for (const job of ["replay-baseline", "replay-shard"]) if (!needs.includes(job)) problems.push(`replay-verdicts does not need ${job}`);
    if (!/replay-faults\.sh --judge /.test(verdicts)) problems.push("replay-verdicts does not run replay-faults.sh --judge");
  }
  const fallback = Number(/HARNESS_KIT_REPLAY_BASELINE_FALLBACK_SECONDS: ([0-9]+)/.exec(require("fs").readFileSync(process.argv[2], "utf8"))?.[1]);
  if (!(fallback > 0)) problems.push("no HARNESS_KIT_REPLAY_BASELINE_FALLBACK_SECONDS default in replay-faults.mjs");
  const topEnv = /^env:\n((?:[ #].*\n|\n)*)/m.exec(text)?.[1] ?? "";
  const session = Number(/^\s+HARNESS_KIT_REPLAY_SESSION_SECONDS: ([0-9]+)\s*$/m.exec(topEnv)?.[1]);
  if (!(session > 0)) problems.push("the workflow env: sets no HARNESS_KIT_REPLAY_SESSION_SECONDS");
  for (const [name, job] of [["replay-baseline", baseline], ["replay-shard", shard], ["replay-verdicts", verdicts]]) {
    if (!job) continue;
    const minutes = Number(/^\s+timeout-minutes: ([0-9]+)/m.exec(job)?.[1]);
    if (!(minutes > 0)) { problems.push(`${name} has no timeout-minutes`); continue; }
    if (minutes * 60 <= fallback) problems.push(`${name} times out at ${minutes} minutes, not above the baseline fallback of ${fallback} seconds`);
    if (session > 0 && session >= minutes * 60) problems.push(`the session limit of ${session} seconds is not below the timeout of ${name}, ${minutes} minutes`);
  }
  if (problems.length > 0) { console.log(problems.join("\n")); process.exit(1); }
' "$ROOT/.github/workflows/validate.yml" "$PLUGIN/scripts/replay-faults.mjs" 2>&1)"
check "validate.yml: the CI replay is one baseline part, shards 1 to 8 each passing --part i/8, and a verdicts job that needs them all" "$out" $?

# (r) The record-defect and brief skills are started only by the person: their frontmatter
# turns off model invocation.
for name in record-defect brief; do
  skill="$PLUGIN/skills/$name/SKILL.md"
  out="$(awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { exit found ? 0 : 1 } /^disable-model-invocation: true$/ { found = 1 } END { if (!found) exit 1 }' "$skill" 2>&1)"
  check "skills/$name/SKILL.md has disable-model-invocation: true" "${out:-no \"disable-model-invocation: true\" line in its frontmatter}" $?
done

# (v) The brief skill's brief has the fixed sections, in this order, and the skill raises
# OPEN spec rules before planning and never approves its own brief.
skill="$PLUGIN/skills/brief/SKILL.md"
got="$(sed -n '/^# Brief: /,/^```$/p' "$skill" | grep '^## ' | tr '\n' '|')"
want="## Goal|## Scope|## Spec rules touched|## Acceptance tests|## Verification plan|## Blast radius|## New thresholds|## Protected files expected|"
out="sections in the brief template: $got"
[ "$got" = "$want" ] && grep -q 'stop before planning further' "$skill" && grep -q '\.harness/review-reads' "$skill" &&
  grep -q 'Never write `.reports/<branch>.brief.approved`, and never run `approve-brief.sh`' "$skill"
check "skills/brief/SKILL.md: the brief's eight sections in order; OPEN rules raised first; never approves itself" "$out" $?

# (ae) Harness commands are written by their full names (/harness-kit:<name>), no retired
# name comes back, and no skill is named like a Claude Code built-in (check-names.mjs, with
# the built-in list in tests/claude-builtins.txt). The test prints one line per case.
bash "$ROOT/tests/check-names.test.sh"
check "tests/check-names.test.sh (all cases)" "" $?

# (af) plan-mode-guard.mjs refuses Claude's EnterPlanMode tool, and hooks.json runs it.
bash "$ROOT/tests/plan-mode-guard.test.sh"
check "tests/plan-mode-guard.test.sh (all cases)" "" $?

# (m) No report is tracked in this repository.
out="$(cd "$ROOT" && node "$PLUGIN/scripts/check-reports.mjs" 2>&1)"
check "check-reports.mjs on this repository: nothing tracked under .reports/" "$out" $?

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
