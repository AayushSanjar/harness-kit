#!/usr/bin/env bash
# Tests for check-commits.mjs: protected files need a reason in a commit body, numbers in
# a commit body need the diff or a "Told:" line (which continues onto the lines after it),
# replay snapshot commits are exempt in a replay (HARNESS_KIT_REPLAY=1) only, commit
# references (7 or more digits) and "v" versions are not unsourced numbers, a "Decision:"
# line must not name a path in .harness/removed-paths, and --message (the commit-msg
# hook's check) judges one new message against the staged changes and the branch so far.
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
unset HARNESS_KIT_REPLAY

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

# 8. A "Told:" line continues onto the lines after it until a blank line or another
# "Word:" line: a number on a continuation line is sourced, and sources others; one after a
# "Breaks:" line or a blank line is not.
dir="$(new_repo told-continues)"
printf 'hello\nretries = 7\n' >"$dir/app.txt"
commit "$dir" $'Retry more\n\nRetries are 7 now; 14 runs failed before, the last on 27 Sep.\n- Told: 14 runs failed before the change,\n  counted in the CI history of 27 Sep.\nBreaks: fails below 99 retries.\n\nAlso 55 more.'
run "$dir"
if [ "$STATUS" -eq 1 ] && grep -q '^FAIL check-commits: 2 finding(s)' <<<"$OUT" &&
  grep -qF 'the number 99 is in the body' <<<"$OUT" && grep -qF 'the number 55 is in the body' <<<"$OUT" &&
  ! grep -qF 'the number 27 ' <<<"$OUT" && ! grep -qF 'the number 14 ' <<<"$OUT"; then
  result "check-commits: a Told: line continues until a blank line or another Word: line" yes ""
else
  result "check-commits: a Told: line continues until a blank line or another Word: line" no "$(describe)"
fi

# 9. A replay snapshot (a commit whose message starts "harness-kit replay-faults:", as
# replay-faults.sh makes) at the tip is exempt only in a replay, with HARNESS_KIT_REPLAY=1
# (which replay-faults.sh sets): its message is not checked and what it changes needs no
# reason, so the branch passes as it was before it. Without HARNESS_KIT_REPLAY=1 (a real
# branch, CI), the same commit is checked like any other and fails.
dir="$(new_repo snapshot)"
git -C "$dir" commit -q --allow-empty -m $'Notes\n\nNothing protected changed.'
printf 'echo "check: 2 passed"\n' >"$dir/scripts/check.sh"
git -C "$dir" add -A
git -C "$dir" commit -q -m $'harness-kit replay-faults: the working tree\n\n42 things.'
HARNESS_KIT_REPLAY=1 run "$dir"
replay="$(describe)"
replay_ok=no
[ "$STATUS" -eq 0 ] && grep -q '^PASS check-commits: 1 commit(s) .* (1 replay snapshot commit(s) skipped)' <<<"$OUT" && replay_ok=yes
run "$dir"
if [ "$replay_ok" = yes ] && [ "$STATUS" -eq 1 ] && grep -q '^FAIL check-commits: 2 finding(s) in the 2 commit(s)' <<<"$OUT" &&
  grep -qF '(a) scripts/check.sh is protected' <<<"$OUT" && grep -qF 'the number 42 is in the body' <<<"$OUT"; then
  result "check-commits: a replay-faults snapshot commit is exempt only with HARNESS_KIT_REPLAY=1" yes ""
else
  result "check-commits: a replay-faults snapshot commit is exempt only with HARNESS_KIT_REPLAY=1" no "with HARNESS_KIT_REPLAY=1: $replay
without: $(describe)"
fi

# 10. A run of 7 or more digits that git resolves to a commit is a reference, not a number:
# a commit whose short hash is all digits is made (new messages until one is), then named
# in a body. Its first 6 digits, which git also resolves to it, are still a number.
dir="$(new_repo digit-hash)"
i=0
digits=""
while [ "$i" -lt 2000 ]; do
  h="$(git -C "$dir" commit-tree "HEAD^{tree}" -p HEAD -m "Try $i" </dev/null)"
  case "${h:0:7}" in *[!0-9]*) ;; *) digits="${h:0:7}"; break ;; esac
  i=$((i + 1))
done
git -C "$dir" update-ref HEAD "$h"
short="${digits:0:6}"
git -C "$dir" commit -q --allow-empty -m "Revert" -m "Reverts $digits; 9999999 is not a commit; $short is too short."
resolves=no
git -C "$dir" rev-parse -q --verify "$short^{commit}" >/dev/null && resolves=yes
run "$dir"
if [ -n "$digits" ] && [ "$resolves" = yes ] && [ "$STATUS" -eq 1 ] && grep -q '^FAIL check-commits: 2 finding(s)' <<<"$OUT" &&
  grep -qF 'the number 9999999 is in the body' <<<"$OUT" && grep -qF "the number $short is in the body" <<<"$OUT" &&
  ! grep -qF "the number $digits " <<<"$OUT"; then
  result "check-commits: 7 or more digits that git resolves to a commit are a reference; fewer are a number" yes ""
else
  result "check-commits: 7 or more digits that git resolves to a commit are a reference; fewer are a number" no "digit-only hash: ${digits:-none found}; git resolves $short: $resolves
$(describe)"
fi

# 11. A version matches with or without a leading "v": 0.9.0 in a body is sourced by v0.9.0
# in the diff, and 1.2.3 by v1.2.3 on a Told: line; 0.7.0 has no source.
dir="$(new_repo versions)"
printf 'hello\nref: v0.9.0\n' >"$dir/app.txt"
commit "$dir" $'Pin\n\nPins 0.9.0, after 1.2.3 upstream; 0.7.0 was the last.\nTold: v1.2.3, from the release page.'
run "$dir"
if [ "$STATUS" -eq 1 ] && grep -q '^FAIL check-commits: 1 finding(s)' <<<"$OUT" &&
  grep -qF 'the number 0.7.0 is in the body' <<<"$OUT"; then
  result "check-commits: a version matches with or without a leading v" yes ""
else
  result "check-commits: a version matches with or without a leading v" no "$(describe)"
fi

# 12. A "Decision:" line (with the lines it continues onto) that names a path in
# .harness/removed-paths fails, naming the commit and the path: in full, or under a removed
# folder, also on a line the Decision: continues onto. The same words on an "Upstream:"
# line, a Decision: naming only the file name, or the path on a line before it pass.
dir="$(new_repo decisions)"
printf 'old/\nlib/gone.js\n' >"$dir/.harness/removed-paths"
commit "$dir" $'Remove the old tools\n\n.harness/removed-paths lists them now.\nDecision: keep lib/gone.js out.'
git -C "$dir" commit -q --allow-empty -m $'Notes\n\nlib/gone.js is mentioned here.\nUpstream: old/tool.sh stays upstream.\nDecision: gone.js is not coming back.'
git -C "$dir" commit -q --allow-empty -m $'More\n\nDecision: the migration\n  moves old/ away.'
run "$dir"
if [ "$STATUS" -eq 1 ] && grep -q '^FAIL check-commits: 2 finding(s)' <<<"$OUT" &&
  grep -qF '(c) '"$(git -C "$dir" rev-parse --short=12 HEAD~2)"' "Remove the old tools": a "Decision:" line names lib/gone.js, which .harness/removed-paths lists, so it is not this project'"'"'s decision. Fix: reword that commit, relabelling the line "Upstream:"' <<<"$OUT" &&
  grep -qF '(c) '"$(git -C "$dir" rev-parse --short=12 HEAD)"' "More": a "Decision:" line names old/' <<<"$OUT"; then
  result "check-commits: a Decision: line naming a path in .harness/removed-paths fails; Upstream: passes" yes ""
else
  result "check-commits: a Decision: line naming a path in .harness/removed-paths fails; Upstream: passes" no "$(describe)"
fi

# The message mode: check_message DIR MESSAGE: MESSAGE, in a file, checked as the next commit.
check_message() {
  printf '%s\n' "$2" >"$WORK/message.txt"
  run "$1" --message "$WORK/message.txt"
}

# 13. --message judges only what the new commit adds: a protected file in the STAGED
# changes must be named (in the new body or any body on the branch); a number in the new
# body must be in the branch's diff including the staged changes, or on a Told: line
# (the new body's or the branch's); a Decision: line in the new body must not name a
# removed path. An earlier commit's own findings are not the new message's.
dir="$(new_repo message)"
printf 'old/\n' >"$dir/.harness/removed-paths"
printf 'hello\nretries = 7\n' >"$dir/app.txt"
commit "$dir" $'Earlier\n\nIt took 99 tries; nothing sources that here.'
printf 'echo "check: 2 passed"\n' >"$dir/scripts/check.sh"
git -C "$dir" add scripts/check.sh
check_message "$dir" $'Count two checks\n\nRetries are 7; it took 12 runs.\nDecision: old/x.sh stays out.'
bad="$(describe)"
bad_ok=no
if [ "$STATUS" -eq 1 ] && grep -q '^FAIL check-commits: 3 finding(s) in the message in ' <<<"$OUT" &&
  grep -qF "(a) scripts/check.sh is protected (.harness/protected-paths) and changed in this commit, but neither this message's body nor any commit body on the branch names it. Fix: add a line to this message's body with the full path and the reason it changed." <<<"$OUT" &&
  grep -qF '(b) this message: the number 12 is in the body but not in the branch'"'"'s diff and not on a "Told:" line. Fix: put it on a line "Told: 12 <what it is>, <where it came from>" in this message'"'"'s body, or take it out.' <<<"$OUT" &&
  grep -qF '(c) this message: a "Decision:" line names old/' <<<"$OUT" && ! grep -q 'number 99\|number 7 ' <<<"$OUT"; then
  bad_ok=yes
fi
check_message "$dir" $'Count two checks\n\nscripts/check.sh: prints the new count. Retries are 7; it took 12 runs.\nTold: 12 runs, counted by hand.\nUpstream: old/x.sh stays out.'
if [ "$bad_ok" = yes ] && [ "$STATUS" -eq 0 ] && grep -q '^PASS check-commits: the message in .*message.txt, against the staged changes and the branch so far' <<<"$OUT" &&
  [ -z "$(git -C "$dir" log --format=%s -1 --skip 1 | grep Count)" ]; then
  result "check-commits: --message judges the staged changes and the new body only, against the branch so far" yes ""
else
  result "check-commits: --message judges the staged changes and the new body only, against the branch so far" no "unfixed message: $bad
fixed message: $(describe)"
fi

# 14. --message reads the message as git leaves it for the hook: comment lines and the
# scissors line (and what follows) are dropped, so a number there is not checked; the
# subject is the first paragraph. In a repository with no base branch, the staged changes
# alone are the branch.
dir="$WORK/fresh"
mkdir -p "$dir" && git -C "$dir" init -q -b main
printf 'x = 5\n' >"$dir/app.txt"
git -C "$dir" add app.txt
check_message "$dir" $'First commit\nstill the subject 77\n\nSets x to 5.\n# Please enter the commit message; 42 lines.\n# ------------------------ >8 ------------------------\n+ 31 in a diff'
if [ "$STATUS" -eq 0 ] && grep -q '^PASS check-commits: the message in .*, against the staged changes and no branch so far (base branch "main" not found' <<<"$OUT"; then
  result "check-commits: --message drops comment and scissors lines, and works with no base branch" yes ""
else
  result "check-commits: --message drops comment and scissors lines, and works with no base branch" no "$(describe)"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures check-commits case(s) failed"
  exit 1
fi
