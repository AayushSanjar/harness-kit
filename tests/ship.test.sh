#!/usr/bin/env bash
# Tests for the person's own steps: report-path.sh, the report, commit draft and warning
# lines of session-start.mjs, check-reports.mjs, land.sh and ship.sh.
#
# Every case runs in a temporary git repository. Its "origin" is a local bare repository,
# and ship.sh finds a FAKE `gh` first on PATH, which records its arguments and prints
# canned run JSON; review.sh finds a FAKE `claude`, as in review.test.sh. Nothing touches
# GitHub and no API call is made. Prints one PASS or FAIL line per case and exits non-zero
# if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/plugins/harness-kit/scripts"
REPORT_PATH="$SCRIPTS/report-path.sh"
SESSION_START="$SCRIPTS/session-start.mjs"
CHECK_REPORTS="$SCRIPTS/check-reports.mjs"
LAND="$SCRIPTS/land.sh"
SHIP="$SCRIPTS/ship.sh"
VERSION="$(node -p 'require(process.argv[1]).version' "$ROOT/plugins/harness-kit/.claude-plugin/plugin.json")"
# The real path: git prints resolved paths, and macOS's temp folder is behind a symlink.
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
failures=0

# The test repositories must not depend on the person's git settings (signing, hooks,
# default branch), and no case may inherit the person's session.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset HARNESS_KIT_EVAL CLAUDE_PROJECT_DIR
# ship.sh: runs appear at once in the fake gh, so never sleep.
export SHIP_POLL_SECONDS=0 SHIP_CI_APPEAR_SECONDS=0

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

describe() { printf 'exit %s\nstdout: %s\nstderr: %s' "$STATUS" "$OUT" "$ERR"; }

# ---------------------------------------------------------------------------------------
# Fakes
# ---------------------------------------------------------------------------------------
mkdir -p "$WORK/bin"

# The fake claude: records how it was called, then prints $FAKE_JSON.
cat >"$WORK/bin/claude" <<'FAKE'
#!/bin/sh
printf '%s\n' "$@" >"$FAKE_LOG/claude-args"
cat >/dev/null
cat "$FAKE_JSON"
FAKE

# The fake gh: appends each call to $FAKE_LOG/gh-calls. Its runs are the lines of
# $FAKE_LOG/runs, "<id> <workflow> <conclusion> <from>": the run is listed from the
# <from>th `gh run list` call on (counted in $FAKE_LOG/list-calls). With no runs file there
# is one run, 4242 of "validate", with the conclusion in $FAKE_LOG/conclusion, listed from
# the first call. Every run is completed. `--workflow` filters by workflow name.
cat >"$WORK/bin/gh" <<'FAKE'
#!/usr/bin/env node
const fs = require("fs");
const log = process.env.FAKE_LOG;
const args = process.argv.slice(2);
fs.appendFileSync(`${log}/gh-calls`, args.join(" ") + "\n");
const read = (f) => { try { return fs.readFileSync(`${log}/${f}`, "utf8").trim(); } catch { return ""; } };
const runs = (read("runs") || `4242 validate ${read("conclusion")} 1`).split("\n").map((line) => {
  const [id, workflowName, conclusion, from] = line.trim().split(/\s+/);
  return { databaseId: Number(id), workflowName, status: "completed", conclusion,
    url: `https://ci.example.invalid/runs/${id}`, from: Number(from) };
});
const opt = (name) => { const i = args.indexOf(name); return i < 0 ? undefined : args[i + 1]; };
const byId = () => runs.find((r) => r.databaseId === Number(args[2]));
const sub = `${args[0]} ${args[1]}`;
if (sub === "run list") {
  const call = Number(read("list-calls") || 0) + 1;
  fs.writeFileSync(`${log}/list-calls`, String(call));
  const workflow = opt("--workflow");
  console.log(JSON.stringify(runs
    .filter((r) => r.from <= call && (!workflow || r.workflowName === workflow))
    .map(({ from, ...r }) => r)));
} else if (sub === "run watch") {
  process.exit(byId()?.conclusion === "success" ? 0 : 1);
} else if (sub === "run view" && byId()) {
  const { status, conclusion, url } = byId();
  console.log(JSON.stringify({ status, conclusion, url }));
} else {
  console.error(`fake gh: unexpected call: ${args.join(" ")}`);
  process.exit(64);
}
FAKE
chmod +x "$WORK/bin/claude" "$WORK/bin/gh"

canned() {
  node -e '
    require("fs").writeFileSync(process.argv[1], JSON.stringify({
      type: "result", subtype: "success", is_error: false,
      duration_ms: 1000, num_turns: 2, result: process.argv[2], total_cost_usd: 0.01,
    }));
  ' "$WORK/$1.json" "$2"
  echo "$WORK/$1.json"
}
PASS_JSON="$(canned pass $'## Items\nR1 — PASS — app.txt:2 "world"\n\n## Verdict\nPASS.\nVERDICT PASS R1=P')"
FIX_JSON="$(canned fix $'## Items\nR1 — FAIL — app.txt:2 no test\n\n## Verdict\nFIX-FIRST: add the test.\nVERDICT FIX-FIRST R1=F')"

# ---------------------------------------------------------------------------------------
# Repositories
# ---------------------------------------------------------------------------------------

# new_repo NAME: a repository whose origin is the bare repository NAME.git, with main
# (a checklist, a check command, app.txt) pushed, and a branch "feature" with one more
# commit, not pushed. The check command runs .harness/check.sh with --skip-reviewed, which
# ship.sh requires before a review. Prints its path.
new_repo() {
  local dir="$WORK/$1" bare="$WORK/$1.git"
  git init -q --bare "$bare"
  mkdir -p "$dir/.harness" "$dir.log"
  git -C "$dir" init -q -b main
  printf 'hello\n' >"$dir/app.txt"
  printf '# Review checklist\n\n- R1: app.txt changes have a test\n' >"$dir/.harness/review-checklist.md"
  printf 'echo "check: 1 passed"\n' >"$dir/.harness/check.sh"
  printf 'sh .harness/check.sh --skip-reviewed\n' >"$dir/.harness/check-command"
  git -C "$dir" add -A && git -C "$dir" commit -q -m "main: initial"
  git -C "$dir" remote add origin "$bare"
  git -C "$dir" push -q -u origin main
  git -C "$dir" checkout -q -b feature
  printf 'hello\nworld\n' >"$dir/app.txt"
  git -C "$dir" commit -q -am "feature: add world"
  echo "$dir"
}

# run_in DIR CMD...: run CMD in DIR with the fakes first on PATH; sets OUT, ERR, STATUS.
run_in() {
  local dir="$1"
  shift
  OUT="$(cd "$dir" && PATH="$WORK/bin:$PATH" FAKE_LOG="$dir.log" "$@" 2>"$WORK/stderr")"
  STATUS=$?
  ERR="$(cat "$WORK/stderr")"
}

# run_ship DIR JSON CONCLUSION: run ship.sh in DIR; a fresh fake log each time (a runs
# file, if a case wrote one, is kept).
run_ship() {
  rm -f "$1.log/claude-args" "$1.log/gh-calls" "$1.log/list-calls"
  printf '%s\n' "$3" >"$1.log/conclusion"
  FAKE_JSON="$2" run_in "$1" bash "$SHIP"
}

# run_session DIR [AGENT_TYPE]: run the SessionStart hook for a session in DIR.
run_session() {
  local input
  input="$(node -e '
    const [cwd, agentType] = process.argv.slice(1);
    const input = { session_id: "s1", hook_event_name: "SessionStart", source: "startup", cwd };
    if (agentType) input.agent_type = agentType;
    console.log(JSON.stringify(input));
  ' "$1" "${2:-}")"
  OUT="$(CLAUDE_PROJECT_DIR="$1" node "$SESSION_START" <<<"$input" 2>"$WORK/stderr")"
  STATUS=$?
  ERR="$(cat "$WORK/stderr")"
}

rev() { git -C "$1" rev-parse "$2" 2>/dev/null; }
remote_rev() { git --git-dir="$1.git" rev-parse -q --verify "refs/heads/$2" 2>/dev/null; }

# ---------------------------------------------------------------------------------------
# report-path.sh and session-start.mjs
# ---------------------------------------------------------------------------------------

# 1. Naming: "/" becomes "-", the path is absolute in the project root even when run from a
# subfolder, latest.md is a relative symlink that follows the branch, --name changes
# nothing, and a detached HEAD gets its own name.
dir="$(new_repo naming)"
git -C "$dir" checkout -q -b feat/x-y
mkdir -p "$dir/sub"
run_in "$dir/sub" bash "$REPORT_PATH"
got1="$OUT" link1="$(readlink "$dir/.reports/latest.md")"
git -C "$dir" checkout -q main
run_in "$dir" bash "$REPORT_PATH"
got2="$OUT" link2="$(readlink "$dir/.reports/latest.md")"
run_in "$dir" bash "$REPORT_PATH" --name team/a/b
got3="$OUT" link3="$(readlink "$dir/.reports/latest.md")"
run_in "$dir/sub" bash "$REPORT_PATH" --commit
got5="$OUT" link5="$(readlink "$dir/.reports/latest.commit.txt")"
run_in "$dir" bash "$REPORT_PATH" --name team/a/b --commit
got6="$OUT" link6="$(readlink "$dir/.reports/latest.commit.txt")"
git -C "$dir" checkout -q --detach
run_in "$dir" bash "$REPORT_PATH"
got4="$OUT"
sha12="$(rev "$dir" HEAD | cut -c1-12)"
if [ "$got1" = "$dir/.reports/feat-x-y.md" ] && [ "$link1" = feat-x-y.md ] &&
  [ "$got2" = "$dir/.reports/main.md" ] && [ "$link2" = main.md ] &&
  [ "$got3" = "$dir/.reports/team-a-b.md" ] && [ "$link3" = main.md ] &&
  [ "$got4" = "$dir/.reports/detached-$sha12.md" ] &&
  [ "$got5" = "$dir/.reports/main.commit.txt" ] && [ "$link5" = main.commit.txt ] &&
  [ "$got6" = "$dir/.reports/team-a-b.commit.txt" ] && [ "$link6" = main.commit.txt ] &&
  [ -z "$(find "$dir/.reports" -type f)" ]; then
  result "report-path: <branch with / as -> .md (--commit: .commit.txt) in .reports/, and latest.md (latest.commit.txt) points at it" yes ""
else
  result "report-path: <branch with / as -> .md (--commit: .commit.txt) in .reports/, and latest.md (latest.commit.txt) points at it" no \
    "got: $got1 -> $link1 | $got2 -> $link2 | $got3 (latest $link3) | $got4 | $got5 -> $link5 | $got6 (latest $link6)
files: $(find "$dir/.reports" -type f)"
fi

# 2. Stale reports: the SessionStart hook removes reports that no local branch maps to,
# and keeps the current branch's report, another live branch's report, and the file
# latest.md pointed at when the session started. Its stdout has the version line and the
# report line, as plain text.
dir="$(new_repo stale)"
git -C "$dir" branch old
git -C "$dir" branch team/live
mkdir -p "$dir/.reports"
for f in feature old team-live gone pinned; do printf '# %s\n' "$f" >"$dir/.reports/$f.md"; done
for f in feature old gone pinned; do printf 'draft %s\n' "$f" >"$dir/.reports/$f.commit.txt"; done
ln -s pinned.md "$dir/.reports/latest.md"
ln -s pinned.commit.txt "$dir/.reports/latest.commit.txt"
git -C "$dir" branch -q -D old
run_session "$dir"
left="$(cd "$dir/.reports" && ls | tr '\n' ' ')"
line2="$(sed -n 2p <<<"$OUT")"
line3="$(sed -n 3p <<<"$OUT")"
if [ "$STATUS" -eq 0 ] &&
  [ "$left" = "feature.commit.txt feature.md latest.commit.txt latest.md pinned.commit.txt pinned.md team-live.md " ] &&
  [ "$(readlink "$dir/.reports/latest.md")" = feature.md ] &&
  [ "$(sed -n 1p <<<"$OUT")" = "harness-kit $VERSION loaded" ] &&
  grep -qF "write your final report to $dir/.reports/feature.md" <<<"$line2" &&
  grep -qF '"## Summary"' <<<"$line2" && grep -q 'at most 15 lines' <<<"$line2" &&
  grep -q 'Never commit it' <<<"$line2" &&
  [ "$(wc -l <<<"$OUT" | tr -d ' ')" = 3 ] &&
  grep -q 'removed the stale report .reports/gone.md' <<<"$ERR" &&
  grep -q 'removed the stale report .reports/old.md' <<<"$ERR" &&
  grep -q 'removed the stale commit draft .reports/gone.commit.txt' <<<"$ERR" &&
  grep -q 'removed the stale commit draft .reports/old.commit.txt' <<<"$ERR"; then
  result "session-start: stale reports and commit drafts removed; the current, live and latest's kept" yes ""
else
  result "session-start: stale reports and commit drafts removed; the current, live and latest's kept" no \
    "$(describe)
left: $left"
fi

# 2c. The commit draft line: the path of the current branch's draft (latest.commit.txt
# points at it), and each rule for the body that check-commits.mjs and the reviewer check.
if [ "$(readlink "$dir/.reports/latest.commit.txt")" = feature.commit.txt ] &&
  grep -qF "write the commit message for all of the branch's uncommitted changes to $dir/.reports/feature.commit.txt" <<<"$line3" &&
  grep -qF 'whenever you change files' <<<"$line3" && grep -qF 'one-line subject' <<<"$line3" &&
  grep -qF 'names every changed file that .harness/protected-paths lists, by its full path, with the reason it changed' <<<"$line3" &&
  grep -qF 'on a line starting "Told:" with its source' <<<"$line3" &&
  grep -qF 'a line starting "Breaks:" for every new or changed check or test, naming what makes it fail' <<<"$line3" &&
  grep -qF 'a line starting "Decision:" for every choice that closes off an alternative' <<<"$line3"; then
  result "session-start: the commit draft line names .reports/<branch>.commit.txt and the Told:, Breaks:, Decision: and protected-file rules" yes ""
else
  result "session-start: the commit draft line names .reports/<branch>.commit.txt and the Told:, Breaks:, Decision: and protected-file rules" no \
    "latest.commit.txt -> $(readlink "$dir/.reports/latest.commit.txt")
line 3: $line3"
fi

# 2b. The Summary template: the report line names all five headings, in this order.
headings="$(grep -oE '"(Result|Evidence|Deviations|Decide|Your commands):"' <<<"$line2" | tr '\n' ' ')"
want='"Result:" "Evidence:" "Deviations:" "Decide:" "Your commands:" '
if [ "$headings" = "$want" ] && grep -qF '"Decide:" what the person must decide; "none" if none.' <<<"$line2"; then
  result "session-start: the Summary template has Result, Evidence, Deviations, Decide, Your commands, in that order" yes ""
else
  result "session-start: the Summary template has Result, Evidence, Deviations, Decide, Your commands, in that order" no \
    "headings found, in order: $headings
line 2: $line2"
fi

# 3. check-reports: an untracked report passes; a staged one fails, and so does a
# committed one, naming the file.
dir="$(new_repo check-reports)"
mkdir -p "$dir/.reports" && printf '# report\n' >"$dir/.reports/feature.md"
run_in "$dir" node "$CHECK_REPORTS"
control="$STATUS: $OUT"
git -C "$dir" add .reports/feature.md
run_in "$dir" node "$CHECK_REPORTS"
staged="$STATUS: $OUT"
git -C "$dir" commit -q -m "a report, by mistake"
run_in "$dir" node "$CHECK_REPORTS"
if [ "${control%%:*}" = 0 ] && grep -q '^0: PASS check-reports' <<<"$control" &&
  grep -q '^1: FAIL check-reports: git tracks 1 file(s) under .reports/.*\.reports/feature\.md' <<<"$staged" &&
  [ "$STATUS" -eq 1 ] && grep -q '^FAIL check-reports: .*\.reports/feature\.md' <<<"$OUT"; then
  result "check-reports: fails on a tracked report (staged or committed); passes when untracked" yes ""
else
  result "check-reports: fails on a tracked report (staged or committed); passes when untracked" no \
    "untracked: $control
staged: $staged
committed: $(describe)"
fi

# 4-6. The HARNESS_KIT_EVAL warning.
dir="$(new_repo eval-warning)"
HARNESS_KIT_EVAL=1 run_session "$dir"
parsed="$(node -e '
  const o = JSON.parse(process.argv[1]);
  console.log(o.systemMessage);
  console.log("---");
  console.log(o.hookSpecificOutput.hookEventName);
  console.log(o.hookSpecificOutput.additionalContext);
' "$OUT" 2>&1)"
if [ "$STATUS" -eq 0 ] &&
  grep -q '^harness-kit WARNING: HARNESS_KIT_EVAL is set in this session, so the Stop hook is OFF' <<<"$parsed" &&
  grep -qx 'SessionStart' <<<"$parsed" && grep -qx "harness-kit $VERSION loaded" <<<"$parsed" &&
  grep -q "write your final report to $dir/.reports/feature.md" <<<"$parsed" &&
  [ "$(grep -c 'Stop hook is OFF' <<<"$parsed")" = 2 ]; then
  result "session-start: HARNESS_KIT_EVAL set: a visible warning (systemMessage) that the Stop hook is OFF" yes ""
else
  result "session-start: HARNESS_KIT_EVAL set: a visible warning (systemMessage) that the Stop hook is OFF" no \
    "$(describe)
parsed: $parsed"
fi

run_session "$dir"
if [ "$STATUS" -eq 0 ] && [ "$(sed -n 1p <<<"$OUT")" = "harness-kit $VERSION loaded" ] &&
  ! grep -q 'OFF\|HARNESS_KIT_EVAL\|systemMessage' <<<"$OUT$ERR"; then
  result "session-start: HARNESS_KIT_EVAL unset: no warning" yes ""
else
  result "session-start: HARNESS_KIT_EVAL unset: no warning" no "$(describe)"
fi

rm -rf "$dir/.reports"
HARNESS_KIT_EVAL=1 run_session "$dir" harness-kit:reviewer
if [ "$STATUS" -eq 0 ] && [ "$OUT" = "harness-kit $VERSION loaded" ] && [ -z "$ERR" ] && [ ! -e "$dir/.reports" ]; then
  result "session-start: the reviewer's session gets the version line only (no report, no warning)" yes ""
else
  result "session-start: the reviewer's session gets the version line only (no report, no warning)" no "$(describe)"
fi

# ---------------------------------------------------------------------------------------
# land.sh
# ---------------------------------------------------------------------------------------

# new_land NAME CHECK_EXIT [CHECK_COMMAND]: a repository on "feature" whose approval
# command reads one line from the terminal and records it, and whose check command is
# CHECK_COMMAND (default `sh scripts/check.sh --skip-reviewed`). scripts/check.sh records
# its arguments; like a real project's check, it runs check-reviewed.mjs unless given
# --skip-reviewed (on this unreviewed branch that fails, and leaves check-reviewed-ran),
# then exits CHECK_EXIT. Writes NAME.patch (app.txt: add a line). Prints its path.
new_land() {
  local dir
  dir="$(new_repo "$1")"
  mkdir -p "$dir/scripts"
  cat >"$dir/scripts/check.sh" <<CHECK
printf '%s\n' "\$@" > "$dir.log/check-args"
case " \$* " in
  *" --skip-reviewed "*) ;;
  *) touch "$dir.log/check-reviewed-ran"; node "$SCRIPTS/check-reviewed.mjs" || exit 1 ;;
esac
exit $2
CHECK
  printf 'read answer && printf "%%s\\n" "$answer" > "%s/approved"\n' "$dir.log" >"$dir/.harness/approve-command"
  printf '%s\n' "${3:-sh scripts/check.sh --skip-reviewed}" >"$dir/.harness/check-command"
  git -C "$dir" add -A && git -C "$dir" commit -q -m "land setup"
  printf 'hello\nworld\nlanded\n' >"$dir/app.txt"
  git -C "$dir" diff >"$WORK/$1.patch"
  git -C "$dir" checkout -q -- app.txt
  echo "$dir"
}

# 7. A patch that does not apply: stops before changing anything, approving or checking.
dir="$(new_land land-bad 0)"
printf 'goodbye\n' >"$dir/app.txt" && git -C "$dir" commit -q -am "app.txt moved on"
head_before="$(rev "$dir" HEAD)"
OUT="$(cd "$dir" && bash "$LAND" "$WORK/land-bad.patch" <<<"yes" 2>&1)"
STATUS=$? ERR=""
if [ "$STATUS" -eq 1 ] && grep -q 'STOPPED: the patch does not apply cleanly' <<<"$OUT" &&
  [ -z "$(git -C "$dir" status --porcelain)" ] && [ "$(rev "$dir" HEAD)" = "$head_before" ] &&
  [ ! -e "$dir.log/approved" ] && [ ! -e "$dir.log/check-args" ]; then
  result "land.sh: stops on a patch that does not apply, changing nothing" yes ""
else
  result "land.sh: stops on a patch that does not apply, changing nothing" no "$(describe)"
fi

# 8. A failing check: stops with a clear message; the patch stays applied, uncommitted.
dir="$(new_land land-red 1)"
head_before="$(rev "$dir" HEAD)"
OUT="$(cd "$dir" && bash "$LAND" "$WORK/land-red.patch" <<<"yes" 2>&1)"
STATUS=$? ERR=""
if [ "$STATUS" -eq 1 ] && grep -q 'STOPPED: the check failed (exit 1): sh scripts/check.sh' <<<"$OUT" &&
  grep -q 'The patch IS applied and nothing was committed' <<<"$OUT" &&
  [ "$(git -C "$dir" status --porcelain)" = " M app.txt" ] && [ "$(rev "$dir" HEAD)" = "$head_before" ] &&
  [ "$(cat "$dir.log/approved" 2>/dev/null)" = yes ] && [ -e "$dir.log/check-args" ] &&
  ! grep -q LANDED <<<"$OUT"; then
  result "land.sh: stops on a failing check, patch applied and uncommitted" yes ""
else
  result "land.sh: stops on a failing check, patch applied and uncommitted" no "$(describe)"
fi

# 9. The whole path: applied, approved (the approval read the person's answer), checked
# WITH --skip-reviewed (so check-reviewed did not run: the review is ship.sh's), nothing
# committed, and the next step printed.
dir="$(new_land land-green 0)"
head_before="$(rev "$dir" HEAD)"
OUT="$(cd "$dir" && bash "$LAND" "$WORK/land-green.patch" <<<"yes" 2>&1)"
STATUS=$? ERR=""
check_args="$(cat "$dir.log/check-args" 2>/dev/null || echo '(the check did not run)')"
if [ "$STATUS" -eq 0 ] && grep -q '^harness-kit land.sh: LANDED' <<<"$OUT" && grep -q 'run ship.sh' <<<"$OUT" &&
  [ "$(cat "$dir.log/approved" 2>/dev/null)" = yes ] && grep -qx -- '--skip-reviewed' <<<"$check_args" &&
  [ ! -e "$dir.log/check-reviewed-ran" ] &&
  [ "$(git -C "$dir" status --porcelain)" = " M app.txt" ] && [ "$(rev "$dir" HEAD)" = "$head_before" ]; then
  result "land.sh: applies, approves, runs the check with --skip-reviewed (no review check), commits nothing" yes ""
else
  result "land.sh: applies, approves, runs the check with --skip-reviewed (no review check), commits nothing" no "$(describe)
check args: $check_args"
fi

# 10. A check command without --skip-reviewed: land.sh never adds it. It stops before
# applying anything (no approval, no check, tree and HEAD unchanged) and prints the line
# to put in .harness/check-command.
dir="$(new_land land-no-flag 0 'sh scripts/check.sh')"
head_before="$(rev "$dir" HEAD)"
OUT="$(cd "$dir" && bash "$LAND" "$WORK/land-no-flag.patch" <<<"yes" 2>&1)"
STATUS=$? ERR=""
if [ "$STATUS" -eq 1 ] && grep -q 'STOPPED: .harness/check-command does not pass --skip-reviewed' <<<"$OUT" &&
  grep -q 'Nothing was changed' <<<"$OUT" && grep -q '^harness-kit land.sh:     sh scripts/check.sh --skip-reviewed$' <<<"$OUT" &&
  [ -z "$(git -C "$dir" status --porcelain)" ] && [ "$(rev "$dir" HEAD)" = "$head_before" ] &&
  [ ! -e "$dir.log/approved" ] && [ ! -e "$dir.log/check-args" ] && [ ! -e "$dir.log/check-reviewed-ran" ]; then
  result "land.sh: a check command without --skip-reviewed stops before applying, and says how to add it" yes ""
else
  result "land.sh: a check command without --skip-reviewed stops before applying, and says how to add it" no "$(describe)"
fi

# 11. No check command at all: the same, stopped before applying anything.
dir="$(new_land land-no-check 0)"
git -C "$dir" rm -q .harness/check-command && git -C "$dir" commit -q -m "no check command"
OUT="$(cd "$dir" && bash "$LAND" "$WORK/land-no-check.patch" <<<"yes" 2>&1)"
STATUS=$? ERR=""
if [ "$STATUS" -eq 1 ] && grep -q 'STOPPED: no .harness/check-command' <<<"$OUT" && grep -q 'Nothing was changed' <<<"$OUT" &&
  [ -z "$(git -C "$dir" status --porcelain)" ] && [ ! -e "$dir.log/approved" ]; then
  result "land.sh: no check command stops before applying" yes ""
else
  result "land.sh: no check command stops before applying" no "$(describe)"
fi

# ---------------------------------------------------------------------------------------
# ship.sh
# ---------------------------------------------------------------------------------------

# 12. On main: refused, and nothing reviewed, pushed or asked of gh.
dir="$(new_repo ship-main)"
git -C "$dir" checkout -q main
run_ship "$dir" "$PASS_JSON" success
if [ "$STATUS" -eq 2 ] && grep -q 'REFUSED: you are on main' <<<"$ERR" &&
  [ ! -e "$dir.log/claude-args" ] && [ ! -e "$dir.log/gh-calls" ] && [ -z "$(remote_rev "$dir" feature)" ]; then
  result "ship.sh: refuses on main" yes ""
else
  result "ship.sh: refuses on main" no "$(describe)"
fi

# 13. Uncommitted changes to a tracked file: refused, nothing done.
dir="$(new_repo ship-dirty)"
printf 'hello\nworld\nnot committed\n' >"$dir/app.txt"
run_ship "$dir" "$PASS_JSON" success
if [ "$STATUS" -eq 2 ] && grep -q 'REFUSED: there are uncommitted changes' <<<"$ERR" &&
  [ ! -e "$dir.log/claude-args" ] && [ ! -e "$dir.log/gh-calls" ] && [ -z "$(remote_rev "$dir" feature)" ]; then
  result "ship.sh: refuses with uncommitted changes" yes ""
else
  result "ship.sh: refuses with uncommitted changes" no "$(describe)"
fi

# 14. A FIX-FIRST review: stops showing the verdict; nothing committed, pushed or merged.
dir="$(new_repo ship-fix)"
head_before="$(rev "$dir" HEAD)"
run_ship "$dir" "$FIX_JSON" success
if [ "$STATUS" -eq 1 ] && [ -e "$dir.log/claude-args" ] &&
  grep -q "STOPPED: the review's verdict is FIX-FIRST (R1=F), not PASS" <<<"$ERR" &&
  grep -q '^R1 — FAIL' <<<"$OUT" && [ "$(rev "$dir" HEAD)" = "$head_before" ] &&
  [ ! -e "$dir.log/gh-calls" ] && [ -z "$(remote_rev "$dir" feature)" ] &&
  [ "$(rev "$dir" main)" = "$(remote_rev "$dir" main)" ]; then
  result "ship.sh: stops on a non-PASS review and shows the verdict" yes ""
else
  result "ship.sh: stops on a non-PASS review and shows the verdict" no "$(describe)"
fi

# 14b. A failing check: ship.sh runs it before the review, stops, and never calls claude;
# nothing committed, pushed or asked of gh.
dir="$(new_repo ship-check-red)"
printf 'echo "FAIL unit tests: 1 failed"\nexit 1\n' >"$dir/.harness/check.sh"
git -C "$dir" commit -q -am "feature: break the check"
head_before="$(rev "$dir" HEAD)"
run_ship "$dir" "$PASS_JSON" success
if [ "$STATUS" -eq 1 ] && grep -q '^FAIL unit tests: 1 failed$' <<<"$OUT" &&
  grep -q 'STOPPED: the check failed (exit 1, above): sh .harness/check.sh --skip-reviewed. No review was started.' <<<"$ERR" &&
  [ ! -e "$dir.log/claude-args" ] && [ ! -e "$dir.log/gh-calls" ] && [ ! -e "$dir/.harness/reviews.tsv" ] &&
  [ "$(rev "$dir" HEAD)" = "$head_before" ] && [ -z "$(remote_rev "$dir" feature)" ]; then
  result "ship.sh: a failing check stops it before the review, with no claude call" yes ""
else
  result "ship.sh: a failing check stops it before the review, with no claude call" no "$(describe)"
fi

# 14c. A check command without --skip-reviewed: ship.sh never adds it; it stops before the
# check and the review, and prints the line to write.
dir="$(new_repo ship-no-flag)"
printf 'sh .harness/check.sh\n' >"$dir/.harness/check-command"
git -C "$dir" commit -q -am "feature: check without the flag"
run_ship "$dir" "$PASS_JSON" success
if [ "$STATUS" -eq 1 ] && grep -q 'STOPPED: the first line of .harness/check-command does not pass --skip-reviewed' <<<"$ERR" &&
  grep -qF '(for a single command: sh .harness/check.sh --skip-reviewed)' <<<"$ERR" &&
  ! grep -q 'check: 1 passed' <<<"$OUT" && [ ! -e "$dir.log/claude-args" ] && [ ! -e "$dir.log/gh-calls" ]; then
  result "ship.sh: a check command without --skip-reviewed stops it before the check and the review" yes ""
else
  result "ship.sh: a check command without --skip-reviewed stops it before the check and the review" no "$(describe)"
fi

# 15. Red CI: the review is committed and the branch pushed, then it stops with the run's
# URL; main is not touched, locally or on the remote. (Case 16 resumes this repository.)
dir="$(new_repo ship-red)"
main_before="$(rev "$dir" main)"
run_ship "$dir" "$PASS_JSON" failure
red_head="$(rev "$dir" HEAD)"
if [ "$STATUS" -eq 1 ] && grep -q 'conclusion "failure", not success: https://ci.example.invalid/runs/4242' <<<"$ERR" &&
  [ "$(git -C "$dir" log -1 --format=%s)" = "Record review of feature: PASS" ] &&
  [ "$(remote_rev "$dir" feature)" = "$red_head" ] && grep -q -- "run list --commit $red_head" "$dir.log/gh-calls" &&
  [ "$(git -C "$dir" symbolic-ref --short HEAD)" = feature ] &&
  [ "$(rev "$dir" main)" = "$main_before" ] && [ "$(remote_rev "$dir" main)" = "$main_before" ]; then
  result "ship.sh: stops on red CI with the run's URL; main untouched" yes ""
else
  result "ship.sh: stops on red CI with the run's URL; main untouched" no "$(describe)
gh calls: $(cat "$dir.log/gh-calls" 2>/dev/null)"
fi

# 16. Resume after red CI: the run is green now. No second review, no new commit; merged.
run_ship "$dir" "$PASS_JSON" success
if [ "$STATUS" -eq 0 ] && [ ! -e "$dir.log/claude-args" ] && grep -q 'already has a committed PASS review' <<<"$ERR" &&
  [ "$(rev "$dir" feature)" = "$red_head" ] && [ "$(rev "$dir" main)" = "$red_head" ] &&
  [ "$(remote_rev "$dir" main)" = "$red_head" ]; then
  result "ship.sh: resumes after red CI: no second review, then merges" yes ""
else
  result "ship.sh: resumes after red CI: no second review, then merges" no "$(describe)"
fi

# 17. Green CI: review committed, branch pushed, main fast-forwarded and pushed, the report
# and the commit draft deleted (untracked files do not count as a change), on main at the end.
dir="$(new_repo ship-green)"
mkdir -p "$dir/.reports" && printf '# report\n' >"$dir/.reports/feature.md"
printf 'draft\n' >"$dir/.reports/feature.commit.txt"
run_ship "$dir" "$PASS_JSON" success
green_head="$(rev "$dir" feature)"
if [ "$STATUS" -eq 0 ] && grep -q 'SHIPPED: feature' <<<"$ERR" &&
  [ "$(git -C "$dir" log -1 --format=%s feature)" = "Record review of feature: PASS" ] &&
  [ "$(remote_rev "$dir" feature)" = "$green_head" ] && [ "$(rev "$dir" main)" = "$green_head" ] &&
  [ "$(remote_rev "$dir" main)" = "$green_head" ] && [ "$(git -C "$dir" symbolic-ref --short HEAD)" = main ] &&
  [ ! -e "$dir/.reports/feature.md" ] && [ ! -e "$dir/.reports/feature.commit.txt" ] && [ ! -e "$dir/.git/harness-kit-ship" ] &&
  grep -q -- "run watch 4242 --exit-status" "$dir.log/gh-calls"; then
  result "ship.sh: green CI: fast-forwards main, pushes it, deletes the report and the commit draft" yes ""
else
  result "ship.sh: green CI: fast-forwards main, pushes it, deletes the report and the commit draft" no "$(describe)"
fi

# 18. Resume after leaving the branch: the remote refuses main once (a pre-receive hook),
# so the first run stops on main with main merged locally and not pushed. Run again on
# main, it finishes: pushes main, deletes the report and its own state file.
dir="$(new_repo ship-resume)"
cat >"$dir.git/hooks/pre-receive" <<HOOK
#!/bin/sh
if [ -e "$dir.log/reject-main" ] && grep -q ' refs/heads/main\$'; then
  echo "rejected by the test" >&2
  exit 1
fi
exit 0
HOOK
chmod +x "$dir.git/hooks/pre-receive"
touch "$dir.log/reject-main"
mkdir -p "$dir/.reports" && printf '# report\n' >"$dir/.reports/feature.md"
main_before="$(rev "$dir" main)"
run_ship "$dir" "$PASS_JSON" success
first="$(describe)"
first_ok=no
if [ "$STATUS" -eq 1 ] && grep -q 'pushing main failed' <<<"$ERR" &&
  [ "$(git -C "$dir" symbolic-ref --short HEAD)" = main ] && [ "$(rev "$dir" main)" = "$(rev "$dir" feature)" ] &&
  [ "$(remote_rev "$dir" main)" = "$main_before" ] && [ -e "$dir/.git/harness-kit-ship" ]; then
  first_ok=yes
fi
rm -f "$dir.log/reject-main"
run_ship "$dir" "$PASS_JSON" success
if [ "$first_ok" = yes ] && [ "$STATUS" -eq 0 ] && grep -q 'continuing the ship of feature' <<<"$ERR" &&
  [ ! -e "$dir.log/claude-args" ] && [ ! -e "$dir.log/gh-calls" ] &&
  [ "$(remote_rev "$dir" main)" = "$(rev "$dir" feature)" ] &&
  [ ! -e "$dir/.reports/feature.md" ] && [ ! -e "$dir/.git/harness-kit-ship" ]; then
  result "ship.sh: resumes on main after a stop while pushing main" yes ""
else
  result "ship.sh: resumes on main after a stop while pushing main" no "first run: $first_ok
$first
second run: $(describe)"
fi

# 19-20. Which CI runs ship.sh waits for. Two workflows: "lint" is red and listed from the
# first `gh run list`; "validate" is green and listed from the second.
# 19. No .harness/ci-workflow (today's behaviour): the runs listed when the first appears,
# so it stops on lint's red run, never asks gh for a workflow, and never watches validate.
dir="$(new_repo ship-any-workflow)"
printf '5151 lint failure 1\n4242 validate success 2\n' >"$dir.log/runs"
run_ship "$dir" "$PASS_JSON" success
if [ "$STATUS" -eq 1 ] && grep -q 'CI run 5151 finished with conclusion "failure", not success: https://ci.example.invalid/runs/5151' <<<"$ERR" &&
  ! grep -q -- '--workflow' "$dir.log/gh-calls" && ! grep -q 'run watch 4242' "$dir.log/gh-calls" &&
  [ "$(remote_rev "$dir" main)" = "$(rev "$dir" main)" ] && [ "$(rev "$dir" main)" != "$(rev "$dir" feature)" ]; then
  result "ship.sh: without .harness/ci-workflow, waits for every run listed when the first appears" yes ""
else
  result "ship.sh: without .harness/ci-workflow, waits for every run listed when the first appears" no "$(describe)
gh calls: $(cat "$dir.log/gh-calls" 2>/dev/null)"
fi

# 20. .harness/ci-workflow names validate: gh is asked for that workflow only, ship.sh keeps
# waiting until its run appears (lint's red run is never looked at), and merges on green.
dir="$(new_repo ship-one-workflow)"
printf 'validate\n' >"$dir/.harness/ci-workflow"
git -C "$dir" add .harness/ci-workflow && git -C "$dir" commit -q -m "CI: wait for validate"
printf '5151 lint failure 1\n4242 validate success 2\n' >"$dir.log/runs"
SHIP_POLL_SECONDS=1 SHIP_CI_APPEAR_SECONDS=10 run_ship "$dir" "$PASS_JSON" success
if [ "$STATUS" -eq 0 ] && grep -q 'waiting for a run of the workflow "validate" (.harness/ci-workflow) to start' <<<"$ERR" &&
  [ "$(grep -c -- '^run list --commit .* --workflow validate ' "$dir.log/gh-calls")" = 2 ] &&
  grep -q 'run watch 4242' "$dir.log/gh-calls" && ! grep -q '5151' "$dir.log/gh-calls" &&
  [ "$(remote_rev "$dir" main)" = "$(rev "$dir" feature)" ]; then
  result "ship.sh: with .harness/ci-workflow, waits for that workflow's run only, then merges" yes ""
else
  result "ship.sh: with .harness/ci-workflow, waits for that workflow's run only, then merges" no "$(describe)
gh calls: $(cat "$dir.log/gh-calls" 2>/dev/null)"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures ship case(s) failed"
  exit 1
fi
