#!/usr/bin/env bash
# Tests for the person's own steps: report-path.sh, the report, commit draft, commit,
# warning and blast-radius lines of session-start.mjs, check-reports.mjs, land.sh, ship.sh
# (its brief gate, its review commit and its index refresh), approve-brief.sh and
# install-hooks.sh's pre-push and commit-msg hooks.
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
APPROVE_BRIEF="$SCRIPTS/approve-brief.sh"
INSTALL_HOOKS="$SCRIPTS/install-hooks.sh"
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

# The fake claude: records how it was called and its input, then prints $FAKE_JSON.
cat >"$WORK/bin/claude" <<'FAKE'
#!/bin/sh
printf '%s\n' "$@" >"$FAKE_LOG/claude-args"
cat >"$FAKE_LOG/claude-stdin"
cat "$FAKE_JSON"
FAKE

# The fake osascript: appends its arguments to $FAKE_LOG/osascript-calls, one call per line,
# so no case shows a real notification. The fake uname prints $FAKE_UNAME when set (ship.sh
# notifies only on Darwin), and is the real uname otherwise.
cat >"$WORK/bin/osascript" <<'FAKE'
#!/bin/sh
printf '%s ' "$@" >>"$FAKE_LOG/osascript-calls"
echo >>"$FAKE_LOG/osascript-calls"
FAKE
cat >"$WORK/bin/uname" <<'FAKE'
#!/bin/sh
if [ -n "${FAKE_UNAME:-}" ]; then echo "$FAKE_UNAME"; else exec /usr/bin/uname "$@"; fi
FAKE
chmod +x "$WORK/bin/osascript" "$WORK/bin/uname"

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

# sha256_of FILE: FILE's sha256, lowercase hex, computed here without brief-lib.sh.
sha256_of() { node -e 'process.stdout.write(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$1"; }

# brief_for DIR [approved|unapproved]: write the current branch's brief,
# .reports/<branch>.brief.md, unless there is one; approved (the default) also writes its
# approval, .reports/<branch>.brief.approved, holding its sha256, as approve-brief.sh does.
brief_for() {
  local name brief
  name="$(git -C "$1" symbolic-ref --short -q HEAD)" || return 0
  brief="$1/.reports/${name//\//-}.brief.md"
  [ -f "$brief" ] && return 0
  mkdir -p "$1/.reports"
  printf '# Brief: add world\n\n## Goal\nThe app says world too.\n' >"$brief"
  [ "${2:-approved}" = approved ] && sha256_of "$brief" >"${brief%.md}.approved"
  return 0
}

# run_ship DIR JSON CONCLUSION: run ship.sh in DIR, with an approved brief for the current
# branch when it has none (the brief cases run ship.sh themselves); a fresh fake log each
# time (a runs file, if a case wrote one, is kept).
run_ship() {
  rm -f "$1.log/claude-args" "$1.log/claude-stdin" "$1.log/gh-calls" "$1.log/list-calls" "$1.log/osascript-calls"
  printf '%s\n' "$3" >"$1.log/conclusion"
  brief_for "$1"
  FAKE_JSON="$2" run_in "$1" bash "$SHIP"
}

# ship_as_is DIR JSON: run ship.sh in DIR with green CI, leaving the brief as the case made it.
ship_as_is() {
  rm -f "$1.log/claude-args" "$1.log/claude-stdin" "$1.log/gh-calls" "$1.log/list-calls" "$1.log/osascript-calls"
  printf 'success\n' >"$1.log/conclusion"
  FAKE_JSON="$2" run_in "$1" bash "$SHIP"
}

# in_terminal DIR CMD...: run CMD in DIR with a pseudo-terminal as its stdin, stdout and
# stderr (python3's pty module), typing this function's stdin into it; sets OUT (everything
# the terminal showed) and STATUS.
in_terminal() {
  local dir="$1"
  shift
  OUT="$(cd "$dir" && python3 -c '
import os, pty, sys
sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))
' "$@" 2>&1)"
  STATUS=$?
  ERR=""
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
# events DIR: DIR's local event log as "tool branch event what" lines, tab-separated.
events() { cut -f2,3,5,6 "$1/.git/harness-kit/events.tsv" 2>/dev/null; }
# event_detail DIR N: the detail of the Nth line of DIR's event log.
event_detail() { sed -n "${2}p" "$1/.git/harness-kit/events.tsv" 2>/dev/null | cut -f7; }
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
for f in feature gone; do printf '# Brief: %s\n' "$f" >"$dir/.reports/$f.brief.md" && printf 'x\n' >"$dir/.reports/$f.brief.approved"; done
ln -s pinned.md "$dir/.reports/latest.md"
ln -s pinned.commit.txt "$dir/.reports/latest.commit.txt"
git -C "$dir" branch -q -D old
run_session "$dir"
left="$(cd "$dir/.reports" && ls | tr '\n' ' ')"
line2="$(sed -n 2p <<<"$OUT")"
line3="$(sed -n 3p <<<"$OUT")"
line4="$(sed -n 4p <<<"$OUT")"
line5="$(sed -n 5p <<<"$OUT")"
if [ "$STATUS" -eq 0 ] &&
  [ "$left" = "feature.brief.approved feature.brief.md feature.commit.txt feature.md latest.commit.txt latest.md pinned.commit.txt pinned.md team-live.md " ] &&
  [ "$(readlink "$dir/.reports/latest.md")" = feature.md ] &&
  [ "$(sed -n 1p <<<"$OUT")" = "harness-kit $VERSION loaded" ] &&
  grep -qF "write your final report to $dir/.reports/feature.md" <<<"$line2" &&
  grep -qF '"## Summary"' <<<"$line2" && grep -q 'at most 15 lines' <<<"$line2" &&
  grep -q 'Never commit it' <<<"$line2" &&
  [ "$(wc -l <<<"$OUT" | tr -d ' ')" = 5 ] &&
  grep -q 'removed the stale report .reports/gone.md' <<<"$ERR" &&
  grep -q 'removed the stale report .reports/old.md' <<<"$ERR" &&
  grep -q 'removed the stale commit draft .reports/gone.commit.txt' <<<"$ERR" &&
  grep -q 'removed the stale commit draft .reports/old.commit.txt' <<<"$ERR" &&
  grep -q 'removed the stale brief .reports/gone.brief.md' <<<"$ERR" &&
  grep -q 'removed the stale brief approval .reports/gone.brief.approved' <<<"$ERR" &&
  ! grep -q 'feature.brief' <<<"$ERR"; then
  result "session-start: stale reports, commit drafts, briefs and approvals removed; the current, live and latest's kept" yes ""
else
  result "session-start: stale reports, commit drafts, briefs and approvals removed; the current, live and latest's kept" no \
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

# 2d. The blast-radius line: before finishing, update or list everything that describes
# the changed behaviour.
if [ "$line5" = "harness-kit: before finishing, search for every file, comment, test and document that describes behaviour you changed, and update each or list it in the report." ]; then
  result "session-start: tells Claude to update or list every file, comment, test and document describing changed behaviour" yes ""
else
  result "session-start: tells Claude to update or list every file, comment, test and document describing changed behaviour" no "line 5: $line5"
fi

# 2e. The commit line: Claude may commit its own work locally with the draft, never a
# protected file (a patch for land.sh instead) and never a push; the draft line no longer
# says only the person commits.
if grep -qF "harness-kit: you may commit your own work locally with that draft (git commit -F $dir/.reports/feature.commit.txt) once the project's check passes" <<<"$line4" &&
  grep -qF 'the commit-msg hook checks the message' <<<"$line4" &&
  grep -qF 'Never commit a change to a file that .harness/protected-paths lists' <<<"$line4" &&
  grep -qF '"land.sh .reports/<name>.patch"' <<<"$line4" && grep -qF 'Never push' <<<"$line4" &&
  grep -qF 'Never commit the draft file itself.' <<<"$line3" && ! grep -qF 'the person commits with it' <<<"$line3"; then
  result "session-start: Claude may commit its own work with the draft, never protected files, never push" yes ""
else
  result "session-start: Claude may commit its own work with the draft, never protected files, never push" no "line 3: $line3
line 4: $line4"
fi

# 2b. The Summary template: the report line names all five headings, in this order.
headings="$(grep -oE '"(Result|Evidence|Deviations|Decide|Your commands):"' <<<"$line2" | tr '\n' ' ')"
want='"Result:" "Evidence:" "Deviations:" "Decide:" "Your commands:" '
if [ "$headings" = "$want" ] && grep -qF '"Decide:" what the person must decide; "none" if none.' <<<"$line2" &&
  grep -qF "\"Deviations:\" anything done differently from, or beyond, the brief ($dir/.reports/feature.brief.md, the plan skill's brief as the person approved it, when there is one; otherwise what the person asked for)" <<<"$line2"; then
  result "session-start: the Summary template has Result, Evidence, Deviations (against the branch's brief), Decide, Your commands, in that order" yes ""
else
  result "session-start: the Summary template has Result, Evidence, Deviations (against the branch's brief), Decide, Your commands, in that order" no \
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

# 11b. The event log: each stop above, with its reason and message, and the LANDED, one line
# each in .git/harness-kit/events.tsv (never in the working tree: the cases above found
# git status unchanged), with the date and HEAD.
line="$(sed -n 1p "$WORK/land-red/.git/harness-kit/events.tsv" 2>/dev/null)"
if [ "$(events "$WORK/land-bad")" = "$(printf 'land.sh\tfeature\tSTOPPED\tpatch-does-not-apply')" ] &&
  [ "$(events "$WORK/land-red")" = "$(printf 'land.sh\tfeature\tSTOPPED\tcheck-failed')" ] &&
  grep -q '^the check failed (exit 1): sh scripts/check.sh --skip-reviewed\. The patch IS applied' <<<"$(event_detail "$WORK/land-red" 1)" &&
  [ "$(events "$WORK/land-no-flag")" = "$(printf 'land.sh\tfeature\tSTOPPED\tno-skip-reviewed')" ] &&
  [ "$(events "$WORK/land-no-check")" = "$(printf 'land.sh\tfeature\tSTOPPED\tno-check-command')" ] &&
  [ "$(events "$WORK/land-green")" = "$(printf 'land.sh\tfeature\tLANDED\t-')" ] &&
  [ "$(event_detail "$WORK/land-green" 1)" = "$WORK/land-green.patch" ] &&
  grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z	land.sh	feature	$(rev "$WORK/land-red" HEAD)	" <<<"$line"; then
  result "land.sh: each stop, with its reason, and each LANDED is a line in .git/harness-kit/events.tsv" yes ""
else
  result "land.sh: each stop, with its reason, and each LANDED is a line in .git/harness-kit/events.tsv" no \
    "land-bad: $(events "$WORK/land-bad")
land-red: $(cat "$WORK/land-red/.git/harness-kit/events.tsv" 2>/dev/null)
land-no-flag: $(events "$WORK/land-no-flag")
land-no-check: $(events "$WORK/land-no-check")
land-green: $(cat "$WORK/land-green/.git/harness-kit/events.tsv" 2>/dev/null)"
fi

# 11c. A log that cannot be written (.git/harness-kit is a file) changes nothing: land.sh
# still lands, exit 0, with one note.
dir="$(new_land land-no-log 0)"
: >"$dir/.git/harness-kit"
OUT="$(cd "$dir" && bash "$LAND" "$WORK/land-no-log.patch" <<<"yes" 2>&1)"
STATUS=$? ERR=""
if [ "$STATUS" -eq 0 ] && grep -q 'LANDED' <<<"$OUT" &&
  grep -q "^harness-kit land.sh: note: could not append to $dir/.git/harness-kit/events.tsv$" <<<"$OUT"; then
  result "land.sh: an event log that cannot be written changes nothing but a note" yes ""
else
  result "land.sh: an event log that cannot be written changes nothing but a note" no "$(describe)"
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

# 14. A FIX-FIRST review: stops showing the verdict, after committing the review's line
# itself (the file alone, with the standard message naming it), so nobody commits it by
# hand; nothing else committed, nothing pushed or merged.
dir="$(new_repo ship-fix)"
head_before="$(rev "$dir" HEAD)"
run_ship "$dir" "$FIX_JSON" success
if [ "$STATUS" -eq 1 ] && [ -e "$dir.log/claude-args" ] &&
  grep -q "STOPPED: the review's verdict is FIX-FIRST (R1=F), not PASS (the review is above; its line is committed: Record review of feature: FIX-FIRST)" <<<"$ERR" &&
  grep -q '^R1 — FAIL' <<<"$OUT" && [ "$(rev "$dir" HEAD~1)" = "$head_before" ] &&
  [ "$(git -C "$dir" log -1 --format=%s)" = "Record review of feature: FIX-FIRST" ] &&
  git -C "$dir" log -1 --format=%b | grep -q '^.harness/reviews.tsv: the line review.sh appended for this branch.s current diff, verdict FIX-FIRST' &&
  [ "$(git -C "$dir" diff --name-only HEAD~1 HEAD)" = .harness/reviews.tsv ] && [ -z "$(git -C "$dir" status --porcelain --untracked-files=no)" ] &&
  [ ! -e "$dir.log/gh-calls" ] && [ -z "$(remote_rev "$dir" feature)" ] &&
  [ "$(rev "$dir" main)" = "$(remote_rev "$dir" main)" ]; then
  result "ship.sh: a non-PASS review: commits its line with the standard message, stops and shows the verdict" yes ""
else
  result "ship.sh: a non-PASS review: commits its line with the standard message, stops and shows the verdict" no "$(describe)
log: $(git -C "$dir" log --format='%h %s' -3)"
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
green_input="$(cat "$dir.log/claude-stdin" 2>/dev/null)"
if [ "$STATUS" -eq 0 ] && grep -q 'SHIPPED: feature' <<<"$ERR" &&
  [ "$(git -C "$dir" log -1 --format=%s feature)" = "Record review of feature: PASS" ] &&
  [ "$(remote_rev "$dir" feature)" = "$green_head" ] && [ "$(rev "$dir" main)" = "$green_head" ] &&
  [ "$(remote_rev "$dir" main)" = "$green_head" ] && [ "$(git -C "$dir" symbolic-ref --short HEAD)" = main ] &&
  [ ! -e "$dir/.reports/feature.md" ] && [ ! -e "$dir/.reports/feature.commit.txt" ] && [ ! -e "$dir/.git/harness-kit-ship" ] &&
  [ ! -e "$dir/.reports/feature.brief.md" ] && [ ! -e "$dir/.reports/feature.brief.approved" ] &&
  grep -q 'the brief is approved as it is: .reports/feature.brief.md' <<<"$ERR" &&
  grep -qx 'approval: MATCHES: .reports/feature.brief.approved holds this brief.s sha256 ([0-9a-f]*); the person approved the brief as it is below' <<<"$green_input" &&
  grep -q -- "run watch 4242 --exit-status" "$dir.log/gh-calls"; then
  result "ship.sh: green CI: fast-forwards main, pushes it, deletes the report, the commit draft, the brief and its approval" yes ""
else
  result "ship.sh: green CI: fast-forwards main, pushes it, deletes the report, the commit draft, the brief and its approval" no "$(describe)"
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

# 21. The event log: each stop and refusal (with its reason and message) and each SHIPPED,
# on the branch being shipped, also when SHIPPED is written from main (ship-resume).
if [ "$(events "$WORK/ship-main")" = "$(printf 'ship.sh\tmain\tSTOPPED\trefused-on-base')" ] &&
  grep -q '^REFUSED: you are on main; check out the branch to ship$' <<<"$(event_detail "$WORK/ship-main" 1)" &&
  [ "$(events "$WORK/ship-dirty")" = "$(printf 'ship.sh\tfeature\tSTOPPED\trefused-uncommitted')" ] &&
  [ "$(events "$WORK/ship-fix")" = "$(printf 'ship.sh\tfeature\tSTOPPED\treview-not-pass')" ] &&
  grep -q "^the review's verdict is FIX-FIRST (R1=F), not PASS" <<<"$(event_detail "$WORK/ship-fix" 1)" &&
  [ "$(events "$WORK/ship-check-red")" = "$(printf 'ship.sh\tfeature\tSTOPPED\tcheck-failed')" ] &&
  [ "$(events "$WORK/ship-red")" = "$(printf 'ship.sh\tfeature\tSTOPPED\tci-not-green\nship.sh\tfeature\tSHIPPED\tmain')" ] &&
  [ "$(events "$WORK/ship-green")" = "$(printf 'ship.sh\tfeature\tSHIPPED\tmain')" ] &&
  grep -q '^merged [0-9a-f]* into main and pushed it$' <<<"$(event_detail "$WORK/ship-green" 1)" &&
  [ "$(events "$WORK/ship-resume")" = "$(printf 'ship.sh\tfeature\tSTOPPED\tpush-base-failed\nship.sh\tfeature\tSHIPPED\tmain')" ]; then
  result "ship.sh: each stop, with its reason, and each SHIPPED is a line in .git/harness-kit/events.tsv" yes ""
else
  result "ship.sh: each stop, with its reason, and each SHIPPED is a line in .git/harness-kit/events.tsv" no \
    "$(for d in ship-main ship-dirty ship-fix ship-check-red ship-red ship-green ship-resume; do
      printf '%s:\n%s\n' "$d" "$(cat "$WORK/$d/.git/harness-kit/events.tsv" 2>/dev/null)"; done)"
fi

# 24. The check runs once: ship.sh saves its output before the review, and review.sh reuses
# it (the reviewer's input says so, with the same output) instead of running it again.
dir="$(new_repo ship-check-once)"
printf 'echo run >>"$CHECK_RUNS"\necho "check: 1 passed"\n' >"$dir/.harness/check.sh"
git -C "$dir" commit -q -am "feature: count check runs"
CHECK_RUNS="$dir.log/check-runs" run_ship "$dir" "$PASS_JSON" success
input="$(cat "$dir.log/claude-stdin" 2>/dev/null)"
section="$(sed -n '/^=== CHECK COMMAND ===$/,/^=== GIT LOG ===$/p' <<<"$input")"
if [ "$STATUS" -eq 0 ] && [ "$(wc -l <"$dir.log/check-runs" | tr -d ' ')" = 1 ] &&
  grep -q '^check: 1 passed$' <<<"$OUT" && grep -q 'reusing the check output ship.sh saved' <<<"$ERR" &&
  grep -q '^reused: ship.sh ran this command just before starting the review' <<<"$section" &&
  grep -qx 'exit status: 0' <<<"$section" && grep -qx 'check: 1 passed' <<<"$section" &&
  [ -z "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'harness-kit-ship-check.*' -newer "$dir.log/check-runs" -print 2>/dev/null)" ]; then
  result "ship.sh: the check runs once; review.sh reuses ship.sh's saved output and says so" yes ""
else
  result "ship.sh: the check runs once; review.sh reuses ship.sh's saved output and says so" no "$(describe)
check runs: $(cat "$dir.log/check-runs" 2>/dev/null)
CHECK COMMAND section: $section"
fi

# 25. A macOS notification on STOPPED and on SHIPPED (uname says Darwin), none elsewhere.
dir="$(new_repo ship-notify)"
FAKE_UNAME=Darwin run_ship "$dir" "$PASS_JSON" failure
stopped_calls="$(cat "$dir.log/osascript-calls" 2>/dev/null)"
FAKE_UNAME=Darwin run_ship "$dir" "$PASS_JSON" success
shipped_calls="$(cat "$dir.log/osascript-calls" 2>/dev/null)"
dir2="$(new_repo ship-no-notify)"
FAKE_UNAME=Linux run_ship "$dir2" "$PASS_JSON" failure
linux_status="$STATUS"
if [ "$STATUS" -eq 1 ] && [ ! -e "$dir2.log/osascript-calls" ] &&
  [ "$(wc -l <<<"$stopped_calls" | tr -d ' ')" = 1 ] && grep -q 'display notification.* harness-kit ship.sh STOPPED: CI run 4242 finished with conclusion "failure"' <<<"$stopped_calls" &&
  [ "$(wc -l <<<"$shipped_calls" | tr -d ' ')" = 1 ] && grep -q 'harness-kit ship.sh SHIPPED: feature is merged into main and pushed.' <<<"$shipped_calls"; then
  result "ship.sh: a macOS notification on STOPPED and SHIPPED; none when not on macOS" yes ""
else
  result "ship.sh: a macOS notification on STOPPED and SHIPPED; none when not on macOS" no "on STOPPED: $stopped_calls
on SHIPPED: $shipped_calls
not macOS: exit $linux_status, calls: $(cat "$dir2.log/osascript-calls" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------------------
# install-hooks.sh and the pre-push hook
# ---------------------------------------------------------------------------------------

# 22. The hook refuses a push to the review base (main, then develop from
# .harness/review-base), saying "push through ship.sh", and lets through other branches
# and a push with HARNESS_KIT_SHIP=1. Installing again replaces its own hook; a hook it did
# not write, or core.hooksPath, is left alone (exit 1).
dir="$(new_repo hook)"
run_in "$dir" bash "$INSTALL_HOOKS"
installed="$STATUS: $ERR"
run_in "$dir" bash "$INSTALL_HOOKS"
again="$STATUS"
git -C "$dir" checkout -q main
printf 'direct\n' >>"$dir/app.txt" && git -C "$dir" commit -q -am "main: direct"
run_in "$dir" git push -q origin main
refused="$STATUS: $ERR"
remote_main_after_refusal="$(remote_rev "$dir" main)"
run_in "$dir" git push -q origin main:other
other="$STATUS"
HARNESS_KIT_SHIP=1 run_in "$dir" git push -q origin main
shipped="$STATUS"
git -C "$dir" checkout -q -b develop
printf 'develop\n' >"$dir/.harness/review-base"
run_in "$dir" git push -q origin develop
develop="$STATUS: $ERR"
printf '#!/bin/sh\nexit 0\n' >"$dir/.git/hooks/pre-push"
run_in "$dir" bash "$INSTALL_HOOKS"
foreign="$STATUS: $ERR"
rm -f "$dir/.git/hooks/pre-push"
git -C "$dir" config core.hooksPath .githooks
run_in "$dir" bash "$INSTALL_HOOKS"
hooks_path="$STATUS: $ERR"
if grep -q '^0: .*installed .*/.git/hooks/pre-push .* and .*/.git/hooks/commit-msg' <<<"$installed" && [ "$again" -eq 0 ] &&
  grep -q '^1: .*harness-kit pre-push: refusing to push to main: push through ship.sh' <<<"$refused" &&
  [ "$remote_main_after_refusal" != "$(rev "$dir" main)" ] && [ "$other" -eq 0 ] && [ "$shipped" -eq 0 ] &&
  [ "$(remote_rev "$dir" main)" = "$(rev "$dir" main)" ] &&
  grep -q '^1: .*refusing to push to develop: push through ship.sh' <<<"$develop" &&
  grep -q '^1: .*exists and harness-kit did not write it' <<<"$foreign" &&
  grep -q '^1: .*core.hooksPath is set (.githooks)' <<<"$hooks_path" && [ ! -e "$dir/.git/hooks/pre-push" ]; then
  result "install-hooks: the pre-push hook refuses pushes to the review base unless HARNESS_KIT_SHIP=1" yes ""
else
  result "install-hooks: the pre-push hook refuses pushes to the review base unless HARNESS_KIT_SHIP=1" no \
    "install: $installed
again: $again
push main: $refused
push other: $other; with HARNESS_KIT_SHIP=1: $shipped
push develop: $develop
foreign hook: $foreign
core.hooksPath: $hooks_path"
fi

# 23. ship.sh ships through both hooks: it sets HARNESS_KIT_SHIP=1 for its own push of
# main, and its review commit passes the commit-msg hook with .harness/ protected.
dir="$(new_repo ship-hook)"
printf '.harness/\n' >"$dir/.harness/protected-paths"
git -C "$dir" add -A && git -C "$dir" commit -q -m $'Protect .harness/\n\n.harness/protected-paths: protects the harness folder.'
run_in "$dir" bash "$INSTALL_HOOKS"
run_ship "$dir" "$PASS_JSON" success
if [ "$STATUS" -eq 0 ] && grep -q 'SHIPPED: feature' <<<"$ERR" && [ "$(remote_rev "$dir" main)" = "$(rev "$dir" feature)" ] &&
  [ "$(git -C "$dir" log -1 --format=%s feature)" = "Record review of feature: PASS" ]; then
  result "ship.sh: pushes main through the pre-push hook; its review commit passes the commit-msg hook" yes ""
else
  result "ship.sh: pushes main through the pre-push hook; its review commit passes the commit-msg hook" no "$(describe)"
fi

# 26. The commit-msg hook: a message check-commits would fail is refused, with each
# finding's fix and where git saved the message; nothing is committed. The fixed message
# commits; git commit --no-verify commits whatever the message (the person's override). A
# commit-msg hook harness-kit did not write stops install-hooks.sh (exit 1) with neither
# hook installed, and is left as it is.
dir="$(new_repo commit-msg)"
printf 'app.txt\n' >"$dir/.harness/protected-paths"
git -C "$dir" add -A && git -C "$dir" commit -q --no-verify -m "Protect app.txt"
run_in "$dir" bash "$INSTALL_HOOKS"
installed="$STATUS: $ERR"
printf 'hello\nworld\nagain\n' >"$dir/app.txt"
git -C "$dir" add app.txt
head_before="$(rev "$dir" HEAD)"
run_in "$dir" git commit -q -m $'Say it again\n\nIt took 3 tries.'
refused="$STATUS: $ERR"
refused_head="$(rev "$dir" HEAD)"
run_in "$dir" git commit -q -m $'Say it again\n\napp.txt: a third line.\nTold: 3 tries, counted by hand.'
fixed="$STATUS: $ERR"
printf 'hello\n' >"$dir/app.txt"
run_in "$dir" git commit -q -a --no-verify -m $'Back\n\nNo reason, 5 times.'
override="$STATUS"
dir2="$(new_repo commit-msg-foreign)"
printf '#!/bin/sh\nexit 0\n' >"$dir2/.git/hooks/commit-msg"
run_in "$dir2" bash "$INSTALL_HOOKS"
foreign="$STATUS: $ERR"
if grep -q '^0: ' <<<"$installed" && [ -x "$dir/.git/hooks/commit-msg" ] && [ -f "$dir/.git/hooks/harness-kit-check-commits.mjs" ] &&
  grep -q '^1: ' <<<"$refused" && grep -qF '(a) app.txt is protected (.harness/protected-paths) and changed in this commit' <<<"$refused" &&
  grep -qF '(b) this message: the number 3 is in the body' <<<"$refused" &&
  grep -qF 'harness-kit commit-msg: commit REFUSED (above). Git saved your message in .git/COMMIT_EDITMSG' <<<"$refused" &&
  grep -qF 'git commit --no-verify, your deliberate override' <<<"$refused" && [ "$refused_head" = "$head_before" ] &&
  grep -q '^0: ' <<<"$fixed" && [ "$(git -C "$dir" log -2 --format=%s | tr '\n' '|')" = "Back|Say it again|" ] && [ "$override" -eq 0 ] &&
  grep -q '^1: .*commit-msg exists and harness-kit did not write it' <<<"$foreign" &&
  [ "$(sed -n 2p "$dir2/.git/hooks/commit-msg")" = "exit 0" ] && [ ! -e "$dir2/.git/hooks/pre-push" ]; then
  result "install-hooks: the commit-msg hook refuses a message check-commits would fail, with the fix; --no-verify commits" yes ""
else
  result "install-hooks: the commit-msg hook refuses a message check-commits would fail, with the fix; --no-verify commits" no \
    "install: $installed
refused: $refused
fixed: $fixed
override: $override
log: $(git -C "$dir" log --format=%s -3)
foreign: $foreign"
fi

# 27-28. The index (.harness/index-command, here a script that writes docs/index.md from
# the branch's Decision: lines, protected). 27: stale, it is regenerated and committed
# alone before the check and the review (so the reviewer's diff holds it), with a body
# naming it that the commit-msg hook passes; then the ship goes on. A second ship of the
# reviewed branch does not run it.
new_index_repo() {
  local dir
  dir="$(new_repo "$1")"
  mkdir -p "$dir/docs"
  cat >"$dir/.harness/index.sh" <<'INDEX'
git log --format=%b | grep '^Decision:' >docs/index.md
echo run >>"$INDEX_RUNS"
INDEX
  printf 'sh .harness/index.sh\n' >"$dir/.harness/index-command"
  printf 'docs/\n' >"$dir/.harness/protected-paths"
  git -C "$dir" add -A && git -C "$dir" commit -q -m $'Index\n\nDecision: the index lives in docs.'
  (cd "$dir" && INDEX_RUNS=/dev/null sh .harness/index.sh) && git -C "$dir" add -A &&
    git -C "$dir" commit -q -m $'Index\n\ndocs/index.md: first build.'
  git -C "$dir" commit -q --allow-empty -m $'Decide\n\nDecision: ship.sh keeps the index fresh.'
  (cd "$dir" && bash "$INSTALL_HOOKS" 2>/dev/null)
  echo "$dir"
}
dir="$(new_index_repo ship-index)"
INDEX_RUNS="$dir.log/index-runs" run_ship "$dir" "$PASS_JSON" success
first="$(describe)"
input="$(cat "$dir.log/claude-stdin" 2>/dev/null)"
subjects="$(git -C "$dir" log --format=%s -3 feature | tr '\n' '|')"
index_commit="$(git -C "$dir" log --format=%H --grep '^Refresh the index' -1 feature)"
INDEX_RUNS="$dir.log/index-runs" run_ship "$dir" "$PASS_JSON" success
if grep -q '^exit 0' <<<"$first" && [ "$subjects" = "Record review of feature: PASS|Refresh the index (.harness/index-command)|Decide|" ] &&
  [ "$(git -C "$dir" diff --name-only "$index_commit~1" "$index_commit")" = docs/index.md ] &&
  git -C "$dir" log -1 --format=%b "$index_commit" | grep -q '^docs/index.md: regenerated by the first line of .harness/index-command' &&
  grep -q 'ship.sh keeps the index fresh' "$dir/docs/index.md" && grep -q 'ship.sh keeps the index fresh' <<<"$input" &&
  grep -q 'committed the refreshed index: docs/index.md' <<<"$first" &&
  [ "$(wc -l <"$dir.log/index-runs" | tr -d ' ')" = 1 ] && [ "$(remote_rev "$dir" main)" = "$(rev "$dir" feature)" ]; then
  result "ship.sh: a stale index is regenerated and committed before the review, through the commit-msg hook" yes ""
else
  result "ship.sh: a stale index is regenerated and committed before the review, through the commit-msg hook" no "first ship: $first
subjects: $subjects
index runs: $(cat "$dir.log/index-runs" 2>/dev/null)
second ship: $(describe)"
fi

# 28. An index already up to date: the command runs, nothing is committed for it. A failing
# index command stops before the check and the review, with nothing committed.
dir="$(new_index_repo ship-index-fresh)"
(cd "$dir" && INDEX_RUNS=/dev/null sh .harness/index.sh) && git -C "$dir" add -A &&
  git -C "$dir" commit -q -m $'Index\n\ndocs/index.md: up to date.'
INDEX_RUNS="$dir.log/index-runs" run_ship "$dir" "$PASS_JSON" success
fresh="$(describe)"
fresh_subjects="$(git -C "$dir" log --format=%s -2 feature | tr '\n' '|')"
dir2="$(new_index_repo ship-index-red)"
printf 'exit 3\n' >"$dir2/.harness/index.sh"
git -C "$dir2" commit -q --no-verify -am "break the index"
head_before="$(rev "$dir2" HEAD)"
INDEX_RUNS=/dev/null run_ship "$dir2" "$PASS_JSON" success
if grep -q '^exit 0' <<<"$fresh" && grep -q 'the index is up to date: sh .harness/index.sh changed nothing' <<<"$fresh" &&
  [ "$fresh_subjects" = "Record review of feature: PASS|Index|" ] &&
  [ "$STATUS" -eq 1 ] && grep -q 'STOPPED: the index command failed (exit 3, above): sh .harness/index.sh. Nothing was committed and no review was started.' <<<"$ERR" &&
  [ "$(rev "$dir2" HEAD)" = "$head_before" ] && [ ! -e "$dir2.log/claude-args" ] && ! grep -q 'check: 1 passed' <<<"$OUT"; then
  result "ship.sh: an up-to-date index commits nothing; a failing index command stops before the review" yes ""
else
  result "ship.sh: an up-to-date index commits nothing; a failing index command stops before the review" no "fresh: $fresh
fresh subjects: $fresh_subjects
failing: $(describe)"
fi


# ---------------------------------------------------------------------------------------
# The brief: ship.sh's gate and approve-brief.sh
# ---------------------------------------------------------------------------------------

# 29. ship.sh stops before the review (before the index, the check and claude) when the
# branch has no brief, when its brief has no approval, and when the brief changed after it
# was approved; each stop prints the exact fix, with approve-brief.sh's full path. A
# brief-optional that is committed but not protected is not honoured, and the stop says so.
# Nothing is committed, pushed or asked of gh.
dir="$(new_repo ship-no-brief)"
head_before="$(rev "$dir" HEAD)"
ship_as_is "$dir" "$PASS_JSON"
none="$(describe)"
none_ok=no
if [ "$STATUS" -eq 1 ] &&
  grep -qF "STOPPED: there is no brief for feature (.reports/feature.brief.md), so no review was started. Fix: in Claude, run /plan <goal> to write it; read it, then approve it in your terminal: $SCRIPTS/approve-brief.sh; then re-run ship.sh." <<<"$ERR" &&
  ! grep -q 'check: 1 passed' <<<"$OUT" && [ ! -e "$dir.log/claude-args" ] && [ ! -e "$dir.log/gh-calls" ] &&
  [ "$(rev "$dir" HEAD)" = "$head_before" ] && [ -z "$(remote_rev "$dir" feature)" ]; then
  none_ok=yes
fi
brief_for "$dir" unapproved
ship_as_is "$dir" "$PASS_JSON"
unapproved="$(describe)"
unapproved_ok=no
if [ "$STATUS" -eq 1 ] &&
  grep -qF "STOPPED: the brief .reports/feature.brief.md has no approval (.reports/feature.brief.approved), so no review was started. Fix: read it, then approve it in your terminal: $SCRIPTS/approve-brief.sh; then re-run ship.sh." <<<"$ERR" &&
  [ ! -e "$dir.log/claude-args" ] && [ ! -e "$dir.log/gh-calls" ]; then
  unapproved_ok=yes
fi
sha256_of "$dir/.reports/feature.brief.md" >"$dir/.reports/feature.brief.approved"
approved_sha="$(cat "$dir/.reports/feature.brief.approved")"
printf 'Out of scope: nothing else.\n' >>"$dir/.reports/feature.brief.md"
changed_sha="$(sha256_of "$dir/.reports/feature.brief.md")"
ship_as_is "$dir" "$PASS_JSON"
changed="$(describe)"
changed_ok=no
if [ "$STATUS" -eq 1 ] &&
  grep -qF "STOPPED: the brief .reports/feature.brief.md changed after it was approved (its sha256 is $changed_sha; .reports/feature.brief.approved holds $approved_sha), so no review was started. Fix: read it again, then approve it in your terminal: $SCRIPTS/approve-brief.sh; then re-run ship.sh." <<<"$ERR" &&
  [ ! -e "$dir.log/claude-args" ] && [ ! -e "$dir.log/gh-calls" ] && [ "$(rev "$dir" HEAD)" = "$head_before" ]; then
  changed_ok=yes
fi
dir2="$(new_repo ship-brief-unprotected)"
printf 'This project does not use briefs.\n' >"$dir2/.harness/brief-optional"
git -C "$dir2" add -A && git -C "$dir2" commit -q -m "briefs optional, unprotected"
ship_as_is "$dir2" "$PASS_JSON"
unprotected="$(describe)"
if [ "$none_ok$unapproved_ok$changed_ok" = yesyesyes ] && [ "$STATUS" -eq 1 ] &&
  grep -qF 'STOPPED: there is no brief for feature' <<<"$ERR" &&
  grep -qF '(Note: .harness/brief-optional is committed but .harness/protected-paths does not list it, so it is not honoured' <<<"$ERR" &&
  [ ! -e "$dir2.log/claude-args" ] &&
  [ "$(events "$dir")" = "$(printf 'ship.sh\tfeature\tSTOPPED\tno-brief\nship.sh\tfeature\tSTOPPED\tbrief-not-approved\nship.sh\tfeature\tSTOPPED\tbrief-changed')" ]; then
  result "ship.sh: no brief, or an approval that does not match, stops before the review with the exact fix" yes ""
else
  result "ship.sh: no brief, or an approval that does not match, stops before the review with the exact fix" no "no brief ($none_ok): $none
unapproved ($unapproved_ok): $unapproved
changed ($changed_ok): $changed
brief-optional not protected: $unprotected
events: $(events "$dir")"
fi

# 30. The opt-out is the person's, per project: a committed .harness/brief-optional that
# .harness/protected-paths lists lets a branch with no brief go on to the review and ship,
# and the reviewer's input says so. A brief that is there must still match its approval.
dir="$(new_repo ship-brief-optional)"
printf 'This project does not use briefs.\n' >"$dir/.harness/brief-optional"
printf '.harness/\n' >"$dir/.harness/protected-paths"
git -C "$dir" add -A && git -C "$dir" commit -q -m "briefs optional, protected"
ship_as_is "$dir" "$PASS_JSON"
optional="$(describe)"
optional_input="$(cat "$dir.log/claude-stdin" 2>/dev/null)"
optional_ok=no
if [ "$STATUS" -eq 0 ] && grep -q 'SHIPPED: feature' <<<"$ERR" &&
  grep -qF 'no brief (.reports/feature.brief.md); this project makes briefs optional (.harness/brief-optional, protected)' <<<"$ERR" &&
  grep -qx 'none: this branch has no brief (.reports/feature.brief.md); the project makes briefs optional (.harness/brief-optional, protected)' <<<"$optional_input"; then
  optional_ok=yes
fi
dir2="$(new_repo ship-brief-optional-changed)"
printf 'This project does not use briefs.\n' >"$dir2/.harness/brief-optional"
printf '.harness/brief-optional\n' >"$dir2/.harness/protected-paths"
git -C "$dir2" add -A && git -C "$dir2" commit -q -m "briefs optional, protected"
brief_for "$dir2"
printf 'changed\n' >>"$dir2/.reports/feature.brief.md"
ship_as_is "$dir2" "$PASS_JSON"
if [ "$optional_ok" = yes ] && [ "$STATUS" -eq 1 ] && grep -qF 'STOPPED: the brief .reports/feature.brief.md changed after it was approved' <<<"$ERR" &&
  [ ! -e "$dir2.log/claude-args" ]; then
  result "ship.sh: a committed, protected .harness/brief-optional lets a branch with no brief ship; a brief that is there must match" yes ""
else
  result "ship.sh: a committed, protected .harness/brief-optional lets a branch with no brief ship; a brief that is there must match" no "optional ($optional_ok): $optional
brief there, changed: $(describe)"
fi

# 31. approve-brief.sh refuses without a terminal (stdin a pipe, even one saying y) and
# writes nothing; with no brief it says to run /plan; on a detached HEAD it refuses.
dir="$(new_repo approve-refused)"
OUT="$(cd "$dir" && bash "$APPROVE_BRIEF" <<<"y" 2>&1)"
STATUS=$? ERR=""
no_brief="$(describe)"
no_brief_ok=no
[ "$STATUS" -eq 1 ] && grep -qF 'there is no brief for feature (.reports/feature.brief.md). In Claude, run /plan <goal> to write it' <<<"$OUT" && no_brief_ok=yes
brief_for "$dir" unapproved
OUT="$(cd "$dir" && printf 'y\n' | bash "$APPROVE_BRIEF" 2>&1)"
STATUS=$? ERR=""
piped="$(describe)"
piped_status="$STATUS"
OUT="$(cd "$dir" && bash "$APPROVE_BRIEF" </dev/null 2>&1)"
STATUS=$? ERR=""
if [ "$no_brief_ok" = yes ] && [ "$piped_status" -eq 2 ] && [ "$STATUS" -eq 2 ] &&
  grep -qF 'REFUSED: stdin is not a terminal, so the answer could not come from you reading the brief.' <<<"$piped" &&
  grep -qF "Run it yourself, in your own terminal: $SCRIPTS/approve-brief.sh. Nothing was written." <<<"$piped" &&
  ! grep -q 'Approve this brief' <<<"$piped" && [ ! -e "$dir/.reports/feature.brief.approved" ]; then
  result "approve-brief.sh: refuses without a terminal and writes nothing; with no brief it says to run /plan" yes ""
else
  result "approve-brief.sh: refuses without a terminal and writes nothing; with no brief it says to run /plan" no "no brief ($no_brief_ok): $no_brief
piped y: $piped
/dev/null: $(describe)
approval: $(cat "$dir/.reports/feature.brief.approved" 2>/dev/null)"
fi

# 32. In a terminal: approve-brief.sh shows the brief and asks; "n" (or just Enter) writes
# nothing; "y" writes .reports/<branch>.brief.approved holding the brief's sha256, which
# ship.sh then accepts. A later "n" leaves that approval as it was.
dir="$(new_repo approve-terminal)"
git -C "$dir" checkout -q -b team/login
brief_for "$dir" unapproved
brief_sha="$(sha256_of "$dir/.reports/team-login.brief.md")"
in_terminal "$dir" bash "$APPROVE_BRIEF" <<<"n"
declined="$(describe)"
declined_status="$STATUS"
declined_file="$(cat "$dir/.reports/team-login.brief.approved" 2>/dev/null)"
in_terminal "$dir" bash "$APPROVE_BRIEF" <<<""
enter_status="$STATUS"
in_terminal "$dir" bash "$APPROVE_BRIEF" <<<"y"
approved="$(describe)"
approved_status="$STATUS"
recorded="$(cat "$dir/.reports/team-login.brief.approved" 2>/dev/null)"
recorded_lines="$(wc -l <"$dir/.reports/team-login.brief.approved" | tr -d ' ')"
in_terminal "$dir" bash "$APPROVE_BRIEF" <<<"no"
after_no="$(cat "$dir/.reports/team-login.brief.approved" 2>/dev/null)"
ship_as_is "$dir" "$PASS_JSON"
if [ "$declined_status" -eq 1 ] && grep -qF 'Approve this brief? [y/N]' <<<"$declined" &&
  grep -qF "=== .reports/team-login.brief.md (sha256 $brief_sha) ===" <<<"$declined" && grep -qF '## Goal' <<<"$declined" &&
  grep -qF 'not approved (answer "n"). Nothing was written.' <<<"$declined" && [ -z "$declined_file" ] && [ "$enter_status" -eq 1 ] &&
  [ "$approved_status" -eq 0 ] && grep -qF "APPROVED: .reports/team-login.brief.approved holds the brief's sha256 ($brief_sha)" <<<"$approved" &&
  [ "$recorded" = "$brief_sha" ] && [ "$recorded_lines" = 1 ] &&
  [ "$after_no" = "$brief_sha" ] &&
  [ "$STATUS" -eq 0 ] && grep -q 'the brief is approved as it is: .reports/team-login.brief.md' <<<"$ERR"; then
  result "approve-brief.sh: in a terminal, y writes the brief's sha256 (ship.sh accepts it); anything else writes nothing" yes ""
else
  result "approve-brief.sh: in a terminal, y writes the brief's sha256 (ship.sh accepts it); anything else writes nothing" no "n: $declined
file after n: $declined_file
Enter: exit $enter_status
y: $approved
recorded: $recorded (brief $brief_sha)
after a later no: $after_no
ship: exit $STATUS
$ERR"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures ship case(s) failed"
  exit 1
fi
