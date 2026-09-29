# The local event log, sourced by land.sh, ship.sh, release.sh and replay-faults.sh, and run
# by stop-gate.mjs (the Stop hook) through bash for harness_check_event; harness-metrics.mjs
# and start-picture.mjs (the SessionStart hook's start-up picture) read it. Written for bash
# 3.2 (macOS).
#
# WHERE: <git common dir>/harness-kit/events.tsv, which is .git/harness-kit/events.tsv in a
# normal clone (every worktree of the clone shares it). It is inside .git, so it is never
# committed, pushed, or seen by CI or another clone: a record for this machine only.
#
# THE LINES, appended, one per event, tab-separated (tabs and line breaks in a value become
# spaces):
#   date    UTC, YYYY-MM-DDTHH:MM:SSZ
#   tool    land.sh, ship.sh, release.sh, replay-faults.sh or stop-gate.mjs
#   branch  the branch the tool worked on ("(detached)" on a detached HEAD)
#   head    HEAD's commit when the event was written ("none" before the first commit)
#   event   land.sh: LANDED or STOPPED; ship.sh: SHIPPED or STOPPED; release.sh: RELEASED or
#           STOPPED; replay-faults.sh: REPLAYED; land.sh, ship.sh, release.sh and
#           stop-gate.mjs: CHECKED (harness_check_event, below)
#   what    STOPPED: a short reason, such as check-failed or no-brief (ship.sh's and
#           release.sh's refusals start "refused-"); REPLAYED:
#           "killed=K,survived=S,timeout=T,error=E,baseline=Bs" (B: the baseline's seconds;
#           before v0.16.0, "killed=K,survived=S,error=E");
#           LANDED: "-"; SHIPPED: the base; RELEASED: the tag; CHECKED: PASS or FAIL
#   detail  STOPPED: the message printed after "STOPPED:" or "REFUSED:"; REPLAYED: "all", or
#           "ids:" and the ids asked for; LANDED: the patch's path; SHIPPED and RELEASED: what
#           was merged; CHECKED: PASS "-"; FAIL "exit N: " (or "signal S: ") and the failing
#           checks' names joined by "; ", or "no FAIL lines" when the check printed none
#
# CHECKED lines are written only when the result changes (harness_check_event), so the log
# holds when a branch's check result last changed, not every run.
#
# Writing never changes what the tool does: outside a git repository nothing is written,
# and a failed write prints one note on stderr.

harness_event_field() { printf '%s' "$1" | tr '\t\r\n' '   '; }

# harness_event TOOL BRANCH EVENT WHAT DETAIL: append one line. An empty BRANCH means the
# current one.
harness_event() {
  local tool="$1" branch="$2" common head
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  [ -n "$branch" ] || branch="$(git symbolic-ref --short -q HEAD 2>/dev/null || echo "(detached)")"
  head="$(git rev-parse -q --verify HEAD 2>/dev/null || echo none)"
  if ! { mkdir -p "$common/harness-kit" &&
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tool" \
      "$(harness_event_field "$branch")" "$head" "$3" "$(harness_event_field "$4")" "$(harness_event_field "$5")" \
      >>"$common/harness-kit/events.tsv"; } 2>/dev/null; then
    echo "harness-kit $tool: note: could not append to $common/harness-kit/events.tsv" >&2
  fi
  return 0
}

# harness_check_names: the failing checks' names in a check's output on stdin, one per
# line, in order: each line starting with the word FAIL (after any spaces), without that
# word and what follows it up to the name (spaces, or one ":" or other punctuation), with
# tabs and carriage returns made spaces. Empty names are dropped.
harness_check_names() {
  tr '\t\r' '  ' | sed -nE 's/^[[:space:]]*FAIL($|[^[:alnum:]_])[[:space:]]*//p' | sed -E 's/[[:space:]]+$//' | grep -v '^$'
}

# harness_check_set: the set of names on stdin (one per line), as sorted unique lines: the
# form two results are compared in, so the order of the names does not matter.
harness_check_set() { LC_ALL=C sort -u; }

# harness_check_event TOOL BRANCH STATUS: record one run of the project's check, its output
# (stdout and stderr) on stdin. STATUS is its exit status, or "signal S" when a signal ended
# it; 0 is PASS, anything else FAIL. An empty BRANCH means the current one.
#
# A line is appended only when the result differs from the latest CHECKED line for the same
# branch, whichever tool wrote it: PASS after FAIL, FAIL after PASS, or FAIL with a
# different set of failing checks (the names' order, and the exit status, are not
# compared). A branch with no CHECKED line gets one. As with harness_event, nothing is
# written outside a git repository, and a failed write prints one note on stderr.
harness_check_event() {
  local tool="$1" branch="$2" status="$3" common log names what detail prefix last_what last_detail
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { cat >/dev/null; return 0; }
  [ -n "$branch" ] || branch="$(git symbolic-ref --short -q HEAD 2>/dev/null || echo "(detached)")"
  branch="$(harness_event_field "$branch")"
  names="$(harness_check_names)"
  if [ "$status" = 0 ]; then
    what=PASS
    detail=-
  else
    what=FAIL
    case "$status" in *[!0-9]*) prefix="$status" ;; *) prefix="exit $status" ;; esac
    if [ -n "$names" ]; then
      detail="$prefix: $(printf '%s\n' "$names" | awk 'NR > 1 { printf "; " } { printf "%s", $0 }')"
    else
      detail="$prefix: no FAIL lines"
    fi
  fi
  log="$common/harness-kit/events.tsv"
  if [ -f "$log" ]; then
    last_what="$(awk -F'\t' -v b="$branch" '$3 == b && $5 == "CHECKED" { w = $6 } END { print w }' "$log" 2>/dev/null)"
    last_detail="$(awk -F'\t' -v b="$branch" '$3 == b && $5 == "CHECKED" { d = $7 } END { print d }' "$log" 2>/dev/null)"
    if [ "$last_what" = "$what" ]; then
      [ "$what" = PASS ] && return 0
      [ "$(harness_check_detail_set "$last_detail")" = "$(harness_check_detail_set "$detail")" ] && return 0
    fi
  fi
  harness_event "$tool" "$branch" CHECKED "$what" "$detail"
}

# harness_check_detail_set DETAIL: the set of failing checks a FAIL line's detail names:
# the text after the first ": ", split at "; " ("no FAIL lines" is the empty set).
harness_check_detail_set() {
  local names="${1#*: }"
  [ "$names" != "no FAIL lines" ] || return 0
  printf '%s\n' "$names" | awk '{ n = split($0, a, "; "); for (i = 1; i <= n; i++) print a[i] }' | harness_check_set
}
