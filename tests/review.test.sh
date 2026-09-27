#!/usr/bin/env bash
# Tests for plugins/harness-kit/scripts/review.sh, check-reviewed.mjs and reviewer-guard.mjs.
# Every case runs in a temporary git repository. review.sh finds a FAKE `claude` first on
# PATH, which records its arguments and stdin and prints canned JSON: no real API call is
# ever made. Prints one PASS or FAIL line per case and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/plugins/harness-kit/scripts"
REVIEW="$SCRIPTS/review.sh"
CHECK="$SCRIPTS/check-reviewed.mjs"
GUARD="$SCRIPTS/reviewer-guard.mjs"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0

# The test repositories must not depend on the person's git settings (signing, hooks,
# diff options).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

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

# The fake claude: records how it was called, then prints $FAKE_JSON and exits $FAKE_EXIT.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/claude" <<'FAKE'
#!/bin/sh
printf '%s\n' "$@" >"$FAKE_LOG/args"
cat >"$FAKE_LOG/stdin"
cat "$FAKE_JSON"
exit "${FAKE_EXIT:-0}"
FAKE
chmod +x "$WORK/bin/claude"

# canned NAME RESULT_TEXT [IS_ERROR]: write a result JSON like `claude -p --output-format
# json` prints. A failed run keeps subtype "success" with is_error true, as a real API
# error does (observed with Claude Code 2.1.283).
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

REVIEW_BODY=$'## Items\nR1 — PASS — app.txt:1 "hello"\nR2 — NA — no spec in this change\n\n## Findings\nNone.\n\n## Verdict\n'
PASS_JSON="$(canned pass "${REVIEW_BODY}PASS.
VERDICT PASS R1=P,R2=NA")"
FIX_JSON="$(canned fix "${REVIEW_BODY}FIX-FIRST: add the test.
VERDICT FIX-FIRST R1=F,R2=NA")"
NO_VERDICT_JSON="$(canned no-verdict "${REVIEW_BODY}Looks good to me.")"
WRONG_IDS_JSON="$(canned wrong-ids "${REVIEW_BODY}PASS.
VERDICT PASS R1=P")"
FAILED_JSON="$(canned failed "API Error: Connection refused" true)"

# new_repo NAME: a repository with main (a checklist, a check command, one file) and a
# branch "feature" with one more commit. Prints its path.
new_repo() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.harness"
  git -C "$dir" init -q -b main
  printf 'hello\n' >"$dir/app.txt"
  printf '# Review checklist\n\n- R1: app.txt says hello\n- R2: matches the spec\n' >"$dir/.harness/review-checklist.md"
  printf 'echo "check: 3 passed, 0 failed"\n' >"$dir/.harness/check-command"
  git -C "$dir" add -A && git -C "$dir" commit -q -m "main: initial"
  git -C "$dir" checkout -q -b feature
  printf 'hello\nworld\n' >"$dir/app.txt"
  git -C "$dir" commit -q -am "feature: add world"
  echo "$dir"
}

# run_review DIR JSON [EXIT]: run review.sh in DIR with the fake claude; sets OUT, ERR, STATUS.
run_review() {
  mkdir -p "$1.log"
  rm -f "$1.log/args" "$1.log/stdin"
  OUT="$(cd "$1" && PATH="$WORK/bin:$PATH" FAKE_LOG="$1.log" FAKE_JSON="$2" FAKE_EXIT="${3:-0}" \
    bash "$REVIEW" 2>"$WORK/stderr")"
  STATUS=$?
  ERR="$(cat "$WORK/stderr")"
}

# run_check DIR: run check-reviewed.mjs in DIR; sets OUT, STATUS.
run_check() {
  OUT="$(cd "$1" && node "$CHECK" 2>&1)"
  STATUS=$?
  ERR=""
}

describe() { printf 'exit %s\nstdout: %s\nstderr: %s' "$STATUS" "$OUT" "${ERR:-}"; }
lines_in() { [ -f "$1" ] && wc -l <"$1" | tr -d ' ' || echo 0; }

# ---------------------------------------------------------------------------------------
# review.sh
# ---------------------------------------------------------------------------------------

# 1. A PASS review: exit 0, the review printed, one line appended with the right fields,
# and the fake was called with the reviewer, the limits and the real check output.
dir="$(new_repo pass)"
run_review "$dir" "$PASS_JSON"
row="$(cat "$dir/.harness/reviews.tsv" 2>/dev/null)"
IFS=$'\t' read -r r_date r_branch r_base r_head r_hash r_verdict r_items r_cost r_duration <<<"$row"
hash="$(cd "$dir" && node "$CHECK" --hash | cut -f3)"
args="$(cat "$dir.log/args" 2>/dev/null)"
stdin="$(cat "$dir.log/stdin" 2>/dev/null)"
if [ "$STATUS" -eq 0 ] && grep -q '^R1 — PASS' <<<"$OUT" &&
  [ "$(lines_in "$dir/.harness/reviews.tsv")" = 1 ] && [ "$(awk -F'\t' '{print NF}' <<<"$row")" = 9 ] &&
  [[ "$r_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]] && [ "$r_branch" = feature ] &&
  [ "$r_base" = "$(git -C "$dir" rev-parse main)" ] && [ "$r_head" = "$(git -C "$dir" rev-parse HEAD)" ] &&
  [ "$r_hash" = "$hash" ] && [ "${#r_hash}" = 64 ] && [ "$r_verdict" = PASS ] && [ "$r_items" = "R1=P,R2=NA" ] &&
  [ "$r_cost" = 0.1234 ] && [ "$r_duration" = 12.3 ] &&
  grep -qx -- '--agent' <<<"$args" && grep -qx 'harness-kit:reviewer' <<<"$args" &&
  grep -qx -- '--max-turns' <<<"$args" && grep -qx -- '--max-budget-usd' <<<"$args" &&
  grep -qx -- '--output-format' <<<"$args" && grep -qx 'json' <<<"$args" &&
  grep -qx 'check: 3 passed, 0 failed' <<<"$stdin" && grep -qx 'exit status: 0' <<<"$stdin" &&
  grep -q '^+world$' <<<"$stdin" && grep -q 'feature: add world' <<<"$stdin" &&
  grep -q '^- R2: matches the spec$' <<<"$stdin"; then
  result "review.sh: a PASS review appends one line with all nine fields" yes ""
else
  result "review.sh: a PASS review appends one line with all nine fields" no "$(describe)
row: $row"
fi

# 2. No checklist: exit non-zero, nothing appended, claude never started.
dir="$(new_repo no-checklist)"
git -C "$dir" rm -q .harness/review-checklist.md && git -C "$dir" commit -q -m "drop checklist"
run_review "$dir" "$PASS_JSON"
if [ "$STATUS" -ne 0 ] && [ ! -e "$dir/.harness/reviews.tsv" ] && [ ! -e "$dir.log/args" ] &&
  grep -q 'no .harness/review-checklist.md' <<<"$ERR"; then
  result "review.sh: no checklist exits non-zero and appends nothing" yes ""
else
  result "review.sh: no checklist exits non-zero and appends nothing" no "$(describe)"
fi

# 3. The review has no VERDICT line: exit non-zero, nothing appended.
dir="$(new_repo no-verdict)"
run_review "$dir" "$NO_VERDICT_JSON"
if [ "$STATUS" -ne 0 ] && [ ! -e "$dir/.harness/reviews.tsv" ] && grep -q 'VERDICT line' <<<"$ERR"; then
  result "review.sh: no VERDICT line exits non-zero and appends nothing" yes ""
else
  result "review.sh: no VERDICT line exits non-zero and appends nothing" no "$(describe)"
fi

# 4. A failed run (exit 1, is_error true): exit non-zero, nothing appended.
dir="$(new_repo failed-run)"
run_review "$dir" "$FAILED_JSON" 1
if [ "$STATUS" -ne 0 ] && [ ! -e "$dir/.harness/reviews.tsv" ] && grep -q 'the run failed' <<<"$ERR"; then
  result "review.sh: a failed run exits non-zero and appends nothing" yes ""
else
  result "review.sh: a failed run exits non-zero and appends nothing" no "$(describe)"
fi

# 5. A VERDICT line that leaves out a checklist item: exit non-zero, nothing appended.
dir="$(new_repo wrong-ids)"
run_review "$dir" "$WRONG_IDS_JSON"
if [ "$STATUS" -ne 0 ] && [ ! -e "$dir/.harness/reviews.tsv" ] && grep -q "checklist's items are R1,R2" <<<"$ERR"; then
  result "review.sh: a VERDICT missing a checklist item appends nothing" yes ""
else
  result "review.sh: a VERDICT missing a checklist item appends nothing" no "$(describe)"
fi

# 6. A review-reads file that does not exist fails closed, as ever (only eval-reviewer.sh
# tolerates one): exit non-zero, nothing appended, claude never started.
dir="$(new_repo missing-read)"
printf 'docs/STATE.md\n' >"$dir/.harness/review-reads"
git -C "$dir" add -A && git -C "$dir" commit -q -m "review-reads names a file that does not exist"
run_review "$dir" "$PASS_JSON"
if [ "$STATUS" -ne 0 ] && [ ! -e "$dir/.harness/reviews.tsv" ] && [ ! -e "$dir.log/args" ] &&
  grep -q 'review-reads names docs/STATE.md, which does not exist' <<<"$ERR"; then
  result "review.sh: a missing review-reads file exits non-zero and appends nothing" yes ""
else
  result "review.sh: a missing review-reads file exits non-zero and appends nothing" no "$(describe)"
fi

# ---------------------------------------------------------------------------------------
# check-reviewed.mjs
# ---------------------------------------------------------------------------------------

# 7. A committed PASS for the current diff passes.
dir="$(new_repo check-pass)"
run_review "$dir" "$PASS_JSON"
git -C "$dir" add .harness/reviews.tsv && git -C "$dir" commit -q -m "review: PASS"
run_check "$dir"
if [ "$STATUS" -eq 0 ] && grep -q '^PASS check-reviewed: diff .* was reviewed .*: PASS$' <<<"$OUT"; then
  result "check-reviewed: a matching PASS passes" yes ""
else
  result "check-reviewed: a matching PASS passes" no "$(describe)"
fi

# 8. The same repository after one more commit: the diff changed, so it fails.
printf 'hello\nworld\nagain\n' >"$dir/app.txt"
git -C "$dir" commit -q -am "feature: one more line"
run_check "$dir"
if [ "$STATUS" -ne 0 ] && grep -q '^FAIL check-reviewed: no review of this branch.s current diff' <<<"$OUT" &&
  grep -q 'the diff changed since the last review' <<<"$OUT" &&
  grep -q 'Run scripts/review.sh in your own terminal.' <<<"$OUT"; then
  result "check-reviewed: a changed diff fails" yes ""
else
  result "check-reviewed: a changed diff fails" no "$(describe)"
fi

# 9. A committed FIX-FIRST for the current diff fails, naming the verdict.
dir="$(new_repo check-fix)"
run_review "$dir" "$FIX_JSON"
review_status=$STATUS
git -C "$dir" add .harness/reviews.tsv && git -C "$dir" commit -q -m "review: FIX-FIRST"
run_check "$dir"
if [ "$review_status" -eq 3 ] && [ "$STATUS" -ne 0 ] && grep -q 'says FIX-FIRST (R1=F,R2=NA), not PASS' <<<"$OUT" &&
  grep -q 'Run scripts/review.sh in your own terminal.' <<<"$OUT"; then
  result "check-reviewed: a FIX-FIRST verdict fails" yes ""
else
  result "check-reviewed: a FIX-FIRST verdict fails" no "$(describe)
review.sh exit: $review_status"
fi

# 10. An old line (committed on main) edited on the branch fails, even though the branch
# also has a PASS for its current diff. The PASS alone is checked first, as a control.
dir="$(new_repo check-append-only)"
git -C "$dir" checkout -q main
printf '2026-01-01T00:00:00Z\told\t%s\t%s\tabc\tPASS\tR1=P,R2=P\t0.1000\t10.0\n' \
  "$(git -C "$dir" rev-parse HEAD)" "$(git -C "$dir" rev-parse HEAD)" >"$dir/.harness/reviews.tsv"
git -C "$dir" add .harness/reviews.tsv && git -C "$dir" commit -q -m "main: an old review"
git -C "$dir" checkout -q feature && git -C "$dir" rebase -q main
run_review "$dir" "$PASS_JSON"
git -C "$dir" add .harness/reviews.tsv && git -C "$dir" commit -q -m "review: PASS"
run_check "$dir"
control_status=$STATUS
awk 'NR == 1 { sub(/\tPASS\t/, "\tFIX-FIRST\t") } 1' "$dir/.harness/reviews.tsv" >"$WORK/edited.tsv" &&
  mv "$WORK/edited.tsv" "$dir/.harness/reviews.tsv"
git -C "$dir" commit -q -am "edit an old review"
run_check "$dir"
if [ "$control_status" -eq 0 ] && [ "$STATUS" -ne 0 ] &&
  grep -q 'reviews.tsv is append-only, but line 1 as of the merge-base .* was changed' <<<"$OUT"; then
  result "check-reviewed: an edited old line fails (append-only)" yes ""
else
  result "check-reviewed: an edited old line fails (append-only)" no "$(describe)
control (before the edit) exit: $control_status"
fi

# 11. A branch with no diff against its base passes, and says why.
dir="$(new_repo check-empty)"
git -C "$dir" checkout -q -b empty main
run_check "$dir"
if [ "$STATUS" -eq 0 ] && grep -q '^PASS check-reviewed: no diff against main .*nothing to review$' <<<"$OUT"; then
  result "check-reviewed: an empty branch passes" yes ""
else
  result "check-reviewed: an empty branch passes" no "$(describe)"
fi

# ---------------------------------------------------------------------------------------
# reviewer-guard.mjs
# ---------------------------------------------------------------------------------------

# run_guard AGENT_TYPE TOOL: sets OUT and STATUS. An empty AGENT_TYPE leaves the field out.
run_guard() {
  local input
  input="$(node -e '
    const [agentType, tool] = process.argv.slice(1);
    const input = { hook_event_name: "PreToolUse", tool_name: tool, tool_input: {} };
    if (agentType) input.agent_type = agentType;
    console.log(JSON.stringify(input));
  ' "$1" "$2")"
  OUT="$(node "$GUARD" <<<"$input" 2>&1)"
  STATUS=$?
  ERR=""
}

for tool in Write Edit NotebookEdit Bash WebFetch WebSearch; do
  run_guard "harness-kit:reviewer" "$tool"
  if [ "$STATUS" -eq 0 ] && grep -q '"permissionDecision":"deny"' <<<"$OUT" &&
    grep -q "the reviewer is read-only, so $tool is not allowed" <<<"$OUT"; then
    result "guard: $tool denied for harness-kit:reviewer" yes ""
  else
    result "guard: $tool denied for harness-kit:reviewer" no "$(describe)"
  fi
  run_guard "general-purpose" "$tool"
  if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ]; then
    result "guard: $tool allowed for general-purpose" yes ""
  else
    result "guard: $tool allowed for general-purpose" no "$(describe)"
  fi
done

run_guard "" "Bash"
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ]; then
  result "guard: Bash allowed with no agent_type (the main session)" yes ""
else
  result "guard: Bash allowed with no agent_type (the main session)" no "$(describe)"
fi

run_guard "harness-kit:reviewer" "Read"
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ]; then
  result "guard: Read allowed for harness-kit:reviewer" yes ""
else
  result "guard: Read allowed for harness-kit:reviewer" no "$(describe)"
fi

[ "$failures" -eq 0 ]
