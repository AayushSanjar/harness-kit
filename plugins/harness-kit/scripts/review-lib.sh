# Shared by review.sh and eval-reviewer.sh, which source it: reading the checklist and
# review-reads, building the reviewer's input, running the reviewer headless within the
# turn and budget limits, and checking what it returns. Written for bash 3.2 (macOS).
#
# Each function returns 1 on failure with the reason in REVIEW_ERROR; the caller decides
# what failing means (review.sh exits, eval-reviewer.sh grades the run ERROR).
#
# Limits, from the environment: REVIEW_MAX_TURNS (default 40), REVIEW_MAX_BUDGET_USD
# (default 3.00) and REVIEW_MAX_INPUT_BYTES (default 250000; see review_build_input).

REVIEW_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REVIEW_AGENT="harness-kit:reviewer"
REVIEW_TURNS="${REVIEW_MAX_TURNS:-40}"
REVIEW_BUDGET="${REVIEW_MAX_BUDGET_USD:-3.00}"
REVIEW_MAX_INPUT="${REVIEW_MAX_INPUT_BYTES:-250000}"
REVIEW_MAX_CHECK_LINES=3000
REVIEW_ERROR=""
REVIEW_ID_LIST=""
REVIEW_READS=()
REVIEW_READ_SOURCES=()
# A file holding the body of the BRIEF section (review.sh sets it, from brief-lib.sh's
# brief_review_section); empty, as in eval-reviewer.sh, means the input has no BRIEF section.
REVIEW_BRIEF_SECTION=""

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

# review_check_reads [--missing-ok]: fails if a review-reads file does not exist. With
# --missing-ok (eval mode only: a historical head can predate a file) a missing file is not
# an error; its source is emptied and review_build_input says it is not present.
review_check_reads() {
  local missing_ok="${1:-}" i=0
  while [ "$i" -lt "${#REVIEW_READS[@]}" ]; do
    if [ ! -f "${REVIEW_READ_SOURCES[$i]}" ]; then
      [ "$missing_ok" = --missing-ok ] ||
        review_fail ".harness/review-reads names ${REVIEW_READS[$i]}, which does not exist" || return 1
      REVIEW_READ_SOURCES[$i]=""
    fi
    i=$((i + 1))
  done
}

# review_check_section H WORK: runs the project's check command from the current folder and
# prints the body of the CHECK COMMAND section: the command, its exit status and its output.
review_check_section() {
  local h="$1" work="$2" check="" check_status
  [ -f "$h/check-command" ] && check="$(head -n 1 "$h/check-command" | tr -d '\r')"
  if [ -z "$check" ]; then
    echo "none: the project has no .harness/check-command, so no check was run"
    return 0
  fi
  echo "Running the check command..." >&2
  /bin/sh -c 'exec 2>&1; eval "$1"' harness-kit-review "$check" </dev/null >"$work/check.out"
  check_status=$?
  review_format_check "$check" "$check_status" "$work/check.out"
}

# review_saved_check H SAVED: prints the body of the CHECK COMMAND section from the check
# run ship.sh saved in the folder SAVED (files command, status, head, tree and output, as
# ship.sh writes them) and returns 0, when that run is this one's: the same first line of
# H/check-command, the same HEAD, and the same `git status --porcelain` (untracked files
# included). Otherwise it prints nothing and returns 1, and the caller runs the check.
review_saved_check() {
  local h="$1" saved="$2" check="" f
  [ -n "$saved" ] || return 1
  for f in command status head tree output; do [ -f "$saved/$f" ] || return 1; done
  [ -f "$h/check-command" ] && check="$(head -n 1 "$h/check-command" | tr -d '\r')"
  [ -n "$check" ] && [ "$check" = "$(cat "$saved/command")" ] || return 1
  [ "$(git rev-parse -q --verify HEAD)" = "$(cat "$saved/head")" ] || return 1
  [ "$(git status --porcelain --untracked-files=all)" = "$(cat "$saved/tree")" ] || return 1
  review_format_check "$check" "$(cat "$saved/status")" "$saved/output" \
    "reused: ship.sh ran this command just before starting the review, at this head and working tree; this is that run's output (the check was not run again)"
}

# review_format_check COMMAND STATUS OUTPUT [NOTE]: the CHECK COMMAND section's body.
review_format_check() {
  local total
  echo "command: $1"
  [ -z "${4:-}" ] || echo "$4"
  echo "exit status: $2"
  total="$(wc -l <"$3" | tr -d ' ')"
  if [ "$total" -gt "$REVIEW_MAX_CHECK_LINES" ]; then
    echo "output (last $REVIEW_MAX_CHECK_LINES of $total lines; $((total - REVIEW_MAX_CHECK_LINES)) earlier lines omitted):"
    tail -n "$REVIEW_MAX_CHECK_LINES" "$3"
  else
    echo "output:"
    cat "$3"
  fi
}

# review_build_input OUT PROJECT BRANCH BASE_REF MERGE_BASE HEAD CHECKLIST CHECK_SECTION
# [CHECKLIST_SHOWN]: writes the reviewer's whole input to OUT. CHECK_SECTION is a file
# holding the body of the CHECK COMMAND section. The checklist is copied from CHECKLIST;
# the input names it as CHECKLIST_SHOWN (default CHECKLIST), the copy the reviewer can
# Read. Uses REVIEW_ID_LIST, REVIEW_READS and REVIEW_READ_SOURCES (an empty source, left
# by review_check_reads --missing-ok, is shown as not present), and REVIEW_BRIEF_SECTION:
# when set, a BRIEF section (the branch's brief and whether its approval matches) follows
# the CHECKLIST.
#
# THE SIZE GUARD. The built input must be at most REVIEW_MAX_INPUT bytes, or this fails
# naming the largest parts, before any claude call. The default, 250000 bytes, comes from
# the models overview (platform.claude.com/docs/en/about-claude/models/overview, read
# 2026-09-27): the smallest "Context window" of a current model is "200K tokens" (Claude
# Haiku 4.5; the others are "1M tokens"), and "1M tokens is roughly 555k words or 2.5M
# Unicode characters on the current tokenizer", so 200K tokens is about 500000 characters.
# The input gets half of that; the other half is left for the system prompt, the agent's
# instructions, the files the reviewer Reads, its thinking and its answer. Bytes are
# counted, not characters, which only errs small. The reviewer's model is the person's
# default, so the smallest window is the safe one; raise REVIEW_MAX_INPUT_BYTES for a
# model with a larger window.
review_build_input() {
  local out="$1" project="$2" branch="$3" base_ref="$4" merge_base="$5" head="$6" checklist="$7" check_section="$8" i=0 size
  local checklist_shown="${9:-$7}"
  {
    echo "=== REVIEW ==="
    echo "project:     $project"
    echo "branch:      $branch"
    echo "base:        $base_ref"
    echo "merge-base:  $merge_base"
    echo "head:        $head"
    echo "checklist:   $checklist_shown"
    echo "item IDs:    $REVIEW_ID_LIST"
    echo
    echo "=== CHECKLIST ==="
    cat "$checklist"
    echo
    if [ -n "$REVIEW_BRIEF_SECTION" ]; then
      echo "=== BRIEF ==="
      cat "$REVIEW_BRIEF_SECTION"
      echo
    fi
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
    review_diff "$project" "$merge_base" "$head"
    while [ "$i" -lt "${#REVIEW_READS[@]}" ]; do
      echo
      echo "=== READ: ${REVIEW_READS[$i]} ==="
      if [ -n "${REVIEW_READ_SOURCES[$i]}" ]; then
        cat "${REVIEW_READ_SOURCES[$i]}"
      else
        echo "${REVIEW_READS[$i]}: not present at this commit"
      fi
      i=$((i + 1))
    done
  } >"$out" || review_fail "could not build the reviewer's input" || return 1
  case "$REVIEW_MAX_INPUT" in "" | *[!0-9]* | 0*) review_fail "REVIEW_MAX_INPUT_BYTES must be a whole number of 1 or more, not \"$REVIEW_MAX_INPUT\"" || return 1 ;; esac
  size="$(wc -c <"$out" | tr -d ' ')"
  [ "$size" -le "$REVIEW_MAX_INPUT" ] ||
    review_fail "the reviewer's input is $size bytes, over the limit of $REVIEW_MAX_INPUT (REVIEW_MAX_INPUT_BYTES), so claude was not started. The largest parts: $(review_largest "$out"). Split the branch into smaller branches and review each" || return 1
  # Piped stdin is capped at 10 MB (code.claude.com/docs/en/headless).
  [ "$size" -le 10000000 ] || review_fail "the reviewer's input is over 10 MB; review a smaller branch" || return 1
}

# review_diff PROJECT MERGE_BASE HEAD: the DIFF section's body, without .harness/reviews.tsv.
# A deleted file is one line, "deleted: <path> (<N> lines)" ("(binary)" for a binary file),
# never its content; a renamed file is "renamed: <old> -> <new>", and any change to its
# content follows in the diff. Added and modified files keep their full diff, which is
# unchanged when nothing was deleted or renamed.
review_diff() {
  local project="$1" from="$2" to="$3" added removed path status old new
  local diff=(git -C "$project" diff --no-color --no-ext-diff -M)
  local paths=(-- . ':(exclude).harness/reviews.tsv')
  "${diff[@]}" -z --numstat --diff-filter=D "$from" "$to" "${paths[@]}" |
    while IFS=$'\t' read -r -d '' added removed path; do
      if [ "$added" = - ]; then echo "deleted: $path (binary)"; else echo "deleted: $path ($removed lines)"; fi
    done
  "${diff[@]}" -z --name-status --diff-filter=R "$from" "$to" "${paths[@]}" |
    while IFS= read -r -d '' status && IFS= read -r -d '' old && IFS= read -r -d '' new; do
      echo "renamed: $old -> $new"
    done
  "${diff[@]}" --diff-filter=d "$from" "$to" "${paths[@]}"
}

# review_largest INPUT: the five largest parts of a built input, largest first, as
# "<part> (<N> bytes)": each file's diff by its path, each READ file, and each other
# section by its name.
review_largest() {
  LC_ALL=C awk '
    /^=== (REVIEW|CHECKLIST|BRIEF|CHECK COMMAND|GIT LOG|GIT STATUS) ===$/ && !inread { key = "the " substr($0, 5, length($0) - 8) " section"; next }
    /^=== DIFF ===$/ && !inread { key = "the deleted and renamed lines"; diff = 1; next }
    /^=== READ: .* ===$/ { key = "READ: " substr($0, 11, length($0) - 14); inread = 1; diff = 0; next }
    diff && /^diff --git / { key = $0; sub(/.* b\//, "", key) }
    { size[key] += length($0) + 1 }
    END { for (k in size) printf "%d\t%s\n", size[k], k }
  ' "$1" | sort -rn | head -n 5 | awk -F'\t' '{ printf "%s%s (%d bytes)", (NR > 1 ? ", " : ""), $2, $1 }'
}

# review_run DIR INPUT OUT [--stream]: runs the reviewer headless in DIR on INPUT, within
# the limits; returns claude's exit status. OUT gets the result JSON, or with --stream the
# whole stream-json transcript, one event per line, the result event last.
review_run() {
  local format=(--output-format json)
  [ "${4:-}" = --stream ] && format=(--output-format stream-json --verbose)
  (
    cd "$1" &&
      claude -p "Review this branch. Your whole input follows: judge it as your instructions say, and end with the VERDICT line." \
        --disallowedTools Write Edit NotebookEdit Bash WebFetch WebSearch \
        --plugin-dir "$REVIEW_PLUGIN_ROOT" \
        --agent "$REVIEW_AGENT" \
        "${format[@]}" \
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
