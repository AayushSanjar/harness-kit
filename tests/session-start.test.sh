#!/usr/bin/env bash
# Tests for the SessionStart hook's start-up picture (start-picture.mjs, through
# session-start.mjs). Every case runs the hook in a temporary git repository whose sources
# are fakes written by hand: the local event log (.git/harness-kit/events.tsv), the brief and
# its approval (.reports/), .harness/reviews.tsv, the state file, and the working tree's
# changes. Prints one PASS or FAIL line per case and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_START="$ROOT/plugins/harness-kit/scripts/session-start.mjs"
# The real path: git prints resolved paths, and macOS's temp folder is behind a symlink.
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
failures=0

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset HARNESS_KIT_EVAL CLAUDE_PROJECT_DIR

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

describe() { printf 'exit %s\nstdout:\n%s\nstderr: %s' "$STATUS" "$OUT" "$ERR"; }

# new_repo NAME: a repository on the branch feat-x with one commit (app.txt, and a
# .gitignore for .reports/, as a project using harness-kit has). Prints its path.
new_repo() {
  local dir="$WORK/$1"
  git init -q -b feat-x "$dir"
  printf 'hello\n' >"$dir/app.txt"
  printf '.reports/\n' >"$dir/.gitignore"
  git -C "$dir" add -A && git -C "$dir" commit -q -m "initial"
  echo "$dir"
}

# run_session DIR [AGENT_TYPE]: run the SessionStart hook for a session in DIR; sets OUT,
# ERR, STATUS and PIC (the picture's lines, without their "harness-kit start-up: " prefix).
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
  PIC="$(grep '^harness-kit start-up: ' <<<"$OUT" | sed 's/^harness-kit start-up: //')"
}

# line N: the picture's Nth line (1 brief, 2 check, 3 replay, 4 review, 5 uncommitted, 6
# state).
line() { sed -n "${1}p" <<<"$PIC"; }

# event DIR DATE TOOL BRANCH HEAD EVENT WHAT DETAIL: append one line to DIR's event log.
event() {
  mkdir -p "$1/.git/harness-kit"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$5" "$6" "$7" "$8" >>"$1/.git/harness-kit/events.tsv"
}

# review DIR DATE BRANCH HEAD VERDICT ITEMS: append one line to DIR's .harness/reviews.tsv.
review() {
  mkdir -p "$1/.harness"
  printf '%s\t%s\tbase\t%s\thash\t%s\t%s\t0.10\t30.0\n' "$2" "$3" "$4" "$5" "$6" >>"$1/.harness/reviews.tsv"
}

sha256_of() { node -e 'process.stdout.write(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$1"; }

# ---------------------------------------------------------------------------------------
# 1. The brief line: none, not approved, approved (with the goal), changed since it was
# approved, and a brief with no title line.
# ---------------------------------------------------------------------------------------
dir="$(new_repo brief)"
brief="$dir/.reports/feat-x.brief.md"
log=""
run_session "$dir"
missing="$(line 1)"
mkdir -p "$dir/.reports" && printf '# Brief: say hello to the world\n\n## Goal\nIt says hello.\n' >"$brief"
run_session "$dir"
unapproved="$(line 1)"
sha256_of "$brief" >"${brief%.md}.approved"
run_session "$dir"
approved="$(line 1)"
printf 'One more word.\n' >>"$brief"
run_session "$dir"
changed="$(line 1)"
printf '## Goal\nNo title.\n' >"$brief"
sha256_of "$brief" >"${brief%.md}.approved"
run_session "$dir"
untitled="$(line 1)"
if [ "$missing" = "branch feat-x; brief: none (there is no .reports/feat-x.brief.md)" ] &&
  [ "$unapproved" = "branch feat-x; brief: not approved (.reports/feat-x.brief.md); goal: say hello to the world" ] &&
  [ "$approved" = "branch feat-x; brief: approved (.reports/feat-x.brief.md); goal: say hello to the world" ] &&
  [ "$changed" = "branch feat-x; brief: changed since it was approved (.reports/feat-x.brief.md); goal: say hello to the world" ] &&
  [ "$untitled" = 'branch feat-x; brief: approved (.reports/feat-x.brief.md); goal: none (the brief has no "# Brief:" title line)' ]; then
  result "start-up picture: the brief line says approved with the goal, not approved, changed since it was approved, or none" yes ""
else
  result "start-up picture: the brief line says approved with the goal, not approved, changed since it was approved, or none" no \
    "missing: $missing
unapproved: $unapproved
approved: $approved
changed: $changed
untitled: $untitled"
fi

# ---------------------------------------------------------------------------------------
# 2. The last check: this branch's latest CHECKED line, not an older one, not another
# branch's, not a later line of another kind; PASS, FAIL with its names, FAIL without
# names; and none with no log or no CHECKED line for the branch.
# ---------------------------------------------------------------------------------------
dir="$(new_repo check)"
head="$(git -C "$dir" rev-parse HEAD)"
run_session "$dir"
no_log="$(line 2)"
event "$dir" 2026-09-01T09:00:00Z land.sh other "$head" CHECKED FAIL "exit 1: other"
run_session "$dir"
no_line="$(line 2)"
event "$dir" 2026-09-02T09:00:00Z land.sh feat-x "$head" CHECKED PASS -
event "$dir" 2026-09-03T10:00:00Z stop-gate.mjs feat-x "$head" CHECKED FAIL "exit 1: unit tests: 2 failed; lint"
event "$dir" 2026-09-04T09:00:00Z ship.sh other "$head" CHECKED PASS -
event "$dir" 2026-09-04T10:00:00Z land.sh feat-x "$head" STOPPED check-failed "the check failed (exit 1)"
run_session "$dir"
fail="$(line 2)"
event "$dir" 2026-09-05T09:00:00Z land.sh feat-x 0123456789abcdef0123456789abcdef01234567 CHECKED PASS -
run_session "$dir"
pass="$(line 2)"
event "$dir" 2026-09-06T09:00:00Z release.sh feat-x "$head" CHECKED FAIL "signal SIGKILL: no FAIL lines"
run_session "$dir"
unnamed="$(line 2)"
if [ "$no_log" = "last check: none (there is no local event log, .git/harness-kit/events.tsv)" ] &&
  [ "$no_line" = "last check: none (.git/harness-kit/events.tsv has no check result for feat-x)" ] &&
  [ "$fail" = "last check: FAIL (exit 1, 2 failing checks) since 2026-09-03T10:00:00Z, recorded by the Stop hook at ${head:0:12} (the current HEAD); failing: unit tests: 2 failed; lint" ] &&
  [ "$pass" = "last check: PASS since 2026-09-05T09:00:00Z, recorded by land.sh at 0123456789ab (not the current HEAD)" ] &&
  [ "$unnamed" = "last check: FAIL (signal SIGKILL) since 2026-09-06T09:00:00Z, recorded by release.sh at ${head:0:12} (the current HEAD); failing: not named (the check printed no FAIL lines)" ]; then
  result "start-up picture: the last check is this branch's latest CHECKED line, with its failing checks, or none" yes ""
else
  result "start-up picture: the last check is this branch's latest CHECKED line, with its failing checks, or none" no \
    "no log: $no_log
no line: $no_line
fail: $fail
pass: $pass
unnamed: $unnamed"
fi

# ---------------------------------------------------------------------------------------
# 3. At most 5 failing checks are named: 8 give the first 5 and "and 3 more"; 5 give all 5.
# ---------------------------------------------------------------------------------------
dir="$(new_repo names)"
head="$(git -C "$dir" rev-parse HEAD)"
event "$dir" 2026-09-03T10:00:00Z ship.sh feat-x "$head" CHECKED FAIL "exit 1: c1; c2; c3; c4; c5; c6; c7; c8"
run_session "$dir"
eight="$(line 2)"
event "$dir" 2026-09-04T10:00:00Z ship.sh feat-x "$head" CHECKED FAIL "exit 1: c1; c2; c3; c4; c5"
run_session "$dir"
five="$(line 2)"
if [ "$eight" = "last check: FAIL (exit 1, 8 failing checks) since 2026-09-03T10:00:00Z, recorded by ship.sh at ${head:0:12} (the current HEAD); failing: c1; c2; c3; c4; c5 and 3 more" ] &&
  [ "$five" = "last check: FAIL (exit 1, 5 failing checks) since 2026-09-04T10:00:00Z, recorded by ship.sh at ${head:0:12} (the current HEAD); failing: c1; c2; c3; c4; c5" ]; then
  result "start-up picture: at most 5 failing checks are named, then and N more" yes ""
else
  result "start-up picture: at most 5 failing checks are named, then and N more" no "eight: $eight
five: $five"
fi

# ---------------------------------------------------------------------------------------
# 4. The last review: this branch's latest line in .harness/reviews.tsv, not an older one or
# another branch's; none with no file or no line for the branch.
# ---------------------------------------------------------------------------------------
dir="$(new_repo review)"
head="$(git -C "$dir" rev-parse HEAD)"
run_session "$dir"
no_file="$(line 4)"
review "$dir" 2026-09-01T09:00:00Z other "$head" PASS R1=P
run_session "$dir"
no_line="$(line 4)"
review "$dir" 2026-09-02T09:00:00Z feat-x 0123456789abcdef0123456789abcdef01234567 PASS "R1=P,R2=P"
review "$dir" 2026-09-03T09:00:00Z feat-x "$head" FIX-FIRST "R1=F,R2=P"
review "$dir" 2026-09-04T09:00:00Z other "$head" STOP "R1=F,R2=F"
printf 'not a review line\n' >>"$dir/.harness/reviews.tsv"
run_session "$dir"
latest="$(line 4)"
if [ "$no_file" = "last review: none (there is no .harness/reviews.tsv)" ] &&
  [ "$no_line" = "last review: none (.harness/reviews.tsv has no line for feat-x)" ] &&
  [ "$latest" = "last review: FIX-FIRST (R1=F,R2=P) on 2026-09-03T09:00:00Z, for head ${head:0:12} (the current HEAD)" ]; then
  result "start-up picture: the last review is this branch's latest line in .harness/reviews.tsv, or none" yes ""
else
  result "start-up picture: the last review is this branch's latest line in .harness/reviews.tsv, or none" no \
    "no file: $no_file
no line: $no_line
latest: $latest"
fi

# ---------------------------------------------------------------------------------------
# 5. Uncommitted changes: none on a clean tree; then one of each kind, untracked files
# counted one by one, in one line.
# ---------------------------------------------------------------------------------------
dir="$(new_repo changes)"
printf 'b\n' >"$dir/b.txt" && printf 'c\n' >"$dir/c.txt"
git -C "$dir" add -A && git -C "$dir" commit -q -m "b and c"
run_session "$dir"
clean="$(line 5)"
printf 'hello again\n' >"$dir/app.txt"
git -C "$dir" rm -q b.txt
git -C "$dir" mv c.txt d.txt
printf 'e\n' >"$dir/e.txt" && git -C "$dir" add e.txt
mkdir -p "$dir/u" && printf 'f\n' >"$dir/f.txt" && printf '1\n' >"$dir/u/1" && printf '2\n' >"$dir/u/2"
run_session "$dir"
dirty="$(line 5)"
if [ "$clean" = "uncommitted: none" ] &&
  [ "$dirty" = "uncommitted: 7 paths (1 modified, 1 added, 1 deleted, 1 renamed, 3 untracked)" ] &&
  [ "$(grep -c '^uncommitted:' <<<"$PIC")" = 1 ]; then
  result "start-up picture: uncommitted changes are counted by kind in one line, or none" yes ""
else
  result "start-up picture: uncommitted changes are counted by kind in one line, or none" no "clean: $clean
dirty: $dirty
picture:
$PIC"
fi

# ---------------------------------------------------------------------------------------
# 6. The state file: docs/STATE.md's first 10 of 25 lines; the file .harness/state-file
# names instead; none when it is missing, empty, or outside the project.
# ---------------------------------------------------------------------------------------
dir="$(new_repo state)"
run_session "$dir"
default_missing="$(sed -n '6,$p' <<<"$PIC")"
mkdir -p "$dir/docs" && : >"$dir/docs/STATE.md"
run_session "$dir"
empty="$(sed -n '6,$p' <<<"$PIC")"
for i in $(seq 1 25); do printf 'state line %s\n' "$i"; done >"$dir/docs/STATE.md"
run_session "$dir"
default_long="$(sed -n '6,$p' <<<"$PIC")"
want_long="state: docs/STATE.md, its first 10 of 25 lines:
$(for i in $(seq 1 10); do printf '> state line %s\n' "$i"; done)"
mkdir -p "$dir/.harness" "$dir/notes" && printf 'notes/NOW.md\n' >"$dir/.harness/state-file"
printf 'now 1\n\nnow 3\n' >"$dir/notes/NOW.md"
run_session "$dir"
configured="$(sed -n '6,$p' <<<"$PIC")"
printf 'notes/GONE.md\n' >"$dir/.harness/state-file"
run_session "$dir"
configured_missing="$(sed -n '6,$p' <<<"$PIC")"
printf '../outside.md\n' >"$dir/.harness/state-file"
printf 'secret\n' >"$WORK/outside.md"
run_session "$dir"
outside="$(sed -n '6,$p' <<<"$PIC")"
if [ "$default_missing" = "state: none (docs/STATE.md does not exist)" ] &&
  [ "$empty" = "state: none (docs/STATE.md is empty)" ] &&
  [ "$default_long" = "$want_long" ] &&
  [ "$configured" = "$(printf 'state: notes/NOW.md (named by .harness/state-file), its 3 lines:\n> now 1\n>\n> now 3')" ] &&
  [ "$configured_missing" = "state: none (notes/GONE.md does not exist; .harness/state-file names it)" ] &&
  [ "$outside" = "state: none (.harness/state-file names ../outside.md, which is outside the project)" ]; then
  result "start-up picture: the state file's first 10 lines, from .harness/state-file or docs/STATE.md, or none" yes ""
else
  result "start-up picture: the state file's first 10 lines, from .harness/state-file or docs/STATE.md, or none" no \
    "default missing: $default_missing
empty: $empty
default long:
$default_long
configured:
$configured
configured missing: $configured_missing
outside: $outside"
fi

# ---------------------------------------------------------------------------------------
# 7. The limits, whatever the sources hold: never more than 16 picture lines, none longer
# than 200 characters (the prefix included), and a line that was cut ends in "…".
# ---------------------------------------------------------------------------------------
dir="$(new_repo limits)"
head="$(git -C "$dir" rev-parse HEAD)"
long="$(printf 'x%.0s' $(seq 1 300))"
mkdir -p "$dir/.reports" "$dir/docs"
printf '# Brief: %s\n' "$long" >"$dir/.reports/feat-x.brief.md"
names="$(for i in $(seq 1 30); do printf 'a check whose name is long number %s; ' "$i"; done)"
event "$dir" 2026-09-03T10:00:00Z stop-gate.mjs feat-x "$head" CHECKED FAIL "exit 1: ${names%; }"
review "$dir" 2026-09-03T09:00:00Z feat-x "$head" PASS "$long"
for i in $(seq 1 40); do printf 'state %s é %s\n' "$i" "$long"; done >"$dir/docs/STATE.md"
run_session "$dir"
lengths="$(node -e '
  const lines = require("fs").readFileSync(0, "utf8").split("\n").filter((l) => l.startsWith("harness-kit start-up: "));
  console.log(lines.length);
  console.log(Math.max(...lines.map((l) => Array.from(l).length)));
  console.log(lines.filter((l) => Array.from(l).length === 200 && !l.endsWith("…")).length);
' <<<"$OUT")"
count="$(sed -n 1p <<<"$lengths")"
longest="$(sed -n 2p <<<"$lengths")"
uncut="$(sed -n 3p <<<"$lengths")"
if [ "$STATUS" -eq 0 ] && [ "$count" = 16 ] && [ "$longest" = 200 ] && [ "$uncut" = 0 ] &&
  grep -q '^harness-kit start-up: state: docs/STATE.md, its first 10 of 40 lines:$' <<<"$OUT" &&
  grep -q '^harness-kit start-up: > state 1 é xxx.*…$' <<<"$OUT"; then
  result "start-up picture: never more than 16 lines, none longer than 200 characters, a cut line ending in …" yes ""
else
  result "start-up picture: never more than 16 lines, none longer than 200 characters, a cut line ending in …" no \
    "lines: $count; longest: $longest; at 200 without …: $uncut
$(describe)"
fi

# ---------------------------------------------------------------------------------------
# 7b. The last full fault replay: the latest REPLAYED line whose detail is "all", on any
# branch, with its age in whole days; from 7 days on, and with none, the command that runs
# one (never cut); a replay of chosen ids is not full; no .harness/mutations.tsv, no command.
# ---------------------------------------------------------------------------------------
replay_cmd="bash $(cd "$ROOT/plugins/harness-kit/scripts" && pwd)/replay-faults.sh"
ago() { node -e 'console.log(new Date(Date.now() - Number(process.argv[1]) * 3600e3).toISOString().replace(/\.\d+Z$/, "Z"))' "$1"; }
dir="$(new_repo replay)"
head="$(git -C "$dir" rev-parse HEAD)"
run_session "$dir"
no_mutations="$(line 3)"
mkdir -p "$dir/.harness" && printf 'id\tapp.txt\thello\tbye\tunit\n' >"$dir/.harness/mutations.tsv"
run_session "$dir"
no_log="$(line 3)"
partial_at="$(ago 1)"
event "$dir" "$partial_at" replay-faults.sh feat-x "$head" REPLAYED "killed=2,survived=0,timeout=0,error=0,baseline=3.00s" "ids: a b"
run_session "$dir"
partial="$(line 3)"
six_at="$(ago 150)"
event "$dir" "$six_at" replay-faults.sh other "$head" REPLAYED "killed=40,survived=1,timeout=0,error=2,baseline=300.00s" "all"
event "$dir" "$(ago 2)" replay-faults.sh feat-x "$head" REPLAYED "killed=2,survived=0,timeout=0,error=0,baseline=3.00s" "ids: a b"
run_session "$dir"
six="$(line 3)"
seven_at="$(ago 170)"
dir7="$(new_repo replay-old)"
mkdir -p "$dir7/.harness" && cp "$dir/.harness/mutations.tsv" "$dir7/.harness/"
event "$dir7" "$(ago 400)" replay-faults.sh feat-x "$head" REPLAYED "killed=9,survived=0,error=0" "all"
event "$dir7" "$seven_at" replay-faults.sh main "$head" REPLAYED "killed=45,survived=0,timeout=0,error=0,baseline=310.00s" "all"
run_session "$dir7"
seven="$(line 3)"
if [ "$no_mutations" = "last full fault replay: none (there is no .harness/mutations.tsv)" ] &&
  [ "$no_log" = "last full fault replay: none (the local event log has no full replay); run one with $replay_cmd" ] &&
  [ "$partial" = "last full fault replay: none (the local event log has no full replay); run one with $replay_cmd" ] &&
  [ "$six" = "last full fault replay: 6 days ago ($six_at, branch other, 40 KILLED, 1 SURVIVED, 0 TIMEOUT, 2 ERROR)" ] &&
  [ "$seven" = "last full fault replay: 7 days ago ($seven_at, branch main, 45 KILLED, 0 SURVIVED, 0 TIMEOUT, 0 ERROR); over 7 days: run one with $replay_cmd" ]; then
  result "start-up picture: the last full fault replay's age, with the command to run one from 7 days on or with none" yes ""
else
  result "start-up picture: the last full fault replay's age, with the command to run one from 7 days on or with none" no \
    "no mutations.tsv: $no_mutations
no log: $no_log
only a partial replay: $partial
6 days: $six
7 days: $seven"
fi

# ---------------------------------------------------------------------------------------
# 8. A bare repository: every line says none, with its reason; so does a detached HEAD's.
# ---------------------------------------------------------------------------------------
dir="$(new_repo bare)"
run_session "$dir"
bare="$PIC"
bare_out="$OUT"
want_bare="branch feat-x; brief: none (there is no .reports/feat-x.brief.md)
last check: none (there is no local event log, .git/harness-kit/events.tsv)
last full fault replay: none (there is no .harness/mutations.tsv)
last review: none (there is no .harness/reviews.tsv)
uncommitted: none
state: none (docs/STATE.md does not exist)"
git -C "$dir" checkout -q --detach
head="$(git -C "$dir" rev-parse HEAD)"
run_session "$dir"
detached="$(sed -n '1,4p' <<<"$PIC")"
want_detached="branch: none (detached HEAD at ${head:0:12}); brief: none (HEAD is not on a branch)
last check: none (HEAD is not on a branch)
last full fault replay: none (there is no .harness/mutations.tsv)
last review: none (HEAD is not on a branch)"
if [ "$bare" = "$want_bare" ] && [ "$detached" = "$want_detached" ] &&
  [ "$(grep -c '^harness-kit start-up: ' <<<"$bare_out")" = 6 ]; then
  result "start-up picture: a bare repository shows none on every line" yes ""
else
  result "start-up picture: a bare repository shows none on every line" no "bare:
$bare
detached:
$detached"
fi

# ---------------------------------------------------------------------------------------
# 9. With HARNESS_KIT_EVAL set, the picture goes into additionalContext with the other lines.
# ---------------------------------------------------------------------------------------
dir="$(new_repo eval)"
HARNESS_KIT_EVAL=1 run_session "$dir"
context="$(node -e 'console.log(JSON.parse(process.argv[1]).hookSpecificOutput.additionalContext)' "$OUT" 2>&1)"
if [ "$STATUS" -eq 0 ] && grep -qx 'harness-kit start-up: uncommitted: none' <<<"$context" &&
  grep -qx 'harness-kit start-up: last review: none (there is no .harness/reviews.tsv)' <<<"$context"; then
  result "start-up picture: with HARNESS_KIT_EVAL set, it is in additionalContext" yes ""
else
  result "start-up picture: with HARNESS_KIT_EVAL set, it is in additionalContext" no "$(describe)"
fi

# THE TIME RULE. In a git repository the hook prints it, naming the branch's brief and the
# time-limit helper's path; the reviewer's session gets the version line only.
dir="$(new_repo time-rule)"
run_session "$dir"
rule="$(grep '^harness-kit time rule: ' <<<"$OUT")"
helper="$(cd "$ROOT/plugins/harness-kit/scripts" && pwd)/time-limit.mjs"
want="harness-kit time rule: before you run any command you expect to take over 2 minutes, write down your estimate of its time. Run it only if the approved brief ($dir/.reports/feat-x.brief.md) lists it in its Verification plan; otherwise ask the person. Never start a command in the background without a time limit: wrap it as node $helper run --limit <seconds> -- <command>. The background-guard hook refuses a background command that is not wrapped."
normal="$(describe)"
run_session "$dir" harness-kit:reviewer
if [ "$rule" = "$want" ] && [ "$OUT" = "$(head -n 1 <<<"$OUT")" ] && ! grep -q 'time rule' <<<"$OUT"; then
  result "session-start: the time rule is printed in a git repository, and not for the reviewer" yes ""
else
  result "session-start: the time rule is printed in a git repository, and not for the reviewer" no \
    "want: $want
got:  $rule
normal session: $normal
reviewer session: $(describe)"
fi

# THE BASH LINE. In a git repository the hook tells Claude to run harness-kit's .sh scripts
# with bash; the reviewer's session gets the version line only (checked above).
dir="$(new_repo bash-rule)"
run_session "$dir"
if [ "$STATUS" -eq 0 ] &&
  grep -qxF "harness-kit: run harness-kit's .sh scripts as \`bash <path>\`: some are not executable." <<<"$OUT"; then
  result "session-start: Claude is told to run harness-kit's .sh scripts with bash" yes ""
else
  result "session-start: Claude is told to run harness-kit's .sh scripts with bash" no "$(describe)"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures session-start case(s) failed"
  exit 1
fi
