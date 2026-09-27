#!/usr/bin/env bash
# Tests for check-commits.mjs: protected files need a reason in a commit body, and numbers
# in a commit body need the diff or a "Told:" line.
#
# Every case runs in a temporary git repository with main and a branch "feature". Prints
# one PASS or FAIL line per case and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/plugins/harness-kit/scripts/check-commits.mjs"
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

describe() { printf 'exit %s\n%s' "$STATUS" "$OUT"; }

# new_repo NAME: main has app.txt, scripts/check.sh and .harness/protected-paths (which
# protects scripts/check.sh and everything under fixtures/); "feature" is checked out, with
# no commits of its own yet. Prints its path.
new_repo() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.harness" "$dir/scripts" "$dir/fixtures"
  git -C "$dir" init -q -b main
  printf 'hello\n' >"$dir/app.txt"
  printf 'echo "check: 1 passed"\n' >"$dir/scripts/check.sh"
  printf 'a\n' >"$dir/fixtures/a.json"
  printf '# protected\nscripts/check.sh\nfixtures/\n' >"$dir/.harness/protected-paths"
  git -C "$dir" add -A && git -C "$dir" commit -q -m "main: initial"
  git -C "$dir" checkout -q -b feature
  echo "$dir"
}

# commit DIR MESSAGE: commit everything with MESSAGE (subject, blank line, body).
commit() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }

run() {
  OUT="$(cd "$1" && shift && node "$CHECK" "$@" 2>&1)"
  STATUS=$?
}

# 1. A branch with no commits of its own passes.
dir="$(new_repo empty)"
run "$dir"
if [ "$STATUS" -eq 0 ] && grep -q '^PASS check-commits: no commits from ' <<<"$OUT"; then
  result "check-commits: a branch with no commits passes" yes ""
else
  result "check-commits: a branch with no commits passes" no "$(describe)"
fi

# 2. A protected file changed and named, with a reason, in a body passes; so does a file
# under a protected folder, named in another commit's body.
dir="$(new_repo named)"
printf 'echo "check: 2 passed"\n' >"$dir/scripts/check.sh"
commit "$dir" $'Count two checks\n\nscripts/check.sh: prints the new count, because a second check was added.'
printf 'b\n' >"$dir/fixtures/a.json"
commit "$dir" $'Update the fixture\n\nThe payload changed shape upstream.'
git -C "$dir" commit -q --allow-empty -m $'Reasons\n\nfixtures/a.json (protected): the upstream payload changed shape.'
run "$dir"
if [ "$STATUS" -eq 0 ] && grep -q '^PASS check-commits: 3 commit(s) ' <<<"$OUT"; then
  result "check-commits: protected files named in a body (in any commit on the branch) pass" yes ""
else
  result "check-commits: protected files named in a body (in any commit on the branch) pass" no "$(describe)"
fi

# 3. A protected file changed and not named in any body fails, naming the path, the commit
# that changed it and the fix. Named only in the subject, it is not named. An unprotected
# file needs nothing.
dir="$(new_repo unnamed)"
printf 'echo "check: 2 passed"\n' >"$dir/scripts/check.sh"
printf 'hello\nworld\n' >"$dir/app.txt"
commit "$dir" $'Change scripts/check.sh\n\nThe count moved, so it prints a new line.'
bad="$(git -C "$dir" rev-parse --short=12 HEAD)"
run "$dir"
if [ "$STATUS" -eq 1 ] && grep -q '^FAIL check-commits: 1 finding(s) in the 1 commit(s) ' <<<"$OUT" &&
  grep -qF "(a) scripts/check.sh is protected (.harness/protected-paths) and changed in $bad, but no commit body on the branch names it. Fix:" <<<"$OUT" &&
  ! grep -q 'app.txt' <<<"$OUT"; then
  result "check-commits: a protected file not named in any body fails, naming the path and the commit" yes ""
else
  result "check-commits: a protected file not named in any body fails, naming the path and the commit" no "$(describe)"
fi

# 3b. A file name names the file when no other changed file has that name: alone, or with
# the folders just above it. With folders that are not the end of its path, or when two
# changed files share the name, it does not, and the finding says why.
dir="$(new_repo filename)"
printf 'echo "check: 2 passed"\n' >"$dir/scripts/check.sh"
printf 'b\n' >"$dir/fixtures/a.json"
commit "$dir" $'Count two checks\n\ncheck.sh prints the new count. The payload in fixtures/a.json changed shape upstream.'
run "$dir"
unique="$(describe)"
unique_ok=no
[ "$STATUS" -eq 0 ] && grep -q '^PASS check-commits' <<<"$OUT" && unique_ok=yes
mkdir -p "$dir/tools" && printf 'echo tool\n' >"$dir/tools/check.sh"
printf 'c\n' >"$dir/fixtures/a.json"
git -C "$dir" add -A && git -C "$dir" commit -q -m $'Add a tool\n\nThe payload in other/a.json changed again.'
run "$dir"
if [ "$unique_ok" = yes ] && [ "$STATUS" -eq 1 ] &&
  grep -qF '(a) scripts/check.sh is protected' <<<"$OUT" &&
  grep -qF '(Its file name alone is not enough: 2 changed files are called check.sh.)' <<<"$OUT" &&
  ! grep -qF '(a) fixtures/a.json' <<<"$OUT"; then
  result "check-commits: a file name unique among the changed files names the file; a shared one does not" yes ""
else
  result "check-commits: a file name unique among the changed files names the file; a shared one does not" no \
    "unique: $unique
shared: $(describe)"
fi

dir="$(new_repo wrong-folder)"
printf 'b\n' >"$dir/fixtures/a.json"
commit "$dir" $'Payload\n\nThe payload in other/a.json changed shape upstream.'
run "$dir"
if [ "$STATUS" -eq 1 ] && grep -qF '(a) fixtures/a.json is protected' <<<"$OUT"; then
  result "check-commits: a file name under the wrong folders does not name the file" yes ""
else
  result "check-commits: a file name under the wrong folders does not name the file" no "$(describe)"
fi

# 4. A branch cannot unprotect a file and change it in one go: the list at the merge-base
# counts too. A deleted protected file must be named as well.
dir="$(new_repo unprotect)"
printf '# protected\nfixtures/\n' >"$dir/.harness/protected-paths"
printf 'echo "check: 2 passed"\n' >"$dir/scripts/check.sh"
git -C "$dir" rm -q fixtures/a.json
commit "$dir" $'Tidy\n\nA smaller list.'
run "$dir"
if [ "$STATUS" -eq 1 ] && grep -qF '(a) scripts/check.sh is protected' <<<"$OUT" &&
  grep -qF '(a) fixtures/a.json is protected' <<<"$OUT"; then
  result "check-commits: a file protected at the merge-base, or deleted, still needs a reason" yes ""
else
  result "check-commits: a file protected at the merge-base, or deleted, still needs a reason" no "$(describe)"
fi

# 5. Numbers in a body: in the diff, or on a "Told:" line (in any body on the branch), they
# pass; otherwise each fails, naming the commit and the number. Names (R1, v0.8.0, 9b-4,
# a hash), the subject and e-mail trailers are not checked.
dir="$(new_repo numbers)"
printf 'hello\nretries = 7\nversion 0.9.0\n' >"$dir/app.txt"
commit "$dir" $'Retry 42 times in the subject\n\nRetries are 7 now, in version 0.9.0; it took 139 runs and 12 minutes to find.\nR1 and C13 pass at v0.8.0 in increment 9b-4 (4c1bc4d).\n- Told: 139 runs, from the CI history on 27 Sep.\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
first="$(git -C "$dir" rev-parse --short=12 HEAD)"
run "$dir"
one="$(describe)"
one_ok=no
if [ "$STATUS" -eq 1 ] && grep -q '^FAIL check-commits: 1 finding(s)' <<<"$OUT" &&
  grep -qF "(b) $first \"Retry 42 times in the subject\": the number 12 is in the body but not in the branch's diff and not on a \"Told:\" line. Fix:" <<<"$OUT"; then
  one_ok=yes
fi
git -C "$dir" commit -q --allow-empty -m $'Sources\n\nTold: 12 minutes, timed by the person.'
run "$dir"
if [ "$one_ok" = yes ] && [ "$STATUS" -eq 0 ] && grep -q '^PASS check-commits: 2 commit(s)' <<<"$OUT"; then
  result "check-commits: a number in a body must be in the diff or on a Told: line; names, subjects and trailers are skipped" yes ""
else
  result "check-commits: a number in a body must be in the diff or on a Told: line; names, subjects and trailers are skipped" no \
    "before the Told: commit: $one
after: $(describe)"
fi

# 6. --warn prints the same findings, under WARN, and exits 0.
dir="$WORK/unnamed"
run "$dir"
failed="$OUT"
run "$dir" --warn
if [ "$STATUS" -eq 0 ] && grep -q '^WARN check-commits: 1 finding(s) .*(--warn: not failing)' <<<"$OUT" &&
  [ "$(grep '^  ' <<<"$OUT")" = "$(grep '^  ' <<<"$failed")" ] && [ -n "$(grep '^  ' <<<"$OUT")" ]; then
  result "check-commits: --warn prints the same findings and exits 0" yes ""
else
  result "check-commits: --warn prints the same findings and exits 0" no "$(describe)
without --warn: $failed"
fi

# 7. The base is .harness/review-base at HEAD: commits already on that base are not the
# branch's, so their messages are not checked.
dir="$(new_repo base)"
git -C "$dir" checkout -q -b develop main
printf 'echo "check: 3 passed"\n' >"$dir/scripts/check.sh"
commit "$dir" $'On develop\n\nNo reason, and 99 bottles.'
git -C "$dir" checkout -q -b topic
printf 'develop\n' >"$dir/.harness/review-base"
commit "$dir" $'Review against develop\n\nThe base is develop.'
run "$dir"
if [ "$STATUS" -eq 0 ] && grep -q '^PASS check-commits: 1 commit(s) from .* (merge-base with develop)' <<<"$OUT"; then
  result "check-commits: only the commits since the merge-base with .harness/review-base are checked" yes ""
else
  result "check-commits: only the commits since the merge-base with .harness/review-base are checked" no "$(describe)"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures check-commits case(s) failed"
  exit 1
fi
