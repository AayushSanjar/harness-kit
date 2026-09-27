#!/usr/bin/env bash
# Review the current branch with the read-only harness-kit reviewer, and record the verdict.
#
#   review.sh            run from anywhere inside the project's git repository
#
# For people, in their own terminal: it spends real money on one headless Claude run.
# Configuration, in the project's .harness/ folder (first line of each unless noted):
#   review-base            the base branch (default main); origin/<base> is used if there
#                          is no local branch of that name
#   review-checklist.md    REQUIRED. One item per line, starting with an ID that ends in a
#                          digit and a colon: "- R1: every new function has a test"
#   check-command          the project's check; its real output goes to the reviewer
#   review-reads           optional; one project-relative path per line (# comments and
#                          blank lines skipped), such as a spec, copied in whole
# Limits, from the environment: REVIEW_MAX_TURNS (default 40) and REVIEW_MAX_BUDGET_USD
# (default 3.00).
#
# WHAT IS REVIEWED is the committed branch: the diff from the merge-base with the base to
# HEAD, excluding .harness/reviews.tsv. Uncommitted changes are shown to the reviewer as
# `git status` but are not part of the diff or its hash; commit first.
#
# THE RECORD. On a completed review it prints the full review, then appends ONE line to
# .harness/reviews.tsv, tab-separated:
#   date  branch  base-sha  head-sha  diff-hash  verdict  items  cost-usd  duration-s
# base-sha is the merge-base. diff-hash comes from check-reviewed.mjs --hash, the same
# function CI runs, so the two cannot disagree. Commit the line; CI's check-reviewed.mjs
# passes only if the latest line for the branch's current diff hash says PASS.
#
# IT FAILS CLOSED. No checklist, no item IDs in it, a missing review-reads file, a failed
# or limited-out run, output that is not the expected JSON, a missing or malformed VERDICT
# line, a VERDICT that does not list exactly the checklist's IDs, a PASS with an F, or HEAD
# moving during the run: each exits 1 and appends nothing.
#
# Exit status: 0 PASS, 3 FIX-FIRST, 4 STOP (each appended); 1 nothing appended; 0 also
# when the branch has no diff against its base (nothing to review, nothing appended).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
AGENT="harness-kit:reviewer"
MAX_TURNS="${REVIEW_MAX_TURNS:-40}"
MAX_BUDGET="${REVIEW_MAX_BUDGET_USD:-3.00}"
MAX_CHECK_LINES=3000

die() {
  echo "harness-kit review.sh: $*; nothing was appended to .harness/reviews.tsv" >&2
  exit 1
}

PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
H="$PROJECT/.harness"
CHECKLIST="$H/review-checklist.md"
cd "$PROJECT" || die "cannot enter $PROJECT"

[ -s "$CHECKLIST" ] || die "no .harness/review-checklist.md (or it is empty): there is nothing to review against"
ids="$(sed -nE 's/^[[:space:]]*([-*][[:space:]]+)?\**([A-Za-z][A-Za-z0-9_-]*[0-9])\**:[[:space:]].*/\2/p' "$CHECKLIST")"
[ -n "$ids" ] || die ".harness/review-checklist.md has no items (an item is a line like \"- R1: ...\")"
dupes="$(sort <<<"$ids" | uniq -d | tr '\n' ' ')"
[ -z "$dupes" ] || die ".harness/review-checklist.md repeats item IDs: $dupes"
id_list="$(paste -sd, - <<<"$ids")"

reads=()
if [ -f "$H/review-reads" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in "" | "#"*) continue ;; esac
    [ -f "$PROJECT/$line" ] || die ".harness/review-reads names $line, which does not exist"
    reads+=("$line")
  done <"$H/review-reads"
fi

state="$(node "$HERE/check-reviewed.mjs" --hash)" || die "could not work out the branch's diff: $state"
IFS=$'\t' read -r base_ref merge_base diff_hash <<<"$state"
if [ "$diff_hash" = "none" ]; then
  echo "harness-kit review.sh: no diff against $base_ref (merge-base ${merge_base:0:12}); nothing to review" >&2
  exit 0
fi
head="$(git rev-parse HEAD)"
branch="$(git symbolic-ref --short -q HEAD || echo "(detached)")"
if [ -n "$(git status --porcelain -- . ':(exclude).harness/reviews.tsv')" ]; then
  echo "harness-kit review.sh: the working tree has uncommitted changes; they are NOT part of the reviewed diff" >&2
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/harness-kit-review.XXXXXX")" || die "cannot make a temporary folder"
trap 'rm -rf "$work"' EXIT
input="$work/input.md"

{
  echo "=== REVIEW ==="
  echo "project:     $PROJECT"
  echo "branch:      $branch"
  echo "base:        $base_ref"
  echo "merge-base:  $merge_base"
  echo "head:        $head"
  echo "checklist:   $CHECKLIST"
  echo "item IDs:    $id_list"
  echo
  echo "=== CHECKLIST ==="
  cat "$CHECKLIST"
  echo
  echo "=== CHECK COMMAND ==="
  check=""
  [ -f "$H/check-command" ] && check="$(head -n 1 "$H/check-command" | tr -d '\r')"
  if [ -z "$check" ]; then
    echo "none: the project has no .harness/check-command, so no check was run"
  else
    echo "command: $check"
    echo "Running the check command..." >&2
    /bin/sh -c 'exec 2>&1; eval "$1"' harness-kit-review "$check" </dev/null >"$work/check.out"
    check_status=$?
    total="$(wc -l <"$work/check.out" | tr -d ' ')"
    echo "exit status: $check_status"
    if [ "$total" -gt "$MAX_CHECK_LINES" ]; then
      echo "output (last $MAX_CHECK_LINES of $total lines; $((total - MAX_CHECK_LINES)) earlier lines omitted):"
      tail -n "$MAX_CHECK_LINES" "$work/check.out"
    else
      echo "output:"
      cat "$work/check.out"
    fi
  fi
  echo
  echo "=== GIT LOG ==="
  git log --no-color --format=fuller "$merge_base..HEAD"
  echo
  echo "=== GIT STATUS ==="
  git -c color.status=false status
  echo
  echo "=== DIFF ==="
  git diff --no-color --no-ext-diff "$merge_base" HEAD -- . ':(exclude).harness/reviews.tsv'
  for path in ${reads[@]+"${reads[@]}"}; do
    echo
    echo "=== READ: $path ==="
    cat "$PROJECT/$path"
  done
} >"$input" || die "could not build the reviewer's input"

# Piped stdin is capped at 10 MB (code.claude.com/docs/en/headless).
[ "$(wc -c <"$input")" -le 10000000 ] || die "the reviewer's input is over 10 MB; review a smaller branch"

echo "harness-kit review.sh: reviewing $branch against $base_ref (limits: $MAX_TURNS turns, \$$MAX_BUDGET)..." >&2
claude -p "Review this branch. Your whole input follows: judge it as your instructions say, and end with the VERDICT line." \
  --disallowedTools Write Edit NotebookEdit Bash WebFetch WebSearch \
  --plugin-dir "$PLUGIN_ROOT" \
  --agent "$AGENT" \
  --output-format json \
  --max-turns "$MAX_TURNS" \
  --max-budget-usd "$MAX_BUDGET" \
  <"$input" >"$work/out.json"
run_status=$?

# Checks the run and the VERDICT line; writes the review to review.txt and
# "verdict<TAB>items<TAB>cost<TAB>duration" to record.tsv.
node - "$work" "$run_status" "$id_list" <<'NODE' || die "the review did not complete"
const fs = require("fs");
const [work, runStatus, idList] = process.argv.slice(2);
const stop = (why) => { console.error(`harness-kit review.sh: ${why}`); process.exit(1); };
let out;
try {
  out = JSON.parse(fs.readFileSync(`${work}/out.json`, "utf8"));
} catch {
  stop(`claude exited ${runStatus} without the expected JSON output`);
}
const text = typeof out.result === "string" ? out.result : "";
if (runStatus !== "0" || out.type !== "result" || out.is_error !== false || out.subtype !== "success") {
  const detail = [text, ...(out.errors ?? [])].filter(Boolean).join(" | ").slice(0, 2000);
  stop(`the run failed: exit ${runStatus}, subtype ${out.subtype}, is_error ${out.is_error}${detail ? `: ${detail}` : ""}`);
}
fs.writeFileSync(`${work}/review.txt`, text.replace(/\s+$/, "") + "\n");
const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
const verdictLines = lines.filter((l) => l.startsWith("VERDICT"));
const last = lines[lines.length - 1] ?? "";
const m = /^VERDICT (PASS|FIX-FIRST|STOP) ((?:[A-Za-z0-9_-]+=(?:P|F|NA))(?:,[A-Za-z0-9_-]+=(?:P|F|NA))*)$/.exec(last);
if (!m) stop("the review does not end with a well-formed VERDICT line");
if (verdictLines.length !== 1) stop(`the review has ${verdictLines.length} VERDICT lines, not one`);
const [, verdict, items] = m;
const got = items.split(",").map((pair) => pair.split("=")[0]).join(",");
if (got !== idList) stop(`the VERDICT line lists ${got}, but the checklist's items are ${idList}`);
if (verdict === "PASS" && /=F(,|$)/.test(items)) stop("the VERDICT is PASS with a FAILED item");
const cost = Number(out.total_cost_usd);
const ms = Number(out.duration_ms);
if (!Number.isFinite(cost) || !Number.isFinite(ms)) stop("the JSON output has no total_cost_usd or duration_ms");
fs.writeFileSync(`${work}/record.tsv`, [verdict, items, cost.toFixed(4), (ms / 1000).toFixed(1)].join("\t"));
NODE

cat "$work/review.txt"
[ "$(git rev-parse HEAD)" = "$head" ] || die "HEAD moved during the review, so the verdict may not match the diff"

IFS=$'\t' read -r verdict items cost duration <"$work/record.tsv"
reviews="$H/reviews.tsv"
if [ -s "$reviews" ] && [ -n "$(tail -c 1 "$reviews")" ]; then echo >>"$reviews"; fi
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$branch" "$merge_base" "$head" "$diff_hash" \
  "$verdict" "$items" "$cost" "$duration" >>"$reviews" || die "could not write $reviews"

echo
echo "harness-kit review.sh: $verdict ($items), \$$cost, ${duration}s; recorded in .harness/reviews.tsv. Commit it." >&2
case "$verdict" in
  PASS) exit 0 ;;
  FIX-FIRST) exit 3 ;;
  *) exit 4 ;;
esac
