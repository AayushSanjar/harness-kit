#!/usr/bin/env bash
# Tests for plugins/harness-kit/scripts/eval-reviewer.sh. Every case runs in a temporary git
# repository with TMPDIR pointed into the test's own folder. eval-reviewer.sh finds a FAKE
# `claude` first on PATH, which records how it was called and what it saw, and prints canned
# JSON: no real API call is ever made. Prints one PASS or FAIL line per case and exits
# non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVAL="$ROOT/plugins/harness-kit/scripts/eval-reviewer.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
# eval-reviewer.sh must set HARNESS_KIT_EVAL itself (case 13).
unset HARNESS_KIT_EVAL

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

# The fake claude. It records its arguments, stdin, folder, HEAD, HARNESS_KIT_EVAL, the spec
# it can Read there, the checklist the input names (and the folder above that checklist's
# .harness/) and the node_modules links it finds; then prints the next file from
# $FAKE_QUEUE (in name order, consumed) or else $FAKE_JSON, and exits $FAKE_EXIT. Asked for
# stream-json, it prints two events before that result, as a real transcript has. With FAKE_KILL (the script's path) it first sends SIGTERM
# to the eval-reviewer.sh that started it, as an interrupted run: the last of the unbroken
# chain of ancestors running it (its subshells share its command line). With FAKE_SLEEP it
# writes its pid to $FAKE_LOG/claude.pid and sleeps that long before printing anything.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/claude" <<'FAKE'
#!/bin/sh
printf '%s\n' "$@" >"$FAKE_LOG/args"
cat >"$FAKE_LOG/stdin"
pwd -P >"$FAKE_LOG/cwd"
git rev-parse HEAD >"$FAKE_LOG/head" 2>/dev/null
cat docs/spec.md >"$FAKE_LOG/spec" 2>/dev/null
printf '%s\n' "${HARNESS_KIT_EVAL-unset}" >"$FAKE_LOG/eval-env"
checklist="$(sed -n 's/^checklist:   //p' "$FAKE_LOG/stdin")"
cat "$checklist" >"$FAKE_LOG/checklist" 2>/dev/null
(cd "$(dirname "$checklist")/.." 2>/dev/null && pwd -P) >"$FAKE_LOG/checklist-root"
for link in node_modules src/node_modules packages/web/node_modules; do
  if [ -L "$link" ]; then echo "$link -> $(readlink "$link")"; else echo "$link: none"; fi
done >"$FAKE_LOG/links"
cat node_modules/pkg/index.js >"$FAKE_LOG/through-link" 2>/dev/null
echo "$(($(cat "$FAKE_LOG/calls" 2>/dev/null || echo 0) + 1))" >"$FAKE_LOG/calls"
[ -z "${FAKE_SLEEP:-}" ] || { echo $$ >"$FAKE_LOG/claude.pid"; sleep "$FAKE_SLEEP"; }
if [ -n "${FAKE_KILL:-}" ]; then
  pid=$PPID target=""
  while [ "$pid" -gt 1 ]; do
    case "$(ps -o command= -p "$pid")" in
      *"bash $FAKE_KILL"*) target=$pid ;;
      *) [ -z "$target" ] || break ;;
    esac
    pid="$(ps -o ppid= -p "$pid" | tr -d ' ')"
  done
  [ -z "$target" ] || kill -TERM "$target"
fi
json="$FAKE_JSON"
if [ -n "${FAKE_QUEUE:-}" ]; then
  json="$FAKE_QUEUE/$(ls "$FAKE_QUEUE" | sort | head -n 1)"
fi
if grep -qx stream-json "$FAKE_LOG/args"; then
  echo '{"type":"system","subtype":"init","session_id":"fake"}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Reading the diff."}]}}'
fi
cat "$json"
echo
[ -z "${FAKE_QUEUE:-}" ] || rm -f "$json"
exit "${FAKE_EXIT:-0}"
FAKE
chmod +x "$WORK/bin/claude"

# canned NAME RESULT_TEXT [IS_ERROR]: a result JSON like `claude -p --output-format json`.
canned() {
  node -e '
    const [file, text, isError] = process.argv.slice(1);
    require("fs").writeFileSync(file, JSON.stringify({
      type: "result", subtype: "success", is_error: isError === "true",
      duration_ms: 12345, num_turns: 4, result: text, total_cost_usd: 0.1234,
    }));
  ' "$WORK/$1.json" "$2" "${3:-false}"
  echo "$WORK/$1.json"
}

# The checklist has R1 (behaviour), R2 (the checks item) and R3 (the spec).
CAUGHT_JSON="$(canned caught $'## Items\nR1 — FAIL — src/auth.js:3 "if (age > MAX_AGE) return true" accepts a token\n  after its expiry: the comparison is inverted.\nR2 — NA — EVAL MODE, no check output\nR3 — P — docs/spec.md S1\n\n## Findings\nNone.\n\n## Verdict\nFIX-FIRST: invert the comparison.\nVERDICT FIX-FIRST R1=F,R2=NA,R3=P')"
FINDING_JSON="$(canned finding $'## Items\nR1 — PASS — src/auth.js:2 "const MAX_AGE = 3600"\nR2 — NA — EVAL MODE\nR3 — PASS — docs/spec.md S1\n\n## Findings\n- src/auth.js:3 lets an expired token through.\n\n## Verdict\nFIX-FIRST.\nVERDICT FIX-FIRST R1=P,R2=NA,R3=P')"
WRONG_KEYWORD_JSON="$(canned wrong-keyword $'## Items\nR1 — FAIL — src/auth.js:3 has no doc comment\nR2 — NA — EVAL MODE\nR3 — PASS — docs/spec.md S1\n\n## Findings\nNone.\n\n## Verdict\nFIX-FIRST: add a doc comment.\nVERDICT FIX-FIRST R1=F,R2=NA,R3=P')"
CHECKS_ONLY_JSON="$(canned checks-only $'## Items\nR1 — PASS — src/auth.js:3 "if (age > MAX_AGE) return true" handles token expiry\nR2 — FAIL — no check output, so nothing shows the tests pass\nR3 — PASS — docs/spec.md S1\n\n## Findings\nNone.\n\n## Verdict\nFIX-FIRST: run the checks.\nVERDICT FIX-FIRST R1=P,R2=F,R3=P')"
CLEAN_JSON="$(canned clean $'## Items\nR1 — PASS — README.md:2 "Usage"\nR2 — NA — EVAL MODE\nR3 — NA — no behaviour change\n\n## Findings\nNone.\n\n## Verdict\nPASS.\nVERDICT PASS R1=P,R2=NA,R3=NA')"
ALARM_JSON="$(canned alarm $'## Items\nR1 — FAIL — README.md:2 no example\nR2 — NA — EVAL MODE\nR3 — NA — no behaviour change\n\n## Findings\nNone.\n\n## Verdict\nFIX-FIRST: add an example.\nVERDICT FIX-FIRST R1=F,R2=NA,R3=NA')"
FAILED_JSON="$(canned failed "API Error: Connection refused" true)"
SPLIT_JSON="$(canned split $'## Items\nR1 — FAIL — src/auth.js:3 has no doc comment\nR2 — NA — EVAL MODE\nR3 — PASS — docs/spec.md S1\n\n## Findings\n- A token past its expiry is accepted.\n\n## Verdict\nFIX-FIRST.\nVERDICT FIX-FIRST R1=F,R2=NA,R3=P')"
PREFIX_JSON="$(canned prefix $'## Items\nC1 — FAIL — src/auth.js:3 has no doc comment\nC2 — NA — EVAL MODE\nC3 — PASS — docs/spec.md S1\n\n## Findings\nNone.\n\n## Verdict\nFIX-FIRST: add a doc comment.\nVERDICT FIX-FIRST C1=F,C2=NA,C3=P')"
NA_FAIL_JSON="$(canned na-fail $'## Items\nR1 — PASS — README.md:2 "Usage: run it with node."\nR2 — FAIL — no check output, so nothing shows the checks pass\nR3 — NA — no behaviour change\n\n## Findings\nNone.\n\n## Verdict\nFIX-FIRST: run the checks.\nVERDICT FIX-FIRST R1=P,R2=F,R3=NA')"
EXPECTED_JSON="$(canned expected $'## Items\nR1 — FAIL — the comparison on line 3 is inverted, so an old token is let in\nR2 — NA — EVAL MODE\nR3 — PASS — docs/spec.md S1\n\n## Findings\nNone.\n\n## Verdict\nFIX-FIRST: invert it back.\nVERDICT FIX-FIRST R1=F,R2=NA,R3=P')"

# new_repo NAME: main has the checklist, the check command, review-reads (the spec), a
# committed reviews.tsv line and src/auth.js; then "defect" breaks auth.js, "fixed" fixes
# it and says so in the spec, and "clean" (from main) edits the README. Prints its path.
new_repo() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.harness/reviewer-eval" "$dir/src" "$dir/docs"
  git -C "$dir" init -q -b main
  printf '# Review checklist\n\n- R1: the change behaves as the spec says\n- R2: the checks pass\n- R3: matches the spec\n' \
    >"$dir/.harness/review-checklist.md"
  printf 'touch "%s"\n' "$dir.check-ran" >"$dir/.harness/check-command"
  printf 'docs/spec.md\n' >"$dir/.harness/review-reads"
  printf '2026-01-01T00:00:00Z\tmain\tabc\tdef\tabc\tPASS\tR1=P,R2=P,R3=P\t0.1000\t10.0\n' >"$dir/.harness/reviews.tsv"
  printf '# Spec\n\nS1: a token older than MAX_AGE is refused.\n' >"$dir/docs/spec.md"
  printf '# App\nUsage: run it.\n' >"$dir/README.md"
  printf 'const MAX_AGE = 3600;\nfunction expired(age) {\n  return age > MAX_AGE;\n}\n' >"$dir/src/auth.js"
  git -C "$dir" add -A && git -C "$dir" commit -q -m "main: initial"
  git -C "$dir" tag base
  printf 'const MAX_AGE = 3600;\nfunction expired(age) {\n  return age < MAX_AGE;\n}\n' >"$dir/src/auth.js"
  git -C "$dir" commit -q -am "refactor the expiry check"
  git -C "$dir" tag defect
  git -C "$dir" checkout -q -b clean base
  printf '# App\nUsage: run it with node.\n' >"$dir/README.md"
  git -C "$dir" commit -q -am "docs: say how to run it"
  git -C "$dir" tag clean-change
  git -C "$dir" checkout -q main
  echo "$dir"
}

# cases DIR LINE...: writes .harness/reviewer-eval/cases.tsv (a working-tree file, as a
# person would have it; it is left uncommitted).
cases() {
  local dir="$1"
  shift
  printf '# id\tkind\tbase\thead\tfile-regex\tkeyword-regex\tspec-replacement\n' >"$dir/.harness/reviewer-eval/cases.tsv"
  printf '%s\n' "$@" >>"$dir/.harness/reviewer-eval/cases.tsv"
}

# run_eval DIR [ARGS...]: runs eval-reviewer.sh in DIR with the fake claude and
# TMPDIR=DIR.tmp; FAKE_* come from the environment. Sets OUT, ERR, STATUS.
run_eval() {
  local dir="$1"
  shift
  mkdir -p "$dir.log" "$dir.tmp"
  rm -f "$dir.log"/*
  OUT="$(cd "$dir" && PATH="$WORK/bin:$PATH" TMPDIR="$dir.tmp" FAKE_LOG="$dir.log" bash "$EVAL" "$@" 2>"$WORK/stderr")"
  STATUS=$?
  ERR="$(cat "$WORK/stderr")"
}

describe() { printf 'exit %s\nstdout: %s\nstderr: %s' "$STATUS" "$OUT" "$ERR"; }

# untouched DIR: reviews.tsv still holds exactly its one committed line, the project's
# working tree has nothing changed but the uncommitted cases.tsv, and the check never ran.
untouched() {
  [ "$(git -C "$1" status --porcelain)" = "?? .harness/reviewer-eval/" ] &&
    [ "$(git -C "$1" show HEAD:.harness/reviews.tsv)" = "$(cat "$1/.harness/reviews.tsv")" ] &&
    [ "$(wc -l <"$1/.harness/reviews.tsv" | tr -d ' ')" = 1 ] &&
    [ ! -e "$1.check-ran" ]
}

# no_worktree DIR: git knows only the main worktree, and no worktree folder is left.
no_worktree() {
  [ "$(git -C "$1" worktree list --porcelain | grep -c '^worktree ')" = 1 ] &&
    [ -z "$(ls -A "$1/.git/worktrees" 2>/dev/null)" ] &&
    [ -z "$(find "$1.tmp" -maxdepth 1 -name 'harness-kit-eval-wt.*' 2>/dev/null)" ]
}

# row ID: the case's line from the printed table, spaces squeezed.
row() { grep "^$1 " <<<"$OUT" | tr -s ' '; }

# results_dir: the results folder eval-reviewer.sh printed at its end.
results_dir() { sed -n 's/.*results in \(.*\) (results\.tsv.*/\1/p' <<<"$ERR"; }

# 1. A defect whose review FAILS R1 naming the file and the keyword is CAUGHT; the reviewer
# ran in a worktree at the head commit, with the limits, and its input has the EVAL MODE
# line in place of the check output (the check command never ran).
dir="$(new_repo caught)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir'
FAKE_JSON="$CAUGHT_JSON" run_eval "$dir"
stdin="$(cat "$dir.log/stdin" 2>/dev/null)"
args="$(cat "$dir.log/args" 2>/dev/null)"
check_section="$(sed -n '/^=== CHECK COMMAND ===$/,/^=== GIT LOG ===$/p' <<<"$stdin")"
if [ "$STATUS" -eq 0 ] && [ "$(row d1)" = 'd1 defect FIX-FIRST CAUGHT $0.1234 12.3' ] &&
  [ "$(cat "$dir.log/head")" = "$(git -C "$dir" rev-parse defect)" ] &&
  [ "$(cat "$dir.log/cwd")" != "$(cd "$dir" && pwd -P)" ] &&
  [ "$check_section" = $'=== CHECK COMMAND ===\nEVAL MODE: historical case, no check output; mark the checks item NA\n\n=== GIT LOG ===' ] &&
  grep -qx "merge-base:  $(git -C "$dir" rev-parse base)" <<<"$stdin" &&
  grep -q '^-  return age > MAX_AGE;$' <<<"$stdin" && grep -q '^+  return age < MAX_AGE;$' <<<"$stdin" &&
  grep -q 'refactor the expiry check' <<<"$stdin" &&
  grep -qx 'item IDs:    R1,R2,R3' <<<"$stdin" && grep -qx '=== READ: docs/spec.md ===' <<<"$stdin" &&
  grep -qx 'harness-kit:reviewer' <<<"$args" && grep -qx -- '--max-turns' <<<"$args" && grep -qx 40 <<<"$args" &&
  grep -qx -- '--max-budget-usd' <<<"$args" && grep -qx 3.00 <<<"$args" &&
  grep -q '^catch rate: *100.0% (1 of 1 defect runs CAUGHT)$' <<<"$OUT" &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: a defect named by a FAILED item (file and keyword) is CAUGHT" yes ""
else
  result "eval: a defect named by a FAILED item (file and keyword) is CAUGHT" no "$(describe)
CHECK COMMAND section: $check_section"
fi

# 2. A defect named only in a finding (every item passes) is CAUGHT.
dir="$(new_repo finding)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir'
FAKE_JSON="$FINDING_JSON" run_eval "$dir"
if [ "$STATUS" -eq 0 ] && [ "$(row d1)" = 'd1 defect FIX-FIRST CAUGHT $0.1234 12.3' ] &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: a defect named by a finding is CAUGHT" yes ""
else
  result "eval: a defect named by a finding is CAUGHT" no "$(describe)"
fi

# 3. The right file with the wrong keyword is MISSED.
dir="$(new_repo wrong-keyword)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir'
FAKE_JSON="$WRONG_KEYWORD_JSON" run_eval "$dir"
if [ "$STATUS" -eq 0 ] && [ "$(row d1)" = 'd1 defect FIX-FIRST MISSED $0.1234 12.3' ] &&
  grep -q '^catch rate: *0.0% (0 of 1 defect runs CAUGHT)$' <<<"$OUT" &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: the right file with a wrong keyword is MISSED" yes ""
else
  result "eval: the right file with a wrong keyword is MISSED" no "$(describe)"
fi

# 4. A non-PASS verdict that only FAILS the checks item is MISSED, even though a PASSED
# item names the file and the keyword.
dir="$(new_repo checks-only)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir'
FAKE_JSON="$CHECKS_ONLY_JSON" run_eval "$dir"
if [ "$STATUS" -eq 0 ] && [ "$(row d1)" = 'd1 defect FIX-FIRST MISSED $0.1234 12.3' ] &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: a non-PASS verdict that only fails the checks item is MISSED" yes ""
else
  result "eval: a non-PASS verdict that only fails the checks item is MISSED" no "$(describe)"
fi

# 5. A control given PASS is CLEAN.
dir="$(new_repo clean)"
cases "$dir" $'c1\tcontrol\tbase\tclean-change\t-\t-'
FAKE_JSON="$CLEAN_JSON" run_eval "$dir"
if [ "$STATUS" -eq 0 ] && [ "$(row c1)" = 'c1 control PASS CLEAN $0.1234 12.3' ] &&
  grep -q '^false-alarm rate: *0.0% (0 of 1 control runs' <<<"$OUT" &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: a clean control given PASS is CLEAN" yes ""
else
  result "eval: a clean control given PASS is CLEAN" no "$(describe)"
fi

# 6. A control given FIX-FIRST is a FALSE ALARM.
dir="$(new_repo alarm)"
cases "$dir" $'c1\tcontrol\tbase\tclean-change\t-\t-'
FAKE_JSON="$ALARM_JSON" run_eval "$dir"
if [ "$STATUS" -eq 0 ] && [ "$(row c1)" = 'c1 control FIX-FIRST FALSE ALARM $0.1234 12.3' ] &&
  grep -q '^false-alarm rate: *100.0% (1 of 1 control runs' <<<"$OUT" &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: a control given FIX-FIRST is a FALSE ALARM" yes ""
else
  result "eval: a control given FIX-FIRST is a FALSE ALARM" no "$(describe)"
fi

# 7. A spec replacement replaces the first review-reads file in the input AND in the
# worktree the reviewer can Read; the project's own spec is left alone.
dir="$(new_repo spec)"
printf '# Spec\n\nS1: a token older than MAX_AGE is refused.\nS2: the replacement.\n' >"$dir.replacement.md"
cases "$dir" "$(printf 'd1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir\t%s' "$dir.replacement.md")"
FAKE_JSON="$CAUGHT_JSON" run_eval "$dir"
stdin="$(cat "$dir.log/stdin" 2>/dev/null)"
read_section="$(sed -n '/^=== READ: docs\/spec.md ===$/,$p' <<<"$stdin")"
if [ "$STATUS" -eq 0 ] && [ "$(row d1)" = 'd1 defect FIX-FIRST CAUGHT $0.1234 12.3' ] &&
  [ "$read_section" = "=== READ: docs/spec.md ===
$(cat "$dir.replacement.md")" ] &&
  [ "$(cat "$dir.log/spec")" = "$(cat "$dir.replacement.md")" ] &&
  grep -qx 'nothing to commit, working tree clean' <<<"$stdin" &&
  ! grep -q 'S2' "$dir/docs/spec.md" && untouched "$dir" && no_worktree "$dir"; then
  result "eval: a spec replacement is what the reviewer sees, in its input and on disk" yes ""
else
  result "eval: a spec replacement is what the reviewer sees, in its input and on disk" no "$(describe)
READ section: $read_section"
fi

# 8. A forced failure: the run fails (exit 1, is_error). It is graded ERROR, its cost still
# counted, the next case still runs, the worktree is gone and the exit status is 1.
dir="$(new_repo forced-failure)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir' $'c1\tcontrol\tbase\tclean-change\t-\t-'
mkdir -p "$WORK/queue-failure"
cp "$FAILED_JSON" "$WORK/queue-failure/1.json" && cp "$CLEAN_JSON" "$WORK/queue-failure/2.json"
FAKE_QUEUE="$WORK/queue-failure" run_eval "$dir"
if [ "$STATUS" -eq 1 ] && [ "$(row d1)" = 'd1 defect - ERROR $0.1234 12.3' ] &&
  [ "$(row c1)" = 'c1 control PASS CLEAN $0.1234 12.3' ] && grep -q 'd1 run 1 is an ERROR: ' <<<"$ERR" &&
  grep -q '^errors: *1 of 2 runs$' <<<"$OUT" && [ "$(cat "$dir.log/calls")" = 2 ] &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: a failed run is an ERROR, the next case runs, and no worktree is left" yes ""
else
  result "eval: a failed run is an ERROR, the next case runs, and no worktree is left" no "$(describe)"
fi

# 8b. A run past its limit (REVIEW_MAX_SECONDS=1, a 1-second grace period) is stopped with
# its process group and is an ERROR, "timed out after 1 seconds"; no worktree is left.
dir="$(new_repo timed-out)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir'
REVIEW_MAX_SECONDS=1 HARNESS_KIT_LIMIT_GRACE_SECONDS=1 FAKE_SLEEP=30 FAKE_JSON="$CAUGHT_JSON" run_eval "$dir"
sleep 0.2
if [ "$STATUS" -eq 1 ] && [ "$(row d1)" = 'd1 defect - ERROR $0.0000 0.0' ] &&
  grep -q 'd1 run 1 is an ERROR: timed out after 1 seconds: the reviewer ran longer than its limit of 1 seconds (TIMEOUT) and was stopped$' <<<"$ERR" &&
  [ -s "$dir.log/claude.pid" ] && ! kill -0 "$(cat "$dir.log/claude.pid")" 2>/dev/null &&
  untouched "$dir" && no_worktree "$dir" && [ -z "$(ls -A "$dir.tmp/harness-kit-live" 2>/dev/null)" ]; then
  result "eval-reviewer: a run past its limit is an ERROR, timed out, and its worktree is removed" yes ""
else
  result "eval-reviewer: a run past its limit is an ERROR, timed out, and its worktree is removed" no "$(describe)
records: $(ls -A "$dir.tmp/harness-kit-live" 2>/dev/null)"
fi

# 9. A forced interruption: SIGTERM while the reviewer runs. The worktree is still removed.
dir="$(new_repo interrupted)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir' $'c1\tcontrol\tbase\tclean-change\t-\t-'
FAKE_JSON="$CAUGHT_JSON" FAKE_KILL="$EVAL" run_eval "$dir"
if [ "$STATUS" -eq 143 ] && [ "$(cat "$dir.log/calls")" = 1 ] && untouched "$dir" && no_worktree "$dir"; then
  result "eval: an interrupted run leaves no worktree behind" yes ""
else
  result "eval: an interrupted run leaves no worktree behind" no "$(describe)
worktrees: $(git -C "$dir" worktree list)
temp: $(ls -A "$dir.tmp" 2>/dev/null)"
fi

# 10. --repeat 3: one line per run, the rates over all runs, pass@3 and pass^3 per case,
# and the totals.
dir="$(new_repo repeat)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir' $'c1\tcontrol\tbase\tclean-change\t-\t-'
mkdir -p "$WORK/queue-repeat"
cp "$CAUGHT_JSON" "$WORK/queue-repeat/1.json"
cp "$WRONG_KEYWORD_JSON" "$WORK/queue-repeat/2.json"
cp "$CAUGHT_JSON" "$WORK/queue-repeat/3.json"
for i in 4 5 6; do cp "$CLEAN_JSON" "$WORK/queue-repeat/$i.json"; done
FAKE_QUEUE="$WORK/queue-repeat" run_eval "$dir" --repeat 3
if [ "$STATUS" -eq 0 ] && [ "$(row 'd1#2')" = 'd1#2 defect FIX-FIRST MISSED $0.1234 12.3' ] &&
  [ "$(grep -c '^[dc]1#[123] ' <<<"$OUT")" = 6 ] &&
  grep -q '^catch rate: *66.7% (2 of 3 defect runs CAUGHT)$' <<<"$OUT" &&
  grep -q '^false-alarm rate: *0.0% (0 of 3 control runs' <<<"$OUT" &&
  grep -q '^pass@3: *defects 100.0% (1 of 1), controls 100.0% (1 of 1)$' <<<"$OUT" &&
  grep -q '^pass^3: *defects 0.0% (0 of 1), controls 100.0% (1 of 1)$' <<<"$OUT" &&
  grep -q '^total cost: *\$0.7404$' <<<"$OUT" && grep -q '^total time: *73.8s$' <<<"$OUT" &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: --repeat 3 reports every run, pass@3, pass^3 and the totals" yes ""
else
  result "eval: --repeat 3 reports every run, pass@3, pass^3 and the totals" no "$(describe)"
fi

# 11. A bad cases.tsv (an unknown kind; an na_items ID not in the checklist and an
# expected_item on a control; a commit that does not exist) runs nothing.
dir="$(new_repo bad-cases)"
cases "$dir" $'d1\tbug\tbase\tdefect\tsrc/auth\\.js\texpir'
FAKE_JSON="$CAUGHT_JSON" run_eval "$dir"
kind_status=$STATUS kind_err=$ERR
cases "$dir" $'c1\tcontrol\tbase\tclean-change\t-\t-\t-\tR2,R9' $'c2\tcontrol\tbase\tclean-change\t-\t-\t-\t-\tR1'
FAKE_JSON="$CAUGHT_JSON" run_eval "$dir"
item_status=$STATUS item_err=$ERR
cases "$dir" $'d1\tdefect\tbase\tno-such-commit\tsrc/auth\\.js\texpir'
FAKE_JSON="$CAUGHT_JSON" run_eval "$dir"
if [ "$kind_status" -eq 1 ] && grep -q 'kind "bug" is not defect or control' <<<"$kind_err" &&
  [ "$item_status" -eq 1 ] && grep -q 'na_items names "R9", which is not a checklist item' <<<"$item_err" &&
  grep -q 'expected_item is for a defect, not a control' <<<"$item_err" &&
  [ "$STATUS" -eq 1 ] && grep -q '"no-such-commit" is not a commit' <<<"$ERR" &&
  [ ! -e "$dir.log/calls" ] && untouched "$dir" && no_worktree "$dir"; then
  result "eval: a bad cases.tsv runs nothing" yes ""
else
  result "eval: a bad cases.tsv runs nothing" no "$(describe)
first run (bad kind): exit $kind_status: $kind_err
second run (bad item IDs): exit $item_status: $item_err"
fi

# 12. A review-reads file added after the case's head (docs/STATE.md, created on main after
# the defect) is not an error in eval mode: the run completes, and the input shows one
# "not present at this commit" line in its place, after the spec that does exist.
dir="$(new_repo missing-read)"
printf 'docs/spec.md\ndocs/STATE.md\n' >"$dir/.harness/review-reads"
printf '# State\n\nToday: the expiry check is fixed.\n' >"$dir/docs/STATE.md"
git -C "$dir" add -A && git -C "$dir" commit -q -m "add docs/STATE.md"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir'
FAKE_JSON="$CAUGHT_JSON" run_eval "$dir"
stdin="$(cat "$dir.log/stdin" 2>/dev/null)"
read_section="$(sed -n '/^=== READ: docs\/STATE.md ===$/,$p' <<<"$stdin")"
if [ "$STATUS" -eq 0 ] && [ "$(row d1)" = 'd1 defect FIX-FIRST CAUGHT $0.1234 12.3' ] &&
  [ "$read_section" = $'=== READ: docs/STATE.md ===\ndocs/STATE.md: not present at this commit' ] &&
  grep -qx '=== READ: docs/spec.md ===' <<<"$stdin" && grep -qx 'S1: a token older than MAX_AGE is refused.' <<<"$stdin" &&
  ! grep -q 'Today: the expiry check is fixed' <<<"$stdin" &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: a review-reads file missing at the case's head is shown as not present, not an ERROR" yes ""
else
  result "eval: a review-reads file missing at the case's head is shown as not present, not an ERROR" no "$(describe)
READ section: $read_section"
fi

# 13. The reviewer runs with HARNESS_KIT_EVAL=1 in its environment (so harness-kit's Stop
# hook is off; see stop-gate.test.sh), asked for stream-json; the whole transcript is saved
# beside the result event, and the final message is what is graded.
dir="$(new_repo transcript)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir'
FAKE_JSON="$CAUGHT_JSON" run_eval "$dir"
args="$(cat "$dir.log/args" 2>/dev/null)"
results="$(results_dir)"
transcript="$results/runs/d1.1/transcript.jsonl"
if [ "$STATUS" -eq 0 ] && [ "$(row d1)" = 'd1 defect FIX-FIRST CAUGHT $0.1234 12.3' ] &&
  [ "$(cat "$dir.log/eval-env")" = 1 ] &&
  grep -qx stream-json <<<"$args" && grep -qx -- --verbose <<<"$args" &&
  [ "$(wc -l <"$transcript" | tr -d ' ')" = 3 ] &&
  [ "$(head -n 1 "$transcript")" = '{"type":"system","subtype":"init","session_id":"fake"}' ] &&
  grep -q '"text":"Reading the diff."' "$transcript" &&
  [ "$(tail -n 1 "$transcript")" = "$(cat "$CAUGHT_JSON")" ] &&
  [ "$(cat "$results/runs/d1.1/out.json")" = "$(cat "$CAUGHT_JSON")" ] &&
  grep -q '^VERDICT FIX-FIRST R1=F,R2=NA,R3=P$' "$results/runs/d1.1/review.txt" &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: HARNESS_KIT_EVAL=1 for the reviewer, and its full stream-json transcript saved beside the result" yes ""
else
  result "eval: HARNESS_KIT_EVAL=1 for the reviewer, and its full stream-json transcript saved beside the result" no "$(describe)
HARNESS_KIT_EVAL seen: $(cat "$dir.log/eval-env" 2>/dev/null)
transcript ($transcript): $(cat "$transcript" 2>/dev/null)"
fi

# 14. The checklist the input names is a copy of the project's CURRENT checklist inside the
# worktree (head has an older one), so the reviewer never needs to Read outside it.
dir="$(new_repo checklist-copy)"
printf '# Review checklist\n\n- R1: the change behaves as the spec says (current)\n- R2: the checks pass\n- R3: matches the spec\n' \
  >"$dir/.harness/review-checklist.md"
git -C "$dir" commit -q -am "sharpen R1"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir'
FAKE_JSON="$CAUGHT_JSON" run_eval "$dir"
stdin="$(cat "$dir.log/stdin" 2>/dev/null)"
if [ "$STATUS" -eq 0 ] && [ "$(row d1)" = 'd1 defect FIX-FIRST CAUGHT $0.1234 12.3' ] &&
  grep -q '^checklist:   .*/\.harness/review-checklist\.md$' <<<"$stdin" &&
  [ "$(cat "$dir.log/checklist-root")" = "$(cat "$dir.log/cwd")" ] &&
  [ "$(cat "$dir.log/checklist")" = "$(cat "$dir/.harness/review-checklist.md")" ] &&
  [ "$(git -C "$dir" show defect:.harness/review-checklist.md)" != "$(cat "$dir.log/checklist")" ] &&
  grep -q '^- R1: the change behaves as the spec says (current)$' <<<"$stdin" &&
  grep -qx 'nothing to commit, working tree clean' <<<"$stdin" &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: the reviewer is pointed at a copy of the current checklist inside its worktree" yes ""
else
  result "eval: the reviewer is pointed at a copy of the current checklist inside its worktree" no "$(describe)
checklist line: $(grep '^checklist:' <<<"$stdin")
checklist's project folder: $(cat "$dir.log/checklist-root" 2>/dev/null); reviewer's folder: $(cat "$dir.log/cwd" 2>/dev/null)"
fi

# 15. Every node_modules folder of the main checkout is linked into the worktree at the same
# path when its parent exists there (the root, src/); packages/web/ is not at head, so its
# node_modules gets no link. The folders linked to are still there afterwards.
dir="$(new_repo node-modules)"
printf 'node_modules\npackages/\n' >>"$dir/.git/info/exclude"
mkdir -p "$dir/node_modules/pkg" "$dir/src/node_modules/lib" "$dir/packages/web/node_modules/dep"
printf 'module.exports = "pkg 2.0";\n' >"$dir/node_modules/pkg/index.js"
printf 'x\n' >"$dir/src/node_modules/lib/x.js"
printf 'y\n' >"$dir/packages/web/node_modules/dep/y.js"
real="$(cd "$dir" && pwd -P)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir'
FAKE_JSON="$CAUGHT_JSON" run_eval "$dir"
links="$(cat "$dir.log/links" 2>/dev/null)"
if [ "$STATUS" -eq 0 ] && [ "$(row d1)" = 'd1 defect FIX-FIRST CAUGHT $0.1234 12.3' ] &&
  [ "$links" = "node_modules -> $real/node_modules
src/node_modules -> $real/src/node_modules
packages/web/node_modules: none" ] &&
  [ "$(cat "$dir.log/through-link")" = 'module.exports = "pkg 2.0";' ] &&
  grep -qx 'nothing to commit, working tree clean' "$dir.log/stdin" &&
  [ -f "$dir/node_modules/pkg/index.js" ] && [ -f "$dir/src/node_modules/lib/x.js" ] &&
  [ -f "$dir/packages/web/node_modules/dep/y.js" ] &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: node_modules linked into the worktree, and no link where the parent folder is absent" yes ""
else
  result "eval: node_modules linked into the worktree, and no link where the parent folder is absent" no "$(describe)
links: $links"
fi

# 16. Rule A: the file named in one failed item and the keyword in a finding is MISSED; the
# two must match inside ONE text.
dir="$(new_repo split)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir'
FAKE_JSON="$SPLIT_JSON" run_eval "$dir"
if [ "$STATUS" -eq 0 ] && [ "$(row d1)" = 'd1 defect FIX-FIRST MISSED $0.1234 12.3' ] &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: rule A, the file in one failed item and the keyword in a finding is MISSED" yes ""
else
  result "eval: rule A, the file in one failed item and the keyword in a finding is MISSED" no "$(describe)"
fi

# 17. Rule A: an item's "C1 — FAIL —" prefix is not the keyword "fail" (the checklist here
# has C ids).
dir="$(new_repo prefix)"
printf '# Review checklist\n\n- C1: the change behaves as the spec says\n- C2: the checks pass\n- C3: matches the spec\n' \
  >"$dir/.harness/review-checklist.md"
git -C "$dir" commit -q -am "C ids"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\tfail'
FAKE_JSON="$PREFIX_JSON" run_eval "$dir"
if [ "$STATUS" -eq 0 ] && [ "$(row d1)" = 'd1 defect FIX-FIRST MISSED $0.1234 12.3' ] &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: rule A, the prefix \"C1 — FAIL —\" does not count as the keyword \"fail\"" yes ""
else
  result "eval: rule A, the prefix \"C1 — FAIL —\" does not count as the keyword \"fail\"" no "$(describe)"
fi

# 18. na_items: the input says "EVAL MODE: mark R2 NA", and a FAIL on R2 alone is CLEAN, not
# a FALSE ALARM; the same review for a control without na_items is still a FALSE ALARM.
dir="$(new_repo na-items)"
cases "$dir" $'c1\tcontrol\tbase\tclean-change\t-\t-\t-\tR2' $'c2\tcontrol\tbase\tclean-change\t-\t-'
FAKE_JSON="$NA_FAIL_JSON" run_eval "$dir"
results="$(results_dir)"
c1_check="$(sed -n '/^=== CHECK COMMAND ===$/,/^=== GIT LOG ===$/p' "$results/runs/c1.1/input.md" 2>/dev/null)"
if [ "$STATUS" -eq 0 ] && [ "$(row c1)" = 'c1 control FIX-FIRST CLEAN $0.1234 12.3' ] &&
  [ "$(row c2)" = 'c2 control FIX-FIRST FALSE ALARM $0.1234 12.3' ] &&
  [ "$c1_check" = $'=== CHECK COMMAND ===\nEVAL MODE: historical case, no check output; mark the checks item NA\nEVAL MODE: mark R2 NA\n\n=== GIT LOG ===' ] &&
  ! grep -q 'EVAL MODE: mark R2 NA' "$results/runs/c2.1/input.md" &&
  grep -q '^false-alarm rate: *50.0% (1 of 2 control runs' <<<"$OUT" &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: a FAIL on an na_items item is not a false alarm, and the input asks for NA" yes ""
else
  result "eval: a FAIL on an na_items item is not a false alarm, and the input asks for NA" no "$(describe)
c1's CHECK COMMAND section: $c1_check"
fi

# 19. expected_item: R1 FAILED with the keyword but no file name is CAUGHT when R1 is the
# expected item, and MISSED without one.
dir="$(new_repo expected-item)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\tinvert\t-\t-\tR1' $'d2\tdefect\tbase\tdefect\tsrc/auth\\.js\tinvert'
FAKE_JSON="$EXPECTED_JSON" run_eval "$dir"
if [ "$STATUS" -eq 0 ] && [ "$(row d1)" = 'd1 defect FIX-FIRST CAUGHT $0.1234 12.3' ] &&
  [ "$(row d2)" = 'd2 defect FIX-FIRST MISSED $0.1234 12.3' ] &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: the expected_item FAILED with the keyword is CAUGHT" yes ""
else
  result "eval: the expected_item FAILED with the keyword is CAUGHT" no "$(describe)"
fi

# 20. --regrade: the saved review, graded MISSED, is graded again with a cases.tsv whose
# keyword now matches: CAUGHT, in the same table, with no claude call; results.tsv is left
# alone and the new grades go to regraded.tsv.
dir="$(new_repo regrade)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\texpir' $'c1\tcontrol\tbase\tclean-change\t-\t-'
mkdir -p "$WORK/queue-regrade"
cp "$WRONG_KEYWORD_JSON" "$WORK/queue-regrade/1.json" && cp "$CLEAN_JSON" "$WORK/queue-regrade/2.json"
FAKE_QUEUE="$WORK/queue-regrade" run_eval "$dir"
first_d1="$(row d1)" first_status=$STATUS
results="$(results_dir)"
original="$(cat "$results/results.tsv" 2>/dev/null)"
cases "$dir" $'d1\tdefect\tbase\tdefect\tsrc/auth\\.js\tdoc comment' $'c1\tcontrol\tbase\tclean-change\t-\t-'
FAKE_JSON="$CAUGHT_JSON" run_eval "$dir" --regrade "$results"
if [ "$first_status" -eq 0 ] && [ "$first_d1" = 'd1 defect FIX-FIRST MISSED $0.1234 12.3' ] &&
  [ "$STATUS" -eq 0 ] && [ "$(row d1)" = 'd1 defect FIX-FIRST CAUGHT $0.1234 12.3' ] &&
  [ "$(row c1)" = 'c1 control PASS CLEAN $0.1234 12.3' ] &&
  grep -q '^catch rate: *100.0% (1 of 1 defect runs CAUGHT)$' <<<"$OUT" &&
  [ ! -e "$dir.log/calls" ] && [ ! -e "$dir.log/args" ] &&
  [ "$(cat "$results/results.tsv")" = "$original" ] && grep -q $'^d1\t1\tdefect\tFIX-FIRST\tCAUGHT\t' "$results/regraded.tsv" &&
  [ "$(git -C "$dir" worktree list --porcelain | grep -c '^worktree ')" = 1 ] &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: --regrade grades saved runs again with the current cases.tsv, with no claude call" yes ""
else
  result "eval: --regrade grades saved runs again with the current cases.tsv, with no claude call" no "first run: exit $first_status, d1: $first_d1
regrade: $(describe)
claude calls during the regrade: $(cat "$dir.log/calls" 2>/dev/null || echo 0)"
fi


# 21. A case whose head deletes a large file: the input shows it as one summary line, never
# its content, and the run is graded as usual.
dir="$(new_repo deleted)"
git -C "$dir" checkout -q -b big base
seq -f 'old line %g of the big file' 1 6000 >"$dir/big.txt"
git -C "$dir" add -A && git -C "$dir" commit -q -m "add big.txt"
git -C "$dir" tag with-big
git -C "$dir" rm -q big.txt && git -C "$dir" commit -q -m "drop big.txt"
git -C "$dir" tag dropped
git -C "$dir" checkout -q main
cases "$dir" $'c1\tcontrol\twith-big\tdropped\t-\t-'
FAKE_JSON="$CLEAN_JSON" run_eval "$dir"
stdin="$(cat "$dir.log/stdin" 2>/dev/null)"
if [ "$STATUS" -eq 0 ] && [ "$(row c1)" = 'c1 control PASS CLEAN $0.1234 12.3' ] &&
  grep -qx 'deleted: big.txt (6000 lines)' <<<"$stdin" && ! grep -q 'of the big file' <<<"$stdin" &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: a deleted file is one summary line in the input" yes ""
else
  result "eval: a deleted file is one summary line in the input" no "$(describe)
DIFF section: $(sed -n '/^=== DIFF ===$/,$p' <<<"$stdin" | head -n 20)"
fi

# 22. A case whose input is over the limit is an ERROR before any claude call, naming the
# largest file; the next case still runs, and no worktree is left.
dir="$(new_repo oversized)"
git -C "$dir" checkout -q -b huge base
seq -f 'new line %g of the huge file, long enough to add up quickly' 1 5000 >"$dir/huge.txt"
git -C "$dir" add -A && git -C "$dir" commit -q -m "add huge.txt"
git -C "$dir" checkout -q main
cases "$dir" $'d1\tdefect\tbase\thuge\thuge\\.txt\tsize' $'c1\tcontrol\tbase\tclean-change\t-\t-'
FAKE_JSON="$CLEAN_JSON" run_eval "$dir"
if [ "$STATUS" -eq 1 ] && [ "$(row d1)" = 'd1 defect - ERROR $0.0000 0.0' ] &&
  [ "$(row c1)" = 'c1 control PASS CLEAN $0.1234 12.3' ] && [ "$(cat "$dir.log/calls" 2>/dev/null)" = 1 ] &&
  grep -q "d1 run 1 is an ERROR: the reviewer's input is [0-9]* bytes, over the limit of 250000 (REVIEW_MAX_INPUT_BYTES), so claude was not started. The largest parts: huge.txt (" <<<"$ERR" &&
  untouched "$dir" && no_worktree "$dir"; then
  result "eval: an input over the limit is an ERROR before any claude call" yes ""
else
  result "eval: an input over the limit is an ERROR before any claude call" no "$(describe)
claude calls: $(cat "$dir.log/calls" 2>/dev/null || echo 0)"
fi

[ "$failures" -eq 0 ]
