#!/usr/bin/env bash
# Tests for plugins/harness-kit/scripts/harness-metrics.mjs. Each case runs in a temporary
# git repository whose tag pre-harness is a commit dated 2026-09-10T12:00:00Z, with a FAKE
# `gh` first on PATH: it records its arguments and prints the runs in $FAKE_GH_RUNS, or
# fails when FAKE_GH_FAIL is set (not logged in), or FAKE_GH_MODE is timeout (a network
# error, exit 1) or garbage (an HTML error page, exit 0). Nothing touches GitHub. Prints one PASS or FAIL line per
# case and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METRICS="$ROOT/plugins/harness-kit/scripts/harness-metrics.mjs"
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
failures=0

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

describe() { printf 'exit %s\noutput:\n%s\ngh calls:\n%s' "$STATUS" "$OUT" "$(cat "$GH_LOG" 2>/dev/null)"; }

mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_GH_LOG"
if [ -n "${FAKE_GH_FAIL:-}" ]; then
  echo "To get started with GitHub CLI, please run:  gh auth login" >&2
  exit 4
fi
case "${FAKE_GH_MODE:-}" in
  timeout) echo "error connecting to api.github.com: dial tcp: i/o timeout" >&2; exit 1 ;;
  garbage) echo "<html><body>502 Bad Gateway</body></html>"; exit 0 ;;
esac
cat "$FAKE_GH_RUNS"
FAKE
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"
GH_LOG="$WORK/gh-calls"
export FAKE_GH_LOG="$GH_LOG"

HEADER='# Escaped defects, one per line, tab-separated, append-only'

# The runs: feat-a's first commit (a1) is red in one workflow, feat-b's is green, feat-c's
# is still running, and main's runs do not count. old and old2 started before the tag.
cat >"$WORK/runs.json" <<'JSON'
[
  {"databaseId": 1, "headBranch": "main", "headSha": "m1", "status": "completed", "conclusion": "failure", "createdAt": "2026-09-11T00:00:00Z", "workflowName": "validate"},
  {"databaseId": 4, "headBranch": "feat-a", "headSha": "a2", "status": "completed", "conclusion": "success", "createdAt": "2026-09-13T11:00:00Z", "workflowName": "validate"},
  {"databaseId": 3, "headBranch": "feat-a", "headSha": "a1", "status": "completed", "conclusion": "success", "createdAt": "2026-09-12T11:00:05Z", "workflowName": "lint"},
  {"databaseId": 2, "headBranch": "feat-a", "headSha": "a1", "status": "completed", "conclusion": "failure", "createdAt": "2026-09-12T11:00:00Z", "workflowName": "validate"},
  {"databaseId": 5, "headBranch": "feat-b", "headSha": "b1", "status": "completed", "conclusion": "success", "createdAt": "2026-10-01T11:00:00Z", "workflowName": "validate"},
  {"databaseId": 6, "headBranch": "feat-c", "headSha": "c1", "status": "in_progress", "conclusion": "", "createdAt": "2026-10-02T11:00:00Z", "workflowName": "validate"},
  {"databaseId": 7, "headBranch": "old", "headSha": "o1", "status": "completed", "conclusion": "success", "createdAt": "2026-09-08T11:00:00Z", "workflowName": "validate"},
  {"databaseId": 8, "headBranch": "old2", "headSha": "o2", "status": "completed", "conclusion": "failure", "createdAt": "2026-09-01T11:00:00Z", "workflowName": "validate"}
]
JSON
echo '[]' >"$WORK/no-runs.json"
export FAKE_GH_RUNS="$WORK/runs.json"

# new_repo NAME [--no-tag]: a repository with one commit, tagged pre-harness, dated
# 2026-09-10T12:00:00Z. With $AT_TAG_DEFECTS set, .harness/defects.tsv (holding D1, dated
# before the tag) is in that commit.
new_repo() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.harness"
  git -C "$dir" init -q -b main
  printf 'hello\n' >"$dir/app.txt"
  if [ -n "${AT_TAG_DEFECTS:-}" ]; then
    printf '%s\n2026-09-05\tD1\tthe old total was off\tlive\tunknown\ttests/t.sh total\tabc1234\n' "$HEADER" >"$dir/.harness/defects.tsv"
  fi
  git -C "$dir" add -A
  GIT_AUTHOR_DATE=2026-09-10T12:00:00Z GIT_COMMITTER_DATE=2026-09-10T12:00:00Z git -C "$dir" commit -q -m "before the harness"
  [ "${2:-}" = --no-tag ] || git -C "$dir" tag pre-harness
}

# fill NAME: the records after the tag (working tree, uncommitted): defects D2 (on the
# tag's day), D3 and a malformed line; reviews of old (before the tag), feat-a (FIX-FIRST,
# then PASS) and feat-b (PASS, in October); a checklist; three planted faults; and the local
# event log: a full replay before the tag, one after it (2 KILLED, 1 SURVIVED) and a later
# partial one; land.sh and ship.sh lines for old (before the tag), feat-a (a land.sh stop,
# LANDED, a ship.sh stop, SHIPPED) and feat-b (a ship.sh refusal, SHIPPED); a malformed line.
fill() {
  local h="$WORK/$1/.harness" log="$WORK/$1/.git/harness-kit"
  mkdir -p "$log"
  printf '%s\t%s\t%s\th\t%s\t%s\t%s\n' \
    2026-09-08T09:00:00Z replay-faults.sh main REPLAYED killed=0,survived=3,error=0 all \
    2026-09-08T09:10:00Z land.sh old STOPPED check-failed "the check failed (exit 1)" \
    2026-09-12T09:00:00Z land.sh feat-a STOPPED check-failed "the check failed (exit 1)" \
    2026-09-12T09:30:00Z land.sh feat-a LANDED - /tmp/a.patch \
    2026-09-12T10:30:00Z ship.sh feat-a STOPPED ci-not-green "CI run 1 finished with conclusion failure" \
    2026-09-13T11:00:00Z replay-faults.sh feat-a REPLAYED killed=2,survived=1,error=0 all \
    2026-09-13T12:00:00Z ship.sh feat-a SHIPPED main "merged into main" \
    2026-10-01T09:00:00Z ship.sh feat-b STOPPED refused-uncommitted "REFUSED: there are uncommitted changes" \
    2026-10-01T09:05:00Z replay-faults.sh feat-b REPLAYED killed=1,survived=0,error=0 "ids: m1" \
    2026-10-01T10:00:00Z ship.sh feat-b SHIPPED main "merged into main" >"$log/events.tsv"
  printf 'not an event\n' >>"$log/events.tsv"
  [ -f "$h/defects.tsv" ] || printf '%s\n' "$HEADER" >"$h/defects.tsv"
  printf '2026-09-10\tD2\tsame-day bug\tperson\tunknown\ttests/t.sh a\tthis\n' >>"$h/defects.tsv"
  printf '2026-09-15\tD3\tthe chart lost a point\tlive\tunknown\ttests/t.sh b\tthis\n' >>"$h/defects.tsv"
  printf '2026-09-16\tD4\tmissing fields\n' >>"$h/defects.tsv"
  printf '%s\t%s\tb\th\td\t%s\t%s\t%s\t%s\n' \
    2026-09-08T10:00:00Z old FIX-FIRST R1=F,R2=P 0.4000 50.0 \
    2026-09-12T10:00:00Z feat-a FIX-FIRST R1=P,R2=F 0.5000 100.0 \
    2026-09-13T10:00:00Z feat-a PASS R1=P,R2=P 0.7000 120.0 \
    2026-10-01T10:00:00Z feat-b PASS R1=P,R2=P 0.3000 60.0 >"$h/reviews.tsv"
  printf -- '- R1: every new function has a test\n- R2: no secrets in logs\n' >"$h/review-checklist.md"
  printf '# id\tfile\tfind\treplacement\tcheck\nm1\tapp.txt\thello\tbye\tgreets\nm2\tapp.txt\tx\ty\tz\nm3\tapp.txt\tp\tq\tr\n' >"$h/mutations.tsv"
}

run() {
  local dir="$1"
  shift
  rm -f "$GH_LOG"
  OUT="$(cd "$WORK/$dir" && node "$METRICS" "$@" 2>&1)"
  STATUS=$?
}

# row ID: the table's line for number ID.
row() { grep -E "^$1 " <<<"$OUT"; }

# 1. Every source present: each number, its source, and the details.
new_repo all
fill all
before="$(git -C "$WORK/all" status --porcelain)"
run all
ok=yes
row 1 | grep -qE '^1 +escaped defects +2 \(live 1, person 1\) +\.harness/defects\.tsv: lines dated from 2026-09-10 on, by where-found; 1 line\(s\) not in the 7-field format were not counted$' || ok=no
row 2 | grep -qE '^2 +planted faults caught +2 of 3 caught \(1 SURVIVED\) +local record, this machine only: the last full replay-faults\.sh run in \.git/harness-kit/events\.tsv dated from 2026-09-10 on \(2026-09-13T11:00:00Z, head h\); 1 line\(s\) not in the 7-field format were not counted; \.harness/mutations\.tsv plants 3 \(planted, not caught\)$' || ok=no
row 3 | grep -qE '^3 +reviews not PASS on the first try +1 of 2 branches; failed: R2 on 1 +\.harness/reviews\.tsv: ' || ok=no
row 4 | grep -qE '^4 +branches whose first CI run was green +1 of 2 branches; 1 still running, not counted +gh run list \(read-only\): every branch but main' || ok=no
row 5a | grep -qE '^5a +review cost and time per branch +\$0\.75 and 140s per branch \(mean of 2\); \$1\.50 in all +\.harness/reviews\.tsv: ' || ok=no
row 5b | grep -qE '^5b +review cost per month +2026-09 \$1\.20, 2026-10 \$0\.30 ' || ok=no
row 6 | grep -qE '^6 +land\.sh and ship\.sh stops per branch +1\.5 per branch \(mean of 2; land\.sh 1, ship\.sh 2\) +local record, this machine only: the STOPPED lines of land\.sh and ship\.sh in \.git/harness-kit/events\.tsv dated from 2026-09-10 on, over the branches with any STOPPED, LANDED or SHIPPED line of land\.sh or ship\.sh; 1 line' || ok=no
grep -qE '^  feat-a +1 +1 +1 +1 +check-failed 1, ci-not-green 1$' <<<"$OUT" || ok=no
grep -qE '^  feat-b +0 +1 +0 +1 +refused-uncommitted 1$' <<<"$OUT" || ok=no
! grep -qE '^  old ' <<<"$OUT" || ok=no
grep -qE '^  feat-a +2026-09-12T10:00:00Z +FIX-FIRST +R2: no secrets in logs$' <<<"$OUT" || ok=no
grep -qE '^  feat-a +a1 +2026-09-12T11:00:00Z +not green: validate failure, lint success$' <<<"$OUT" || ok=no
grep -qE '^  feat-c +c1 +2026-10-02T11:00:00Z +still running$' <<<"$OUT" || ok=no
grep -qE '^  feat-a +2 +\$1\.20 +220s$' <<<"$OUT" || ok=no
grep -q '^harness-metrics: from 2026-09-10T12:00:00.000Z (the tag pre-harness, commit [0-9a-f]\{12\}) to now$' <<<"$OUT" || ok=no
grep -q 'No .harness/baseline.tsv: run harness-metrics.mjs --baseline once' <<<"$OUT" || ok=no
if [ "$STATUS" -eq 0 ] && [ "$ok" = yes ]; then
  result "harness-metrics: every source present, each number with its source" yes ""
else
  result "harness-metrics: every source present, each number with its source" no "$(describe)"
fi

# 2. gh is only asked to list runs (read-only), and nothing is written.
if [ "$(cat "$GH_LOG")" = "run list --limit 1000 --json databaseId,headBranch,headSha,status,conclusion,createdAt,workflowName" ] &&
  [ "$(git -C "$WORK/all" status --porcelain)" = "$before" ]; then
  result "harness-metrics: gh is only asked for run list, and nothing is written" yes ""
else
  result "harness-metrics: gh is only asked for run list, and nothing is written" no "$(describe)
status before: $before
status after: $(git -C "$WORK/all" status --porcelain)"
fi

# 3-8. No source at all: each number is NOT FOUND, never 0.
new_repo none
FAKE_GH_FAIL=1 run none
[ "$STATUS" -eq 0 ] || OUT="exit $STATUS: $OUT"
not_found() {
  local id="$1" label="$2" source="$3"
  if row "$id" | grep -qE "^$id +.* +NOT FOUND +$source" && ! row "$id" | grep -qE ' 0( |$)| 0 of '; then
    result "harness-metrics: $label" yes ""
  else
    result "harness-metrics: $label" no "$(describe)"
  fi
}
not_found 1 "no defects.tsv: escaped defects are NOT FOUND, not 0" '\.harness/defects\.tsv did not exist$'
not_found 2 "no event log: planted faults caught are NOT FOUND, not 0" 'there is no local event log \(\.git/harness-kit/events\.tsv\): nothing has been recorded on this machine; \.harness/mutations\.tsv did not exist$'
not_found 3 "no reviews.tsv: first-try reviews are NOT FOUND, not 0 of 0" '\.harness/reviews\.tsv did not exist$'
not_found 4 "gh failing: first CI runs are NOT FOUND, not 0 of 0" 'gh run list failed: To get started with GitHub CLI'
not_found 5a "no reviews.tsv: review cost and time are NOT FOUND, not 0" '\.harness/reviews\.tsv did not exist$'
not_found 5b "no reviews.tsv: the monthly cost is NOT FOUND, not 0" '\.harness/reviews\.tsv did not exist$'
not_found 6 "no event log: land.sh and ship.sh stops are NOT FOUND, not 0" 'there is no local event log \(\.git/harness-kit/events\.tsv\): nothing has been recorded on this machine$'

# 9. Sources that exist but hold nothing for the period: 0, not NOT FOUND. An empty event
# log gives 0 stops, but number 2 stays NOT FOUND: no replay run is not 0 caught.
new_repo empty
mkdir -p "$WORK/empty/.git/harness-kit" && : >"$WORK/empty/.git/harness-kit/events.tsv"
printf '%s\n' "$HEADER" >"$WORK/empty/.harness/defects.tsv"
: >"$WORK/empty/.harness/reviews.tsv"
printf '# no faults yet\n' >"$WORK/empty/.harness/mutations.tsv"
FAKE_GH_RUNS="$WORK/no-runs.json" run empty
if [ "$STATUS" -eq 0 ] && row 1 | grep -qE '^1 +escaped defects +0 ' &&
  row 2 | grep -qE ' NOT FOUND +local record, this machine only: no replay-faults\.sh run in \.git/harness-kit/events\.tsv dated from 2026-09-10 on; \.harness/mutations\.tsv plants 0 \(planted, not caught\)$' &&
  row 6 | grep -qE '^6 +land\.sh and ship\.sh stops per branch +0 branches +local record, this machine only' &&
  row 3 | grep -qE ' 0 of 0 branches ' && row 4 | grep -qE ' 0 of 0 branches ' && row 5a | grep -qE ' 0 branches ' &&
  row 5b | grep -qE ' 0 months ' && [ "$(grep -c 'NOT FOUND' <<<"$OUT")" = 1 ]; then
  result "harness-metrics: empty sources give 0, not NOT FOUND (an empty event log: 0 stops, no replay run)" yes ""
else
  result "harness-metrics: empty sources give 0, not NOT FOUND (an empty event log: 0 stops, no replay run)" no "$(describe)"
fi

# 10. --since a date and --until a date narrow the period.
run all --since 2026-10-01
out1="$OUT" s1=$STATUS
run all --until 2026-09-30
if [ "$s1" -eq 0 ] && grep -qE '^1 +escaped defects +0 ' <<<"$out1" && grep -qE '^3 .* 0 of 1 branches ' <<<"$out1" &&
  grep -qE '^4 .* 1 of 1 branches; 1 still running' <<<"$out1" && grep -qE '^5b +review cost per month +2026-10 \$0\.30 ' <<<"$out1" &&
  grep -q '^harness-metrics: from 2026-10-01T00:00:00.000Z to now$' <<<"$out1" &&
  grep -qE '^2 +planted faults caught +1 of 1 caught +local record, this machine only: the last replay-faults\.sh run in .* \(2026-10-01T09:05:00Z, head h, ids: m1; no run of every entry in the period\)' <<<"$out1" &&
  grep -qE '^6 .* 1\.0 per branch \(mean of 1; land\.sh 0, ship\.sh 1\) ' <<<"$out1" &&
  [ "$STATUS" -eq 0 ] && row 3 | grep -qE ' 1 of 1 branches; failed: R2 on 1 ' && row 4 | grep -qE ' 0 of 1 branches ' &&
  row 5b | grep -qE ' 2026-09 \$1\.20 ' && grep -q ' to 2026-10-01T00:00:00.000Z$' <<<"$OUT"; then
  result "harness-metrics: --since and --until narrow the period" yes ""
else
  result "harness-metrics: --since and --until narrow the period" no "since: exit $s1
$out1
until: $(describe)"
fi

# 11. .harness/ci-workflow and .harness/review-base: gh is asked for that workflow only,
# and the base's runs are left out.
new_repo wf
printf 'validate\n' >"$WORK/wf/.harness/ci-workflow"
printf 'feat-b\n' >"$WORK/wf/.harness/review-base"
run wf
if [ "$STATUS" -eq 0 ] && grep -q -- '--workflow validate$' "$GH_LOG" &&
  row 4 | grep -qE ' 0 of 2 branches; 1 still running, not counted +gh run list \(read-only, workflow validate from \.harness/ci-workflow\): every branch but feat-b,'; then
  result "harness-metrics: ci-workflow and review-base shape the CI query" yes ""
else
  result "harness-metrics: ci-workflow and review-base shape the CI query" no "$(describe)"
fi

# 12. --baseline: the files at the tag (defects.tsv only), CI runs before the tag, NOT FOUND
# for the rest; written once; the table then shows it.
AT_TAG_DEFECTS=1 new_repo base
fill base
run base --baseline
bl="$WORK/base/.harness/baseline.tsv"
ok=yes
[ "$STATUS" -eq 0 ] || ok=no
grep -qE '^1	1 \(live 1\)	\.harness/defects\.tsv at pre-harness: lines dated before 2026-09-10T12:00:00.000Z' "$bl" || ok=no
grep -qE '^2	NOT FOUND	the local event log is not in git, so the files at the tag hold no record of it; \.harness/mutations\.tsv did not exist at pre-harness$' "$bl" || ok=no
grep -qE '^3	NOT FOUND	\.harness/reviews\.tsv did not exist at pre-harness$' "$bl" || ok=no
grep -qE '^4	1 of 2 branches	gh run list' "$bl" || ok=no
grep -qE '^5a	NOT FOUND	' "$bl" || ok=no
grep -qE '^5b	NOT FOUND	' "$bl" || ok=no
grep -qE '^6	NOT FOUND	the local event log is not in git, so the files at the tag hold no record of it$' "$bl" || ok=no
grep -q '^# harness-kit baseline: the numbers for everything before the tag pre-harness (commit [0-9a-f]\{40\}, 2026-09-10T12:00:00.000Z),$' "$bl" || ok=no
first="$(describe)
baseline.tsv:
$(cat "$bl" 2>/dev/null)"
cp "$bl" "$WORK/baseline.copy" 2>/dev/null
run base --baseline
cmp -s "$bl" "$WORK/baseline.copy" && [ "$STATUS" -eq 1 ] && grep -q 'exists already, and the baseline is written once; nothing was changed' <<<"$OUT" || ok=no
second="$(describe)"
run base
row 1 | grep -qE '^1 +escaped defects +2 \(live 1, person 1\) +1 \(live 1\) +\.harness/defects\.tsv:' || ok=no
row 3 | grep -qE ' 1 of 2 branches; failed: R2 on 1 +NOT FOUND +\.harness/reviews' || ok=no
grep -qE '^# +number +value +baseline +source$' <<<"$OUT" || ok=no
if [ "$ok" = yes ]; then
  result "harness-metrics --baseline: old records or NOT FOUND, written once, then shown" yes ""
else
  result "harness-metrics --baseline: old records or NOT FOUND, written once, then shown" no "first: $first
second: $second
table: $(describe)"
fi

# 13. No tag pre-harness: exit 2 with what to do; --since a date works without it.
new_repo notag --no-tag
run notag
out1="$OUT" s1=$STATUS
run notag --baseline
out2="$OUT" s2=$STATUS
run notag --since 2026-09-01
if [ "$s1" -eq 2 ] && grep -q 'there is no tag pre-harness, the default start; tag the last commit before the harness' <<<"$out1" &&
  [ "$s2" -eq 2 ] && [ ! -e "$WORK/notag/.harness/baseline.tsv" ] && [ "$STATUS" -eq 0 ] && row 6 | grep -q 'NOT FOUND'; then
  result "harness-metrics: no tag pre-harness exits 2 unless --since is given" yes ""
else
  result "harness-metrics: no tag pre-harness exits 2 unless --since is given" no "default: exit $s1 $out1
baseline: exit $s2 $out2
since: $(describe)"
fi

# 14. Usage: an unknown option, a bad date, and --baseline with --since exit 2.
run all --weekly
s1=$STATUS
run all --since 2026-13-01
s2=$STATUS
run all --baseline --since 2026-09-01
if [ "$s1" -eq 2 ] && [ "$s2" -eq 2 ] && [ "$STATUS" -eq 2 ] && [ ! -e "$WORK/all/.harness/baseline.tsv" ]; then
  result "harness-metrics: unknown options, bad dates and --baseline with --since exit 2" yes ""
else
  result "harness-metrics: unknown options, bad dates and --baseline with --since exit 2" no "exits $s1 $s2 $STATUS"
fi

# 15. The header says, for each of the six numbers, what would make it misleading.
count="$(sed -n '1,/^import /p' "$METRICS" | grep -c '^//      Misleading: ')"
if [ "$count" = 6 ]; then
  result "harness-metrics: the header has a Misleading sentence for each of the six numbers" yes ""
else
  result "harness-metrics: the header has a Misleading sentence for each of the six numbers" no "found $count"
fi

# 16. CHECKED lines (a check result, recorded when it changed) count towards no number: the
# same records as case 1 plus CHECKED lines of land.sh, ship.sh, release.sh and the Stop
# hook, one for a branch (feat-z) with no other line, give the same numbers 2 and 6.
new_repo checked
fill checked
printf '%s\t%s\t%s\th\tCHECKED\t%s\t%s\n' \
  2026-09-12T08:00:00Z land.sh feat-a FAIL "exit 1: unit" \
  2026-09-12T08:30:00Z ship.sh feat-a PASS - \
  2026-09-14T08:00:00Z stop-gate.mjs feat-z FAIL "exit 1: lint" \
  2026-09-14T09:00:00Z land.sh feat-z PASS - \
  2026-09-15T08:00:00Z release.sh feat-y PASS - >>"$WORK/checked/.git/harness-kit/events.tsv"
run checked
if [ "$STATUS" -eq 0 ] &&
  row 6 | grep -qE '^6 +land\.sh and ship\.sh stops per branch +1\.5 per branch \(mean of 2; land\.sh 1, ship\.sh 2\) ' &&
  row 2 | grep -qE '^2 +planted faults caught +2 of 3 caught \(1 SURVIVED\) ' && ! grep -qE '^  feat-[yz] ' <<<"$OUT"; then
  result "harness-metrics: CHECKED lines change no number" yes ""
else
  result "harness-metrics: CHECKED lines change no number" no "$(describe)"
fi

# 17-19. gh answers, but not with runs: number 4 is NOT FOUND with the reason, never a count.
new_repo gh-broken
printf '[{"message": "API rate limit exceeded"}, {"databaseId": 5, "headBranch": "feat-b", "headSha": "b1", "status": "completed", "conclusion": "success", "createdAt": "2026-10-01T11:00:00Z", "workflowName": "validate"}]\n' >"$WORK/not-runs.json"
gh_not_found() {
  local label="$1" source="$2"
  if [ "$STATUS" -eq 0 ] && row 4 | grep -qE "^4 +.* +NOT FOUND +$source" && ! row 4 | grep -qE ' [0-9]+ of [0-9]+ '; then
    result "harness-metrics: $label" yes ""
  else
    result "harness-metrics: $label" no "$(describe)"
  fi
}
FAKE_GH_MODE=timeout run gh-broken
gh_not_found "gh timing out: first CI runs are NOT FOUND, not a number" 'gh run list failed: error connecting to api\.github\.com: dial tcp: i/o timeout'
FAKE_GH_MODE=garbage run gh-broken
gh_not_found "gh printing garbage: first CI runs are NOT FOUND, not a number" 'gh run list did not print a JSON list'
FAKE_GH_RUNS="$WORK/not-runs.json" run gh-broken
gh_not_found "a gh list with entries that are not runs: first CI runs are NOT FOUND, not 0 of 0" 'gh run list printed 1 entry that is not a run'

[ "$failures" -eq 0 ]
