#!/usr/bin/env bash
# Repository-level checks for harness-kit. Prints one PASS or FAIL line per
# check and exits non-zero if any check fails.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
# empty folder outside any git repository, so there is no report line and no .reports/
# folder is made here, and without HARNESS_KIT_EVAL, so there is no warning (tests/ship.test.sh
# covers both).
expected="harness-kit 0.9.1 loaded"
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

# (j) The reviewer's cases: review.sh (with a fake claude, no API calls),
# check-reviewed.mjs and the reviewer guard hook, one per line.
bash "$ROOT/tests/review.test.sh"
check "tests/review.test.sh (all cases)" "" $?

# (k) The reviewer evaluation's cases: eval-reviewer.sh (with a fake claude, no API calls)
# grades, cleans up its worktrees and never writes .harness/reviews.tsv, one per line.
bash "$ROOT/tests/eval-reviewer.test.sh"
check "tests/eval-reviewer.test.sh (all cases)" "" $?

# (l) The person's own steps: report-path.sh, session-start.mjs's report and commit draft
# lines, stale reports and drafts, the HARNESS_KIT_EVAL warning, check-reports.mjs, land.sh and ship.sh (with a fake
# gh and a local bare repository as the remote, nothing touches GitHub), one per line.
bash "$ROOT/tests/ship.test.sh"
check "tests/ship.test.sh (all cases)" "" $?

# (n) check-commits.mjs's cases: protected files need a reason in a commit body, numbers
# in a body need the diff or a "Told:" line, and --warn, one per line.
bash "$ROOT/tests/check-commits.test.sh"
check "tests/check-commits.test.sh (all cases)" "" $?

# (o) upgrade.sh's cases (with a fake claude, nothing touches GitHub), one per line.
bash "$ROOT/tests/upgrade.test.sh"
check "tests/upgrade.test.sh (all cases)" "" $?

# (m) No report is tracked in this repository.
out="$(cd "$ROOT" && node "$PLUGIN/scripts/check-reports.mjs" 2>&1)"
check "check-reports.mjs on this repository: nothing tracked under .reports/" "$out" $?

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
