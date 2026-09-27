# Shared by review.sh and eval-reviewer.sh, which source it: reading the checklist and
# review-reads, building the reviewer's input, running the reviewer headless within the
# turn and budget limits, and checking what it returns. Written for bash 3.2 (macOS).
#
# Each function returns 1 on failure with the reason in REVIEW_ERROR; the caller decides
# what failing means (review.sh exits, eval-reviewer.sh grades the run ERROR).
#
# Limits, from the environment: REVIEW_MAX_TURNS (default 40) and REVIEW_MAX_BUDGET_USD
# (default 3.00).

REVIEW_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REVIEW_AGENT="harness-kit:reviewer"
REVIEW_TURNS="${REVIEW_MAX_TURNS:-40}"
REVIEW_BUDGET="${REVIEW_MAX_BUDGET_USD:-3.00}"
REVIEW_MAX_CHECK_LINES=3000
REVIEW_ERROR=""
REVIEW_ID_LIST=""
REVIEW_READS=()
REVIEW_READ_SOURCES=()

review_fail() {
  REVIEW_ERROR="$*"
  return 1
}

# review_load_checklist CHECKLIST: sets REVIEW_ID_LIST ("R1,R2,..."), the item IDs in order.
review_load_checklist() {
  local checklist="$1" ids dupes
  [ -s "$checklist" ] || review_fail "no .harness/review-checklist.md (or it is empty): there is nothing to review against" || return 1
  ids="$(sed -nE 's/^[[:space:]]*([-*][[:space:]]+)?\**([A-Za-z][A-Za-z0-9_-]*[0-9])\**:[[:space:]].*/\2/p' "$checklist")"
  [ -n "$ids" ] || review_fail ".harness/review-checklist.md has no items (an item is a line like \"- R1: ...\")" || return 1
  dupes="$(sort <<<"$ids" | uniq -d | tr '\n' ' ')"
  [ -z "$dupes" ] || review_fail ".harness/review-checklist.md repeats item IDs: $dupes" || return 1
  REVIEW_ID_LIST="$(paste -sd, - <<<"$ids")"
}

# review_load_reads LIST ROOT: sets REVIEW_READS to the project-relative paths LIST names
# (# comments and blank lines skipped) and REVIEW_READ_SOURCES to the file each is copied
# from, ROOT/<path>. A caller may point a source elsewhere before review_check_reads.
review_load_reads() {
  local list="$1" root="$2" line
  REVIEW_READS=()
  REVIEW_READ_SOURCES=()
  [ -f "$list" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in "" | "#"*) continue ;; esac
    REVIEW_READS+=("$line")
    REVIEW_READ_SOURCES+=("$root/$line")
  done <"$list"
}

review_check_reads() {
  local i=0
  while [ "$i" -lt "${#REVIEW_READS[@]}" ]; do
    [ -f "${REVIEW_READ_SOURCES[$i]}" ] ||
      review_fail ".harness/review-reads names ${REVIEW_READS[$i]}, which does not exist" || return 1
    i=$((i + 1))
  done
}

# review_check_section H WORK: runs the project's check command from the current folder and
# prints the body of the CHECK COMMAND section: the command, its exit status and its output.
review_check_section() {
  local h="$1" work="$2" check="" check_status total
  [ -f "$h/check-command" ] && check="$(head -n 1 "$h/check-command" | tr -d '\r')"
  if [ -z "$check" ]; then
    echo "none: the project has no .harness/check-command, so no check was run"
    return 0
  fi
  echo "command: $check"
  echo "Running the check command..." >&2
  /bin/sh -c 'exec 2>&1; eval "$1"' harness-kit-review "$check" </dev/null >"$work/check.out"
  check_status=$?
  total="$(wc -l <"$work/check.out" | tr -d ' ')"
  echo "exit status: $check_status"
  if [ "$total" -gt "$REVIEW_MAX_CHECK_LINES" ]; then
    echo "output (last $REVIEW_MAX_CHECK_LINES of $total lines; $((total - REVIEW_MAX_CHECK_LINES)) earlier lines omitted):"
    tail -n "$REVIEW_MAX_CHECK_LINES" "$work/check.out"
  else
    echo "output:"
    cat "$work/check.out"
  fi
}

# review_build_input OUT PROJECT BRANCH BASE_REF MERGE_BASE HEAD CHECKLIST CHECK_SECTION:
# writes the reviewer's whole input to OUT. CHECK_SECTION is a file holding the body of the
# CHECK COMMAND section. Uses REVIEW_ID_LIST, REVIEW_READS and REVIEW_READ_SOURCES.
review_build_input() {
  local out="$1" project="$2" branch="$3" base_ref="$4" merge_base="$5" head="$6" checklist="$7" check_section="$8" i=0
  {
    echo "=== REVIEW ==="
    echo "project:     $project"
    echo "branch:      $branch"
    echo "base:        $base_ref"
    echo "merge-base:  $merge_base"
    echo "head:        $head"
    echo "checklist:   $checklist"
    echo "item IDs:    $REVIEW_ID_LIST"
    echo
    echo "=== CHECKLIST ==="
    cat "$checklist"
    echo
    echo "=== CHECK COMMAND ==="
    cat "$check_section"
    echo
    echo "=== GIT LOG ==="
    git -C "$project" log --no-color --format=fuller "$merge_base..$head"
    echo
    echo "=== GIT STATUS ==="
    git -C "$project" -c color.status=false status
    echo
    echo "=== DIFF ==="
    git -C "$project" diff --no-color --no-ext-diff "$merge_base" "$head" -- . ':(exclude).harness/reviews.tsv'
    while [ "$i" -lt "${#REVIEW_READS[@]}" ]; do
      echo
      echo "=== READ: ${REVIEW_READS[$i]} ==="
      cat "${REVIEW_READ_SOURCES[$i]}"
      i=$((i + 1))
    done
  } >"$out" || review_fail "could not build the reviewer's input" || return 1
  # Piped stdin is capped at 10 MB (code.claude.com/docs/en/headless).
  [ "$(wc -c <"$out")" -le 10000000 ] || review_fail "the reviewer's input is over 10 MB; review a smaller branch" || return 1
}

# review_run DIR INPUT OUT_JSON: runs the reviewer headless in DIR on INPUT, within the
# limits; returns claude's exit status.
review_run() {
  (
    cd "$1" &&
      claude -p "Review this branch. Your whole input follows: judge it as your instructions say, and end with the VERDICT line." \
        --disallowedTools Write Edit NotebookEdit Bash WebFetch WebSearch \
        --plugin-dir "$REVIEW_PLUGIN_ROOT" \
        --agent "$REVIEW_AGENT" \
        --output-format json \
        --max-turns "$REVIEW_TURNS" \
        --max-budget-usd "$REVIEW_BUDGET" \
        <"$2" >"$3"
  )
}

# review_parse WORK RUN_STATUS NAME: checks the run and the VERDICT line in WORK/out.json;
# writes the review to WORK/review.txt and "verdict<TAB>items<TAB>cost<TAB>duration" to
# WORK/record.tsv. NAME prefixes its messages on stderr.
review_parse() {
  node - "$1" "$2" "$REVIEW_ID_LIST" "$3" <<'NODE' || review_fail "the review did not complete"
const fs = require("fs");
const [work, runStatus, idList, name] = process.argv.slice(2);
const stop = (why) => { console.error(`harness-kit ${name}: ${why}`); process.exit(1); };
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
}
