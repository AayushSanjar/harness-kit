# The local event log, sourced by land.sh, ship.sh, release.sh and replay-faults.sh;
# harness-metrics.mjs reads it. Written for bash 3.2 (macOS).
#
# WHERE: <git common dir>/harness-kit/events.tsv, which is .git/harness-kit/events.tsv in a
# normal clone (every worktree of the clone shares it). It is inside .git, so it is never
# committed, pushed, or seen by CI or another clone: a record for this machine only.
#
# THE LINES, appended, one per event, tab-separated (tabs and line breaks in a value become
# spaces):
#   date    UTC, YYYY-MM-DDTHH:MM:SSZ
#   tool    land.sh, ship.sh, release.sh or replay-faults.sh
#   branch  the branch the tool worked on ("(detached)" on a detached HEAD)
#   head    HEAD's commit when the event was written ("none" before the first commit)
#   event   land.sh: LANDED or STOPPED; ship.sh: SHIPPED or STOPPED; release.sh: RELEASED or
#           STOPPED; replay-faults.sh: REPLAYED
#   what    STOPPED: a short reason, such as check-failed or no-brief (ship.sh's and
#           release.sh's refusals start "refused-"); REPLAYED: "killed=K,survived=S,error=E";
#           LANDED: "-"; SHIPPED: the base; RELEASED: the tag
#   detail  STOPPED: the message printed after "STOPPED:" or "REFUSED:"; REPLAYED: "all", or
#           "ids:" and the ids asked for; LANDED: the patch's path; SHIPPED and RELEASED: what
#           was merged
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
