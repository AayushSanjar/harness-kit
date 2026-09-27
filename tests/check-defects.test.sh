#!/usr/bin/env bash
# Tests for plugins/harness-kit/scripts/check-defects.mjs. Each case runs in a temporary
# git repository whose main has .harness/defects.tsv with a header and one defect, D1, and
# a branch "feature" that changes it. Prints one PASS or FAIL line per case and exits
# non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/plugins/harness-kit/scripts/check-defects.mjs"
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

describe() { printf 'exit %s\noutput: %s' "$STATUS" "$OUT"; }

HEADER='# Escaped defects, one per line, tab-separated, append-only
#   date  id  description  where-found  introducing-commit  test-added  fixing-commit'

# new_repo NAME: main with app.txt, then defects.tsv holding D1 (introduced by the first
# commit), and the branch "feature" checked out. Sets INTRO to the first commit. Prints
# nothing; the repository is $WORK/NAME.
new_repo() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.harness"
  git -C "$dir" init -q -b main
  printf 'hello\n' >"$dir/app.txt"
  git -C "$dir" add -A && git -C "$dir" commit -q -m "main: initial"
  INTRO="$(git -C "$dir" rev-parse HEAD)"
  printf '%s\n2026-09-01\tD1\tthe total was off by one\tlive\t%s\ttests/total.test.sh total counts the last day\tthis\n' \
    "$HEADER" "$INTRO" >"$dir/.harness/defects.tsv"
  git -C "$dir" add -A && git -C "$dir" commit -q -m "record D1"
  git -C "$dir" checkout -q -b feature
}

# d2 [WHERE] [INTRO]: a D2 line.
d2() { printf '2026-09-27\tD2\tthe chart lost its last point\t%s\t%s\ttests/chart.test.sh last point drawn\tthis\n' "${1:-review}" "${2:-$INTRO}"; }

run() {
  OUT="$(cd "$WORK/$1" && node "$CHECK" 2>&1)"
  STATUS=$?
}

# 1. No defects.tsv anywhere: nothing to check.
mkdir -p "$WORK/none" && git -C "$WORK/none" init -q -b main && git -C "$WORK/none" commit -q --allow-empty -m init
run none
if [ "$STATUS" -eq 0 ] && grep -q '^PASS check-defects: no .harness/defects.tsv' <<<"$OUT"; then
  result "check-defects: no defects.tsv passes" yes ""
else
  result "check-defects: no defects.tsv passes" no "$(describe)"
fi

# 2. A well-formed line appended on the branch, committed with its fix, passes, and its
# "this" resolves (git blame) to that commit.
new_repo append
d2 >>"$WORK/append/.harness/defects.tsv"
printf 'hello, fixed\n' >"$WORK/append/app.txt"
git -C "$WORK/append" commit -q -am "fix the chart; record D2"
fix="$(git -C "$WORK/append" rev-parse HEAD)"
run append
if [ "$STATUS" -eq 0 ] && grep -q '^PASS check-defects: .harness/defects.tsv keeps its 3 line(s)' <<<"$OUT" &&
  grep -qF "the 1 line(s) added since are well formed (D2: \"this\" is ${fix:0:12})" <<<"$OUT"; then
  result "check-defects: an appended well-formed line passes" yes ""
else
  result "check-defects: an appended well-formed line passes" no "$(describe)"
fi

# 3. An edited line fails, naming the line and what it was.
new_repo edited
sed -i.bak 's/off by one/off by two/' "$WORK/edited/.harness/defects.tsv" && rm "$WORK/edited/.harness/defects.tsv.bak"
git -C "$WORK/edited" commit -q -am "reword D1"
run edited
if [ "$STATUS" -eq 1 ] && grep -q '^FAIL check-defects: 1 finding' <<<"$OUT" &&
  grep -q '(a) line 3 as of the merge-base [0-9a-f]* with main was changed' <<<"$OUT" &&
  grep -q 'now: 2026-09-01	D1	the total was off by two' <<<"$OUT"; then
  result "check-defects: an edited line fails" yes ""
else
  result "check-defects: an edited line fails" no "$(describe)"
fi

# 4. A removed line fails, and so does a line inserted above an old one.
new_repo removed
sed -i.bak '/D1/d' "$WORK/removed/.harness/defects.tsv" && rm "$WORK/removed/.harness/defects.tsv.bak"
d2 >>"$WORK/removed/.harness/defects.tsv"
git -C "$WORK/removed" commit -q -am "drop D1"
run removed
out1="$OUT" s1=$STATUS
new_repo inserted
{ head -n 2 "$WORK/inserted/.harness/defects.tsv"; d2; tail -n 1 "$WORK/inserted/.harness/defects.tsv"; } >"$WORK/inserted.tsv"
mv "$WORK/inserted.tsv" "$WORK/inserted/.harness/defects.tsv"
git -C "$WORK/inserted" commit -q -am "D2 above D1"
run inserted
if [ "$s1" -eq 1 ] && grep -q '(a) line 3 .* was changed' <<<"$out1" && [ "$STATUS" -eq 1 ] && grep -q '(a) line 3' <<<"$OUT"; then
  result "check-defects: a removed line, or one inserted above an old line, fails" yes ""
else
  result "check-defects: a removed line, or one inserted above an old line, fails" no "removed: exit $s1 $out1
inserted: $(describe)"
fi

# 5. The whole file deleted fails as removed lines.
new_repo deleted
git -C "$WORK/deleted" rm -q .harness/defects.tsv && git -C "$WORK/deleted" commit -q -m "no defects"
run deleted
if [ "$STATUS" -eq 1 ] && grep -q '(a) line 1 .* was removed' <<<"$OUT"; then
  result "check-defects: deleting the file fails" yes ""
else
  result "check-defects: deleting the file fails" no "$(describe)"
fi

# 6. An uncommitted edit fails at once (the working tree is read), on main too.
new_repo uncommitted
git -C "$WORK/uncommitted" checkout -q main
sed -i.bak 's/	live	/	person	/' "$WORK/uncommitted/.harness/defects.tsv" && rm "$WORK/uncommitted/.harness/defects.tsv.bak"
run uncommitted
if [ "$STATUS" -eq 1 ] && grep -q '(a) line 3 .* was changed' <<<"$OUT"; then
  result "check-defects: an uncommitted edit fails, on main too" yes ""
else
  result "check-defects: an uncommitted edit fails, on main too" no "$(describe)"
fi

# 7. An appended line that is not in the format fails with each problem: where-found not
# one of the four, a commit that does not exist, a repeated id, too few fields.
new_repo malformed
{
  d2 prod deadbeefdeadbeef
  printf '2026-09-27\tD1\tagain\tcheck\tunknown\ttests/x.test.sh x\tthis\n'
  printf '2026-09-27\tD3\tshort line\n'
} >>"$WORK/malformed/.harness/defects.tsv"
run malformed
if [ "$STATUS" -eq 1 ] && grep -q '^FAIL check-defects: 3 finding' <<<"$OUT" &&
  grep -q '(b) line 4 (D2): where-found is "prod", not one of live, review, check, person; introducing-commit deadbeefdeadbeef is not a commit in this repository' <<<"$OUT" &&
  grep -q '(b) line 5 (D1): the id D1 is used by an earlier line' <<<"$OUT" &&
  grep -q '(b) line 6 (D3): it has 3 tab-separated fields, not 7' <<<"$OUT"; then
  result "check-defects: a malformed appended line fails, naming each problem" yes ""
else
  result "check-defects: a malformed appended line fails, naming each problem" no "$(describe)"
fi

# 8. "this" resolved with git: a line committed on its own resolves to a commit that
# changes only defects.tsv, which holds no fix, so it fails; an uncommitted "this" passes.
new_repo alone
d2 >>"$WORK/alone/.harness/defects.tsv"
run alone
out1="$OUT" s1=$STATUS
git -C "$WORK/alone" commit -q -am "record D2 alone"
alone="$(git -C "$WORK/alone" rev-parse HEAD)"
run alone
if [ "$s1" -eq 0 ] && grep -q '^PASS' <<<"$out1" && [ "$STATUS" -eq 1 ] &&
  grep -qF "(b) line 4 (D2): fixing-commit \"this\" resolves to ${alone:0:12}, which changes only .harness/defects.tsv, so it holds no fix" <<<"$OUT"; then
  result "check-defects: \"this\" resolves with git; a commit holding only the line fails, an uncommitted line passes" yes ""
else
  result "check-defects: \"this\" resolves with git; a commit holding only the line fails, an uncommitted line passes" no "uncommitted: exit $s1 $out1
committed: $(describe)"
fi

# 9. --resolve, for readers: each "this" becomes the commit that added its line, or
# "uncommitted"; every other line is printed as it is.
new_repo resolve
record_d1="$(git -C "$WORK/resolve" rev-parse main)"
d2 >>"$WORK/resolve/.harness/defects.tsv"
OUT="$(cd "$WORK/resolve" && node "$CHECK" --resolve 2>&1)"
STATUS=$?
if [ "$STATUS" -eq 0 ] && [ "$(sed -n 1,2p <<<"$OUT")" = "$HEADER" ] &&
  [ "$(sed -n 3p <<<"$OUT" | cut -f7)" = "$record_d1" ] && [ "$(sed -n 3p <<<"$OUT" | cut -f1-6)" = "$(sed -n 3p "$WORK/resolve/.harness/defects.tsv" | cut -f1-6)" ] &&
  [ "$(sed -n 4p <<<"$OUT" | cut -f7)" = uncommitted ]; then
  result "check-defects --resolve: \"this\" becomes the commit that added the line, or uncommitted" yes ""
else
  result "check-defects --resolve: \"this\" becomes the commit that added the line, or uncommitted" no "$(describe)
record D1: $record_d1"
fi

[ "$failures" -eq 0 ]
